// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! The four new `SchedulerService` RPCs (appended to the proto tail) plus the
//! transactional `SubmitPerformanceAttempt` write path (A10 + A8).

use anki_proto::scheduler;
use serde_json::Value;
use std::collections::HashMap;
use std::collections::HashSet;

use super::attempt_log::NewAttempt;
use super::attempt_log::Outcome;
use super::attempt_log::OutcomeStep;
use super::grading;
use super::notetypes::tbs_fields;
use crate::ops::Op;
use crate::prelude::*;

impl Collection {
    /// A10 — grade a submission, persist the Attempt Log note (same txn), and
    /// return per-step credit. Returns `(steps, total_credit,
    /// attempt_note_id)`.
    pub(crate) fn ankountant_submit_performance_attempt(
        &mut self,
        req: scheduler::SubmitPerformanceAttemptRequest,
    ) -> Result<scheduler::SubmitPerformanceAttemptResponse> {
        let item_note_id = NoteId(req.item_note_id);
        let note = self
            .storage
            .get_note(item_note_id)?
            .or_not_found(item_note_id)?;
        let steps_json = note
            .fields()
            .get(tbs_fields::STEPS_JSON)
            .or_invalid("TBS note missing steps_json")?;
        let steps = grading::parse_steps(steps_json).or_invalid("invalid steps_json")?;
        validate_attempt_item(&req.mode, &note, &steps)?;

        // Build the id -> submitted value map from the submission JSON.
        let submitted = parse_submission(&req.mode, &req.submission_json, &steps)?;
        // research = single-citation, all-or-nothing (multi-valued key);
        // everything else (tbs / doc_review) = per-step partial credit.
        let (outcomes, total_credit) = if req.mode == "research" {
            grading::grade_research(&steps, &submitted)
        } else {
            grading::grade(&steps, &submitted)
        };

        // Resolve the item's section (ADR 0008): from its `sec::` tag, falling
        // back to the default for pre-section-dimension notes. The section drives
        // both the confusable map and the sealed-bank lookup below, so an AUD
        // attempt resolves against AUD sets + the AUD sealed deck, not FAR.
        let section = super::note_section(&note.tags)?;
        let map = self.ankountant_confusable_map(&section);
        let schema_tag = note.fields().get(tbs_fields::SCHEMA_TAG).cloned();
        // Also consider the note's ordinary tags for a ds:: match.
        let confusion_set_id = schema_tag
            .as_deref()
            .and_then(|t| Collection::ankountant_set_for_tag(&map, t))
            .or_else(|| {
                note.tags
                    .iter()
                    .find_map(|t| Collection::ankountant_set_for_tag(&map, t))
            })
            .or_invalid("Performance item missing confusion set")?;

        // Is this item in the sealed firewall bank? (Determines Performance.)
        let sealed = self.ankountant_note_is_sealed(item_note_id, &section)?;

        let outcome = Outcome {
            credit: total_credit,
            steps: outcomes
                .iter()
                .map(|o| OutcomeStep {
                    id: o.id.clone(),
                    correct: o.correct,
                    weight: o.weight,
                })
                .collect(),
            // T1 AC2 — record time-to-cite for research attempts only; other
            // modes keep `outcome_json` byte-identical (elapsed_ms omitted).
            elapsed_ms: (req.mode == "research").then_some(req.latency_ms),
        };

        let attempt = NewAttempt {
            item_ref: item_note_id,
            confusion_set_id,
            mode: req.mode.clone(),
            confidence: req.confidence.clone(),
            latency_ms: req.latency_ms,
            outcome,
            section,
            sealed,
        };

        // Ensure the Attempt Log note type + deck exist before the write
        // transaction (their creation is itself transactional; nesting panics).
        self.ankountant_attempt_log_notetype()?;
        let out = self.transact(Op::AddNote, |col| col.ankountant_write_attempt(&attempt))?;
        let attempt_note_id = out.output;

        Ok(scheduler::SubmitPerformanceAttemptResponse {
            steps: outcomes
                .into_iter()
                .map(|o| scheduler::StepResult {
                    id: o.id,
                    correct: o.correct,
                    weight: o.weight,
                })
                .collect(),
            total_credit,
            attempt_note_id: attempt_note_id.0,
        })
    }

    /// True if the note's card lives in the sealed firewall deck for `section`.
    fn ankountant_note_is_sealed(&mut self, nid: NoteId, section: &str) -> Result<bool> {
        let search = format!("nid:{} deck:Ankountant::Sealed::{}::*", nid.0, section);
        if !self.search_notes_unordered(search.as_str())?.is_empty() {
            return Ok(true);
        }
        let stress_search = format!(
            "nid:{} deck:Ankountant::Stress::Sealed::{}::*",
            nid.0, section
        );
        Ok(!self
            .search_notes_unordered(stress_search.as_str())?
            .is_empty())
    }
}

/// Parse a submission into a step-id -> value map.
/// - confusion mode: `{"choice":"X"}` maps to a single step id "choice".
/// - research mode: `{"citation":"ASC …"}` maps to a single step id "citation".
/// - tbs / doc_review mode: `{"steps":[{"id":"l1","value":...}]}` (doc_review
///   reuses this per-step path verbatim — one step per blank).
fn parse_submission(
    mode: &str,
    json: &str,
    expected_steps: &[grading::GradableStep],
) -> Result<HashMap<String, Value>> {
    let mut out = HashMap::new();
    let root: Value = serde_json::from_str(json).or_invalid("invalid submission_json")?;
    let root = root
        .as_object()
        .or_invalid("submission_json must be an object")?;
    match mode {
        "confusion" => {
            let choice = root
                .get("choice")
                .and_then(Value::as_str)
                .or_invalid("confusion submission missing choice")?;
            if choice.trim().is_empty() {
                invalid_input!("confusion submission missing choice");
            }
            out.insert("choice".to_string(), Value::String(choice.to_string()));
        }
        "research" => {
            let citation = root
                .get("citation")
                .and_then(Value::as_str)
                .or_invalid("research submission missing citation")?;
            if citation.trim().is_empty() {
                invalid_input!("research submission missing citation");
            }
            out.insert("citation".to_string(), Value::String(citation.to_string()));
        }
        "tbs" | "doc_review" => {
            let submitted_steps = root
                .get("steps")
                .and_then(Value::as_array)
                .or_invalid("performance submission missing steps")?;
            let expected_ids: HashSet<&str> =
                expected_steps.iter().map(|s| s.id.as_str()).collect();
            for step in submitted_steps {
                let step = step
                    .as_object()
                    .or_invalid("performance submission step must be an object")?;
                let id = step
                    .get("id")
                    .and_then(Value::as_str)
                    .or_invalid("performance submission step missing id")?;
                if id.trim().is_empty() {
                    invalid_input!("performance submission step missing id");
                }
                if !expected_ids.contains(id) {
                    invalid_input!("unknown performance submission step id: {id}");
                }
                let value = step
                    .get("value")
                    .cloned()
                    .or_invalid("performance submission step missing value")?;
                if out.insert(id.to_string(), value).is_some() {
                    invalid_input!("duplicate performance submission step id: {id}");
                }
            }
        }
        _ => invalid_input!("Unknown performance mode: {mode}"),
    }
    Ok(out)
}

fn validate_attempt_item(mode: &str, note: &Note, steps: &[grading::GradableStep]) -> Result<()> {
    validate_gradable_steps(steps)?;
    let item_kind = note
        .fields()
        .get(tbs_fields::TBS_TYPE)
        .map(String::as_str)
        .or_invalid("TBS note missing tbs_type")?;
    match mode {
        "confusion" if item_kind == "mcq" => {
            if !steps.iter().any(|step| step.id == "choice") {
                invalid_input!("confusion item missing choice step");
            }
            Ok(())
        }
        "research" if item_kind == "research" => {
            if !steps.iter().any(|step| step.id == "citation") {
                invalid_input!("research item missing citation step");
            }
            Ok(())
        }
        "doc_review" if item_kind == "doc_review" => Ok(()),
        "tbs" if matches!(item_kind, "journal_entry" | "numeric") => Ok(()),
        "confusion" | "research" | "doc_review" | "tbs" => {
            invalid_input!("performance mode {mode} does not match item type {item_kind}")
        }
        _ => invalid_input!("Unknown performance mode: {mode}"),
    }
}

fn validate_gradable_steps(steps: &[grading::GradableStep]) -> Result<()> {
    if let Err(message) = grading::validate_steps(steps) {
        invalid_input!("{message}");
    }
    Ok(())
}

// SchedulerService RPC glue lives in scheduler/service/mod.rs; the thin impls
// there dispatch into the collection-facing helpers above and in the sibling
// modules (schedule.rs, confusion.rs, readiness.rs).
