// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! A10 — step-graded partial credit for TBS + confusion Performance attempts.
//!
//! A step's `answer_key` is a JSON value; for journal-entry lines it is an
//! object `{account, side, amount}` (or `{account, dr|cr}`); for numeric cells
//! it is a scalar (with optional per-step `tolerance`). Grading is line-by-line
//! so a single wrong amount fails only its own step (method-vs-slip).

use serde::Deserialize;
use serde::Deserializer;
use serde::Serialize;
use serde_json::Value;
use std::collections::HashSet;

use super::constants;
use super::logic;

/// One gradable step parsed from a TBS note's `steps_json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GradableStep {
    pub(crate) id: String,
    pub(crate) answer_key: Value,
    #[serde(default, deserialize_with = "deserialize_optional_f64_field")]
    pub(crate) weight: Option<f64>,
    /// Optional per-step numeric tolerance.
    #[serde(default, deserialize_with = "deserialize_optional_f64_field")]
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

fn deserialize_optional_f64_field<'de, D>(deserializer: D) -> Result<Option<f64>, D::Error>
where
    D: Deserializer<'de>,
{
    match Option::<f64>::deserialize(deserializer)? {
        Some(value) => Ok(Some(value)),
        None => Err(serde::de::Error::custom("expected a number, got null")),
    }
}

/// Effective weight for each step: explicit weight when present, else 1/N.
pub(crate) fn effective_weights(steps: &[GradableStep]) -> Vec<f64> {
    let default = logic::default_weight(steps.len());
    steps.iter().map(|s| s.weight.unwrap_or(default)).collect()
}

pub(crate) fn validate_effective_weights(
    steps: &[GradableStep],
) -> std::result::Result<(), String> {
    if steps.is_empty() {
        return Err("TBS note has no gradable steps".to_string());
    }
    let weights = effective_weights(steps);
    let mut total = 0.0;
    for (step, weight) in steps.iter().zip(weights) {
        if !weight.is_finite() || weight < 0.0 {
            return Err(format!("TBS note has invalid weight for step {}", step.id));
        }
        total += weight;
    }
    if (total - 1.0).abs() > 1e-6 {
        return Err("TBS note step weights must sum to 1.0".to_string());
    }
    Ok(())
}

pub(crate) fn validate_steps(steps: &[GradableStep]) -> std::result::Result<(), String> {
    if steps.is_empty() {
        return Err("TBS note has no gradable steps".to_string());
    }
    let mut ids = HashSet::new();
    for step in steps {
        if step.id.trim().is_empty() {
            return Err("TBS note has blank step id".to_string());
        }
        if !ids.insert(step.id.as_str()) {
            return Err(format!("TBS note has duplicate step id: {}", step.id));
        }
        if step.answer_key.is_null() {
            return Err(format!("TBS note missing answer key for step {}", step.id));
        }
        if let Some(tolerance) = step.tolerance {
            if !tolerance.is_finite() || tolerance < 0.0 {
                return Err(format!(
                    "TBS note has invalid tolerance for step {}",
                    step.id
                ));
            }
        }
    }
    validate_effective_weights(steps)
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

/// T1 — grade a research submission. A research item carries a single gradable
/// step (id `"citation"`) whose `answer_key` is either a scalar canonical
/// citation OR an array of accepted citation variants (spelling variants and,
/// when the author lists them, the exact paragraph and its parent section). The
/// step is correct iff the submitted citation citation-normalizes-equal to ANY
/// accepted variant. Credit is all-or-nothing per step (Σ of correct weights);
/// with the conventional single 1.0-weight step this is exactly 1.0 / 0.0.
/// Time-to-cite is recorded separately (`Outcome.elapsed_ms`), never folded
/// into credit (OQ-2).
pub(crate) fn grade_research(
    steps: &[GradableStep],
    submitted: &std::collections::HashMap<String, Value>,
) -> (Vec<StepOutcome>, f64) {
    let weights = effective_weights(steps);
    let mut total = 0.0;
    let mut outcomes = Vec::with_capacity(steps.len());
    for (step, weight) in steps.iter().zip(weights) {
        let correct = submitted
            .get(&step.id)
            .is_some_and(|v| citation_step_matches(&step.answer_key, v));
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

/// Match a submitted citation against a research step's `answer_key`, which is
/// a scalar OR an array of accepted variants.
fn citation_step_matches(answer_key: &Value, submitted: &Value) -> bool {
    let sub = value_to_plain_string(submitted);
    match answer_key {
        Value::Array(accepted) => accepted
            .iter()
            .any(|a| logic::citation_matches(&value_to_plain_string(a), &sub)),
        other => logic::citation_matches(&value_to_plain_string(other), &sub),
    }
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

    fn research_step(answer_key: Value) -> Vec<GradableStep> {
        vec![GradableStep {
            id: "citation".into(),
            answer_key,
            weight: Some(1.0),
            tolerance: None,
        }]
    }

    fn cite(value: &str) -> HashMap<String, Value> {
        let mut sub = HashMap::new();
        sub.insert("citation".into(), serde_json::json!(value));
        sub
    }

    #[test]
    fn research_all_or_nothing_with_normalization() {
        // T1 AC1 — one citation step; correct is 1.0, else 0.0, and spelling
        // variants normalize-match.
        let steps = research_step(serde_json::json!(["ASC 606-10-32-31"]));
        let (out, total) = grade_research(&steps, &cite("fasb asc 606 10 32 31"));
        assert!(out[0].correct);
        assert!((total - 1.0).abs() < 1e-9);

        let (out, total) = grade_research(&steps, &cite("ASC 606-10-32-39"));
        assert!(!out[0].correct);
        assert!(total.abs() < 1e-9);

        // A blank/missing citation is wrong, not a panic.
        let (out, total) = grade_research(&steps, &HashMap::new());
        assert!(!out[0].correct);
        assert!(total.abs() < 1e-9);
    }

    #[test]
    fn research_multi_valued_key_accepts_any_listed_variant() {
        // T1 — multi-valued accepted list: exact paragraph, spelling variant,
        // AND the parent section are all accepted (the key lists them); an
        // unlisted sibling paragraph is not.
        let steps = research_step(serde_json::json!([
            "ASC 842-20-25-1",
            "842-20-25-01",
            "ASC 842-20-25" // parent section, explicitly accepted
        ]));
        assert!(grade_research(&steps, &cite("842-20-25-1")).0[0].correct);
        assert!(grade_research(&steps, &cite("FASB ASC 842-20-25-1")).0[0].correct);
        // Section-vs-paragraph acceptance: submitting the parent section is OK
        // because the key lists it.
        assert!(grade_research(&steps, &cite("ASC 842-20-25")).0[0].correct);
        // A sibling paragraph the key does NOT list is wrong.
        assert!(!grade_research(&steps, &cite("ASC 842-20-25-4")).0[0].correct);
    }

    #[test]
    fn research_scalar_key_also_supported() {
        // The answer_key may be a bare string, not only an array.
        let steps = research_step(serde_json::json!("ASC 360-10-30-1"));
        assert!(grade_research(&steps, &cite("asc 360 10 30 1")).0[0].correct);
        assert!(!grade_research(&steps, &cite("asc 360 10 30 9")).0[0].correct);
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

    #[test]
    fn explicit_null_numeric_fields_are_invalid() {
        assert!(parse_steps(r#"[{"id":"a","answer_key":1,"weight":null}]"#).is_err());
        assert!(parse_steps(r#"[{"id":"a","answer_key":1,"tolerance":null}]"#).is_err());
    }
}
