// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! A4/A5 — per-topic Memory / Performance / gap plus the abstain-aware
//! readiness band.
//!
//! - Memory: trailing-30d recall accuracy on the **study pile** (>= 5 reps).
//! - Performance: accuracy on the **sealed bank** only (MCQ + TBS partial
//!   credit, weighted 50/50), from the Attempt Log — never the study pile.
//! - gap = memory - performance.
//! - Readiness: abstain under thin evidence, else a Wilson accuracy band.

use anki_proto::scheduler::GetReadinessResponse;
use anki_proto::scheduler::Readiness;
use anki_proto::scheduler::TopicScore;

use super::constants;
use super::logic;
use crate::prelude::*;
use crate::revlog::RevlogReviewKind;

/// Accumulator for one confusion set's sealed Performance.
#[derive(Default)]
struct PerfAccum {
    mcq_correct: f64,
    mcq_total: f64,
    tbs_credit: f64,
    tbs_total: f64,
}

impl PerfAccum {
    fn performance(&self) -> Option<f64> {
        let mcq = (self.mcq_total > 0.0).then(|| self.mcq_correct / self.mcq_total);
        let tbs = (self.tbs_total > 0.0).then(|| self.tbs_credit / self.tbs_total);
        match (mcq, tbs) {
            (Some(m), Some(t)) => {
                Some(m * constants::PERFORMANCE_MCQ_WEIGHT + t * constants::PERFORMANCE_TBS_WEIGHT)
            }
            (Some(m), None) => Some(m),
            (None, Some(t)) => Some(t),
            (None, None) => None,
        }
    }

    /// Attempts backing this set's Performance — the effective sample size for
    /// its Wilson band (MCQ items + TBS items).
    fn effective_n(&self) -> f64 {
        self.mcq_total + self.tbs_total
    }
}

/// A5 — a Wilson band (as `0..1` fractions) centred on `point` given `n`
/// backing attempts. `(0.0, 0.0)` when there is no evidence.
fn fraction_band(point: f64, n: f64) -> (f64, f64) {
    if n <= 0.0 {
        return (0.0, 0.0);
    }
    let (low, high) = logic::wilson_band(point * n, n);
    (low / 100.0, high / 100.0)
}

impl Collection {
    /// A4/A5 — compute readiness for the section.
    pub(crate) fn ankountant_get_readiness(
        &mut self,
        section: &str,
    ) -> Result<GetReadinessResponse> {
        let map = self.ankountant_confusable_map(section);
        let attempts = self.ankountant_attempts(section)?;

        // --- Performance per set from SEALED attempts only (A4 AC2). ---
        let mut perf: std::collections::BTreeMap<String, PerfAccum> = map
            .keys()
            .map(|k| (k.clone(), PerfAccum::default()))
            .collect();
        let mut sealed_attempts = 0u32;
        let mut sealed_correct = 0.0f64;
        let mut sealed_total = 0.0f64;
        for a in &attempts {
            if !a.sealed {
                // Study-pile attempts never contribute to Performance.
                continue;
            }
            sealed_attempts += 1;
            let acc = perf.entry(a.confusion_set_id.clone()).or_default();
            if logic::is_partial_credit_mode(a.mode.as_str()) {
                // tbs / doc_review: fractional per-step (per-blank) partial credit.
                acc.tbs_credit += a.outcome.credit;
                acc.tbs_total += 1.0;
                sealed_correct += a.outcome.credit;
                sealed_total += 1.0;
            } else {
                // confusion / research / MCQ: pass/fail on credit >= 0.5.
                let c = if a.outcome.credit >= 0.5 { 1.0 } else { 0.0 };
                acc.mcq_correct += c;
                acc.mcq_total += 1.0;
                sealed_correct += c;
                sealed_total += 1.0;
            }
        }

        // --- Memory per set from trailing-30d study-pile recall reps. ---
        let memory = self.ankountant_memory_by_set(section, &map)?;

        // --- Per-topic scores, each with a Wilson band (A4/#3). ---
        let mut topics = Vec::new();
        for set_id in map.keys() {
            let accum = perf.get(set_id);
            let perf_val = accum.and_then(|p| p.performance()).unwrap_or(0.0);
            let (perf_low, perf_high) =
                fraction_band(perf_val, accum.map(|p| p.effective_n()).unwrap_or(0.0));

            let (mem_correct, mem_total) = memory.get(set_id).copied().unwrap_or((0, 0));
            let mem_insufficient = mem_total < constants::MEMORY_MIN_REPS;
            let mem_val = if mem_insufficient {
                0.0
            } else {
                mem_correct as f64 / mem_total as f64
            };
            let (mem_low, mem_high) = if mem_insufficient {
                (0.0, 0.0)
            } else {
                fraction_band(mem_val, mem_total as f64)
            };

            topics.push(TopicScore {
                set_id: set_id.clone(),
                memory: mem_val,
                performance: perf_val,
                gap: mem_val - perf_val,
                memory_insufficient: mem_insufficient,
                memory_low: mem_low,
                memory_high: mem_high,
                performance_low: perf_low,
                performance_high: perf_high,
            });
        }

        // --- Abstain-aware readiness band (A5), projected to CPA 0-99. ---
        let sets_defined = map.len().max(1);
        let sets_covered = map
            .keys()
            .filter(|k| {
                attempts
                    .iter()
                    .any(|a| a.sealed && &a.confusion_set_id == *k)
            })
            .count();
        let coverage = sets_covered as f64 / sets_defined as f64;
        let generated_at = TimestampSecs::now().0;

        let readiness = if sealed_attempts < constants::ABSTAIN_MIN_ATTEMPTS {
            Readiness {
                abstain: true,
                reason: "insufficient volume".to_string(),
                coverage,
                generated_at,
                reasons: abstain_reasons(coverage, sealed_attempts),
                ..Default::default()
            }
        } else if coverage < constants::ABSTAIN_MIN_COVERAGE {
            Readiness {
                abstain: true,
                reason: "insufficient coverage".to_string(),
                coverage,
                generated_at,
                reasons: abstain_reasons(coverage, sealed_attempts),
                ..Default::default()
            }
        } else {
            // Wilson band on sealed accuracy (0..100), mapped onto the CPA
            // scaled-score scale (0..99) through the monotonic ADR-0005 transform.
            let (acc_low, acc_high) = logic::wilson_band(sealed_correct, sealed_total);
            let point_acc = sealed_correct / sealed_total;
            Readiness {
                abstain: false,
                reason: String::new(),
                band_low: logic::cpa_scale_from_accuracy(acc_low / 100.0),
                band_high: logic::cpa_scale_from_accuracy(acc_high / 100.0),
                confidence: logic::confidence_label(sealed_attempts).to_string(),
                point_estimate: logic::cpa_scale_from_accuracy(point_acc),
                coverage,
                generated_at,
                reasons: band_reasons(&topics, &perf, coverage, sealed_attempts),
            }
        };

        Ok(GetReadinessResponse {
            topics,
            readiness: Some(readiness),
        })
    }

    /// Trailing-30d recall reps on study-pile cards per confusion set, as
    /// `(correct, total)` counts (so the caller can form both the accuracy and
    /// its Wilson band). Memory is only meaningful at >= MEMORY_MIN_REPS.
    fn ankountant_memory_by_set(
        &mut self,
        section: &str,
        map: &super::config::ConfusableMap,
    ) -> Result<std::collections::BTreeMap<String, (u32, u32)>> {
        let window_start = TimestampSecs::now().0 - constants::MEMORY_WINDOW_DAYS * 86_400;
        let window_start_ms = window_start * 1000;

        let mut out = std::collections::BTreeMap::new();
        for (set_id, set) in map {
            let mut correct = 0u32;
            let mut total = 0u32;
            for tag in &set.tags {
                // Study-pile cards only (NOT sealed).
                let search = format!("tag:{tag} deck:Ankountant::Study::{section}::*");
                let cids = self.search_cards(search.as_str(), crate::search::SortMode::NoOrder)?;
                for cid in cids {
                    let entries = self.storage.get_revlog_entries_for_card(cid)?;
                    for e in entries {
                        // recall reps only, within the trailing window
                        if e.id.0 < window_start_ms {
                            continue;
                        }
                        if !matches!(
                            e.review_kind,
                            RevlogReviewKind::Review | RevlogReviewKind::Relearning
                        ) {
                            continue;
                        }
                        if e.button_chosen == 0 {
                            continue; // manual reschedule
                        }
                        total += 1;
                        if e.button_chosen > 1 {
                            correct += 1;
                        }
                    }
                }
            }
            out.insert(set_id.clone(), (correct, total));
        }
        Ok(out)
    }
}

/// Pretty-print a snake_case set id for a human-facing reason line.
fn pretty_set_id(set_id: &str) -> String {
    set_id.replace('_', " ")
}

/// Factual reasons shown while abstaining: just the two numbers behind the
/// give-up decision (coverage + volume). No inferred cause.
fn abstain_reasons(coverage: f64, sealed_attempts: u32) -> Vec<String> {
    vec![
        format!("Coverage: {:.0}% of topics", coverage * 100.0),
        format!(
            "Evidence: {sealed_attempts} sealed attempts (need >= {})",
            constants::ABSTAIN_MIN_ATTEMPTS
        ),
    ]
}

/// Factual reasons behind an emitted band: the weakest covered topic, the
/// largest memory-performance gap, and the coverage/volume — all restated
/// numbers, never a claimed cause.
fn band_reasons(
    topics: &[TopicScore],
    perf: &std::collections::BTreeMap<String, PerfAccum>,
    coverage: f64,
    sealed_attempts: u32,
) -> Vec<String> {
    let mut reasons = Vec::new();

    // Weakest topic among those with sealed evidence.
    let weakest = topics
        .iter()
        .filter(|t| perf.get(&t.set_id).map(|p| p.effective_n()).unwrap_or(0.0) > 0.0)
        .min_by(|a, b| a.performance.partial_cmp(&b.performance).unwrap());
    if let Some(t) = weakest {
        reasons.push(format!(
            "Lowest performance: {} ({:.0}%)",
            pretty_set_id(&t.set_id),
            t.performance * 100.0
        ));
    }

    // Largest memory-minus-performance gap among topics with both signals.
    let widest = topics
        .iter()
        .filter(|t| {
            !t.memory_insufficient
                && perf.get(&t.set_id).map(|p| p.effective_n()).unwrap_or(0.0) > 0.0
        })
        .max_by(|a, b| a.gap.partial_cmp(&b.gap).unwrap());
    if let Some(t) = widest {
        if t.gap > 0.0 {
            reasons.push(format!(
                "Largest gap: {} ({:.0} pts)",
                pretty_set_id(&t.set_id),
                t.gap * 100.0
            ));
        }
    }

    reasons.push(format!(
        "Coverage: {:.0}% of topics; {sealed_attempts} sealed attempts",
        coverage * 100.0
    ));
    reasons
}
