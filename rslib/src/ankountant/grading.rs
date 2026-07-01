// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! A10 — step-graded partial credit for TBS + confusion Performance attempts.
//!
//! A step's `answer_key` is a JSON value; for journal-entry lines it is an
//! object `{account, side, amount}` (or `{account, dr|cr}`); for numeric cells
//! it is a scalar (with optional per-step `tolerance`). Grading is line-by-line
//! so a single wrong amount fails only its own step (method-vs-slip).

use serde::Deserialize;
use serde::Serialize;
use serde_json::Value;

use super::constants;
use super::logic;

/// One gradable step parsed from a TBS note's `steps_json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GradableStep {
    pub(crate) id: String,
    pub(crate) answer_key: Value,
    #[serde(default)]
    pub(crate) weight: Option<f64>,
    /// Optional per-step numeric tolerance.
    #[serde(default)]
    pub(crate) tolerance: Option<f64>,
}

#[derive(Debug, Clone)]
pub(crate) struct StepOutcome {
    pub(crate) id: String,
    pub(crate) correct: bool,
    pub(crate) weight: f64,
}

/// Parse `steps_json`, filling in equal default weights (1/N) when a step
/// omits its weight.
pub(crate) fn parse_steps(steps_json: &str) -> Result<Vec<GradableStep>, serde_json::Error> {
    let steps: Vec<GradableStep> = serde_json::from_str(steps_json)?;
    Ok(steps)
}

/// Effective weight for each step: explicit weight when present, else 1/N.
pub(crate) fn effective_weights(steps: &[GradableStep]) -> Vec<f64> {
    let default = logic::default_weight(steps.len());
    steps.iter().map(|s| s.weight.unwrap_or(default)).collect()
}

/// Grade a submission against the parsed steps. `submitted` maps step id ->
/// submitted value. Returns per-step outcomes and the total credit fraction
/// `Σ(weight × correct)`.
pub(crate) fn grade(
    steps: &[GradableStep],
    submitted: &std::collections::HashMap<String, Value>,
) -> (Vec<StepOutcome>, f64) {
    let weights = effective_weights(steps);
    let mut total = 0.0;
    let mut outcomes = Vec::with_capacity(steps.len());
    for (step, weight) in steps.iter().zip(weights) {
        let value = submitted.get(&step.id);
        let correct = value.is_some_and(|v| step_matches(step, v));
        if correct {
            total += weight;
        }
        outcomes.push(StepOutcome {
            id: step.id.clone(),
            correct,
            weight,
        });
    }
    (outcomes, total)
}

fn step_matches(step: &GradableStep, submitted: &Value) -> bool {
    let tolerance = step
        .tolerance
        .unwrap_or(constants::DEFAULT_NUMERIC_TOLERANCE);
    match (&step.answer_key, submitted) {
        // Journal-entry line: match every keyed sub-field.
        (Value::Object(key_obj), Value::Object(sub_obj)) => {
            key_obj.iter().all(|(field, key_val)| {
                sub_obj
                    .get(field)
                    .is_some_and(|sub_val| scalar_matches(key_val, sub_val, tolerance))
            })
        }
        // Numeric / scalar cell.
        (key_val, sub_val) => scalar_matches(key_val, sub_val, tolerance),
    }
}

fn scalar_matches(key: &Value, submitted: &Value, tolerance: f64) -> bool {
    match (key, submitted) {
        (Value::Number(_), _) | (_, Value::Number(_)) => logic::numeric_matches(
            &value_to_plain_string(key),
            &value_to_plain_string(submitted),
            tolerance,
        ),
        _ => {
            // Try numeric first (handles "$1,000" strings), fall back to text.
            let ks = value_to_plain_string(key);
            let ss = value_to_plain_string(submitted);
            logic::numeric_matches(&ks, &ss, tolerance) || logic::text_matches(&ks, &ss)
        }
    }
}

fn value_to_plain_string(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    fn je_steps() -> Vec<GradableStep> {
        // 4 JE lines, equal weights (default 1/N == 0.25).
        serde_json::from_str(
            r#"[
              {"id":"l1","answer_key":{"account":"Cash","side":"dr","amount":1000}},
              {"id":"l2","answer_key":{"account":"Lease Liability","side":"cr","amount":600}},
              {"id":"l3","answer_key":{"account":"ROU Asset","side":"dr","amount":600}},
              {"id":"l4","answer_key":{"account":"Interest Expense","side":"dr","amount":40}}
            ]"#,
        )
        .unwrap()
    }

    #[test]
    fn four_line_je_three_correct_one_wrong_amount_scores_075() {
        // A10 AC1 — [ok,ok,ok,wrong], total 0.75.
        let steps = je_steps();
        let mut sub: HashMap<String, Value> = HashMap::new();
        sub.insert(
            "l1".into(),
            serde_json::json!({"account":"Cash","side":"dr","amount":1000}),
        );
        sub.insert(
            "l2".into(),
            serde_json::json!({"account":"Lease Liability","side":"cr","amount":600}),
        );
        sub.insert(
            "l3".into(),
            serde_json::json!({"account":"ROU Asset","side":"dr","amount":600}),
        );
        // wrong amount only on l4
        sub.insert(
            "l4".into(),
            serde_json::json!({"account":"Interest Expense","side":"dr","amount":99}),
        );

        let (outcomes, total) = grade(&steps, &sub);
        let flags: Vec<bool> = outcomes.iter().map(|o| o.correct).collect();
        assert_eq!(flags, vec![true, true, true, false]);
        assert!((total - 0.75).abs() < 1e-9);
    }

    #[test]
    fn single_wrong_amount_fails_only_that_line() {
        // A10 AC2.
        let steps = je_steps();
        let mut sub: HashMap<String, Value> = HashMap::new();
        for step in &steps {
            sub.insert(step.id.clone(), step.answer_key.clone());
        }
        // Corrupt only l2's amount.
        sub.insert(
            "l2".into(),
            serde_json::json!({"account":"Lease Liability","side":"cr","amount":1}),
        );
        let (outcomes, total) = grade(&steps, &sub);
        assert!(!outcomes[1].correct);
        assert!(outcomes[0].correct && outcomes[2].correct && outcomes[3].correct);
        assert!((total - 0.75).abs() < 1e-9);
    }

    #[test]
    fn numeric_cells_graded_per_cell_with_tolerance() {
        // A10 AC3 — per-cell numeric tolerance.
        let steps: Vec<GradableStep> = serde_json::from_str(
            r#"[
              {"id":"c1","answer_key":250000,"tolerance":1.0},
              {"id":"c2","answer_key":12500,"tolerance":1.0}
            ]"#,
        )
        .unwrap();
        let mut sub: HashMap<String, Value> = HashMap::new();
        sub.insert("c1".into(), serde_json::json!(250000.5)); // within tolerance
        sub.insert("c2".into(), serde_json::json!(12600)); // outside tolerance
        let (outcomes, total) = grade(&steps, &sub);
        assert!(outcomes[0].correct);
        assert!(!outcomes[1].correct);
        assert!((total - 0.5).abs() < 1e-9);
    }

    #[test]
    fn explicit_weights_are_honoured() {
        let steps: Vec<GradableStep> = serde_json::from_str(
            r#"[
              {"id":"a","answer_key":1,"weight":0.7},
              {"id":"b","answer_key":2,"weight":0.3}
            ]"#,
        )
        .unwrap();
        let mut sub: HashMap<String, Value> = HashMap::new();
        sub.insert("a".into(), serde_json::json!(1));
        sub.insert("b".into(), serde_json::json!(999));
        let (_, total) = grade(&steps, &sub);
        assert!((total - 0.7).abs() < 1e-9);
    }
}
