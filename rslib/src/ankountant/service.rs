// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! The four new `SchedulerService` RPCs (appended to the proto tail) plus the
//! transactional `SubmitPerformanceAttempt` write path (A10 + A8).

use std::collections::HashMap;

use anki_proto::scheduler;
use serde_json::Value;

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
            .cloned()
            .unwrap_or_default();
        let steps = grading::parse_steps(&steps_json).or_invalid("invalid steps_json")?;

        // Build the id -> submitted value map from the submission JSON.
        let submitted = parse_submission(&req.mode, &req.submission_json)?;
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
            .unwrap_or_default();

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
        Ok(!self.search_notes_unordered(search.as_str())?.is_empty())
    }
}

/// Parse a submission into a step-id -> value map.
/// - confusion mode: `{"choice":"X"}` maps to a single step id "choice".
/// - research mode: `{"citation":"ASC …"}` maps to a single step id "citation".
/// - tbs / doc_review mode: `{"steps":[{"id":"l1","value":...}]}` (doc_review
///   reuses this per-step path verbatim — one step per blank).
fn parse_submission(mode: &str, json: &str) -> Result<HashMap<String, Value>> {
    let mut out = HashMap::new();
    let root: Value = serde_json::from_str(json).or_invalid("invalid submission_json")?;
    match mode {
        "confusion" => {
            if let Some(choice) = root.get("choice") {
                out.insert("choice".to_string(), choice.clone());
            }
        }
        "research" => {
            if let Some(citation) = root.get("citation") {
                out.insert("citation".to_string(), citation.clone());
            }
        }
        _ => {
            if let Some(steps) = root.get("steps").and_then(|v| v.as_array()) {
                for step in steps {
                    if let (Some(id), Some(value)) = (step.get("id"), step.get("value")) {
                        if let Some(id) = id.as_str() {
                            out.insert(id.to_string(), value.clone());
                        }
                    }
                }
            }
        }
    }
    Ok(out)
}

// SchedulerService RPC glue lives in scheduler/service/mod.rs; the thin impls
// there dispatch into the collection-facing helpers above and in the sibling
// modules (schedule.rs, confusion.rs, readiness.rs).
