// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

use std::collections::BTreeMap;

use serde_json::json;
use serde_json::Value;

use super::constants;
use super::evidence;
use super::logic;
use crate::prelude::*;

struct TopicFixture {
    topic: &'static str,
    memory_train: &'static [bool],
    memory_held_out: &'static [bool],
    performance_train: &'static [bool],
    performance_held_out: &'static [bool],
}

#[derive(Clone)]
struct PredictionRow {
    id: u32,
    topic: &'static str,
    prediction: f64,
    outcome: bool,
}

struct CalibrationBin {
    label: String,
    mean_prediction: f64,
    observed: f64,
    total: usize,
    correct: usize,
    absolute_error: f64,
}

struct Evaluation {
    rows: Vec<PredictionRow>,
    brier: f64,
    log_loss: f64,
    calibration: Vec<CalibrationBin>,
}

fn fixtures() -> Vec<TopicFixture> {
    vec![
        TopicFixture {
            topic: "capitalize_vs_expense",
            memory_train: &[true, true, true, true, true, true, true, true, false, false],
            memory_held_out: &[true, true, true, true, false],
            performance_train: &[
                true, true, true, true, true, true, true, false, false, false,
            ],
            performance_held_out: &[true, true, true, false, false],
        },
        TopicFixture {
            topic: "operating_vs_finance_lease",
            memory_train: &[
                true, true, true, true, true, true, true, false, false, false,
            ],
            memory_held_out: &[true, true, true, false, false],
            performance_train: &[
                true, true, true, true, true, true, false, false, false, false,
            ],
            performance_held_out: &[true, true, true, false, false],
        },
        TopicFixture {
            topic: "revrec_step_selection",
            memory_train: &[true, true, true, true, true, true, true, true, true, false],
            memory_held_out: &[true, true, true, true, false],
            performance_train: &[true, true, true, true, true, true, true, true, false, false],
            performance_held_out: &[true, true, true, true, false],
        },
        TopicFixture {
            topic: "trading_afs_htm",
            memory_train: &[
                true, true, true, true, true, true, false, false, false, false,
            ],
            memory_held_out: &[true, true, true, false, false],
            performance_train: &[
                true, true, true, true, true, false, false, false, false, false,
            ],
            performance_held_out: &[true, true, false, false, false],
        },
        TopicFixture {
            topic: "tax_book_vs_tax_basis",
            memory_train: &[
                true, true, true, true, true, false, false, false, false, false,
            ],
            memory_held_out: &[true, true, false, false, false],
            performance_train: &[
                true, true, true, true, false, false, false, false, false, false,
            ],
            performance_held_out: &[true, true, false, false, false],
        },
    ]
}

fn accuracy(outcomes: &[bool]) -> f64 {
    let correct = outcomes.iter().filter(|&&b| b).count() as f64;
    correct / outcomes.len() as f64
}

fn evaluation(rows: Vec<PredictionRow>) -> Evaluation {
    let n = rows.len() as f64;
    let brier = rows
        .iter()
        .map(|r| {
            let y = if r.outcome { 1.0 } else { 0.0 };
            (r.prediction - y).powi(2)
        })
        .sum::<f64>()
        / n;
    let log_loss = rows
        .iter()
        .map(|r| {
            let p = r.prediction.clamp(1e-12, 1.0 - 1e-12);
            if r.outcome {
                -p.ln()
            } else {
                -(1.0 - p).ln()
            }
        })
        .sum::<f64>()
        / n;

    let mut bins: BTreeMap<u32, (f64, usize, usize)> = BTreeMap::new();
    for r in &rows {
        let bucket = (r.prediction * 10.0).floor().clamp(0.0, 9.0) as u32;
        let entry = bins.entry(bucket).or_default();
        entry.0 += r.prediction;
        entry.1 += 1;
        entry.2 += usize::from(r.outcome);
    }
    let calibration = bins
        .into_iter()
        .map(|(bucket, (prediction_sum, total, correct))| {
            let mean_prediction = prediction_sum / total as f64;
            let observed = correct as f64 / total as f64;
            CalibrationBin {
                label: format!("{}-{}%", bucket * 10, bucket * 10 + 9),
                mean_prediction,
                observed,
                total,
                correct,
                absolute_error: (mean_prediction - observed).abs(),
            }
        })
        .collect();

    Evaluation {
        rows,
        brier,
        log_loss,
        calibration,
    }
}

fn memory_evaluation() -> Evaluation {
    let mut rows = Vec::new();
    for (topic_index, fixture) in fixtures().iter().enumerate() {
        let prediction = accuracy(fixture.memory_train);
        for (i, &outcome) in fixture.memory_held_out.iter().enumerate() {
            rows.push(PredictionRow {
                id: 10_000 + topic_index as u32 * 100 + i as u32,
                topic: fixture.topic,
                prediction,
                outcome,
            });
        }
    }
    evaluation(rows)
}

fn performance_evaluation() -> Evaluation {
    let mut rows = Vec::new();
    for (topic_index, fixture) in fixtures().iter().enumerate() {
        let prediction = accuracy(fixture.performance_train);
        for (i, &outcome) in fixture.performance_held_out.iter().enumerate() {
            rows.push(PredictionRow {
                id: 20_000 + topic_index as u32 * 100 + i as u32,
                topic: fixture.topic,
                prediction,
                outcome,
            });
        }
    }
    evaluation(rows)
}

fn rows_json(rows: &[PredictionRow]) -> Vec<Value> {
    rows.iter()
        .map(|r| {
            json!({
                "id": r.id,
                "topic": r.topic,
                "prediction": r.prediction,
                "outcome": r.outcome,
            })
        })
        .collect()
}

fn calibration_json(rows: &[CalibrationBin]) -> Vec<Value> {
    rows.iter()
        .map(|r| {
            json!({
                "bucket": r.label,
                "mean_prediction": r.mean_prediction,
                "observed": r.observed,
                "total": r.total,
                "correct": r.correct,
                "absolute_error": r.absolute_error,
            })
        })
        .collect()
}

fn score_mapping_json(performance: &Evaluation) -> Value {
    let correct = performance.rows.iter().filter(|r| r.outcome).count() as f64;
    let total = performance.rows.len() as f64;
    let point_accuracy = correct / total;
    let (low_accuracy_pct, high_accuracy_pct) = logic::wilson_band(correct, total);
    let low_accuracy = low_accuracy_pct / 100.0;
    let high_accuracy = high_accuracy_pct / 100.0;
    let point_score = logic::cpa_scale_from_accuracy(point_accuracy);
    let low_score = logic::cpa_scale_from_accuracy(low_accuracy);
    let high_score = logic::cpa_scale_from_accuracy(high_accuracy);

    json!({
        "exam": "CPA FAR",
        "method": "Map held-out sealed exam-style accuracy to the CPA 0-99 readiness scale with the ADR-0005 monotonic piecewise-linear transform; 75% accuracy maps to the CPA pass line of 75. The range maps the Wilson 95% accuracy band endpoints through the same transform.",
        "held_out_correct": correct,
        "held_out_total": total,
        "point_accuracy": point_accuracy,
        "accuracy_low": low_accuracy,
        "accuracy_high": high_accuracy,
        "point_estimate": point_score,
        "band_low": low_score,
        "band_high": high_score,
        "range": format!("{low_score:.1} to {high_score:.1}"),
        "anchors": [
            {"accuracy": 0.0, "score": logic::cpa_scale_from_accuracy(0.0)},
            {"accuracy": constants::CPA_PASS_ACCURACY, "score": logic::cpa_scale_from_accuracy(constants::CPA_PASS_ACCURACY)},
            {"accuracy": 1.0, "score": logic::cpa_scale_from_accuracy(1.0)}
        ],
    })
}

fn split_manifest(memory: &Evaluation, performance: &Evaluation) -> Value {
    json!({
        "rule": "Static deterministic fixture: per topic, 10 authored outcomes train the estimator and 5 later authored outcomes are held out. Held-out ids are disjoint from train ids by construction.",
        "memory_held_out_ids": memory.rows.iter().map(|r| r.id).collect::<Vec<_>>(),
        "performance_held_out_ids": performance.rows.iter().map(|r| r.id).collect::<Vec<_>>(),
        "memory_held_out_count": memory.rows.len(),
        "performance_held_out_count": performance.rows.len(),
    })
}

fn classification_accuracy(rows: &[PredictionRow]) -> f64 {
    let correct = rows
        .iter()
        .filter(|r| (r.prediction >= 0.5) == r.outcome)
        .count();
    correct as f64 / rows.len() as f64
}

fn build_report() -> Value {
    let memory = memory_evaluation();
    let performance = performance_evaluation();
    let split = split_manifest(&memory, &performance);
    let split_repeat = split_manifest(&memory_evaluation(), &performance_evaluation());
    let performance_correct = performance.rows.iter().filter(|r| r.outcome).count();
    let performance_total = performance.rows.len();
    let performance_accuracy = performance_correct as f64 / performance_total as f64;
    let score_mapping = score_mapping_json(&performance);
    let score_range_ordered = score_mapping["band_low"].as_f64().unwrap()
        < score_mapping["point_estimate"].as_f64().unwrap()
        && score_mapping["point_estimate"].as_f64().unwrap()
            < score_mapping["band_high"].as_f64().unwrap();

    json!({
        "title": "Held-out model evidence — calibration, performance, score range",
        "generated_at": TimestampSecs::now().0,
        "reproduce": "just ankountant-evidence",
        "scope_note": "Deterministic backend fixture for Sunday verification-page inputs. It proves held-out split reproducibility and metric/report generation; it is not a real-student external validation sample.",
        "split": split,
        "verdicts": {
            "split_reproducible": split == split_repeat,
            "held_out_sets_non_empty": !memory.rows.is_empty() && !performance.rows.is_empty(),
            "score_range_ordered": score_range_ordered,
        },
        "memory": {
            "model": "Per-topic Memory prediction is the training split's trailing-review recall rate; calibration is evaluated only on held-out recall outcomes.",
            "held_out_reviews": memory.rows.len(),
            "brier": memory.brier,
            "log_loss": memory.log_loss,
            "calibration": calibration_json(&memory.calibration),
            "rows": rows_json(&memory.rows),
        },
        "performance": {
            "model": "Per-topic Performance prediction is the training split's sealed exam-style accuracy; held-out accuracy is evaluated on disjoint sealed exam-style outcomes.",
            "held_out_questions": performance_total,
            "held_out_correct": performance_correct,
            "held_out_accuracy": performance_accuracy,
            "classification_accuracy_at_50_pct": classification_accuracy(&performance.rows),
            "brier": performance.brier,
            "log_loss": performance.log_loss,
            "calibration": calibration_json(&performance.calibration),
            "rows": rows_json(&performance.rows),
        },
        "score_mapping": score_mapping,
    })
}

#[test]
fn models_evidence_uses_held_out_rows_for_memory_metrics() {
    let memory = memory_evaluation();
    assert_eq!(memory.rows.len(), 25);
    assert!(memory.brier.is_finite());
    assert!(memory.log_loss.is_finite());
    assert!(memory.calibration.len() >= 4);
    for row in &memory.rows {
        assert!(row.id >= 10_000);
    }
}

#[test]
fn models_evidence_reports_performance_accuracy_and_ordered_score_range() {
    let performance = performance_evaluation();
    let score = score_mapping_json(&performance);
    assert_eq!(performance.rows.len(), 25);
    assert!(score["band_low"].as_f64().unwrap() < score["point_estimate"].as_f64().unwrap());
    assert!(score["point_estimate"].as_f64().unwrap() < score["band_high"].as_f64().unwrap());
    assert_eq!(
        score["anchors"][1]["score"].as_f64().unwrap(),
        constants::CPA_PASS_SCORE
    );
}

#[test]
#[ignore = "evidence emitter; run via `just ankountant-evidence`"]
fn emit_models_evidence() {
    let data = build_report();
    assert!(data["verdicts"]["split_reproducible"].as_bool().unwrap());
    assert!(data["verdicts"]["held_out_sets_non_empty"]
        .as_bool()
        .unwrap());
    assert!(data["verdicts"]["score_range_ordered"].as_bool().unwrap());
    evidence::write_artifact("models", evidence::MODELS_TEMPLATE, &data);
}
