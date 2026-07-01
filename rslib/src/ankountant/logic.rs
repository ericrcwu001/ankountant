// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Pure, side-effect-free Ankountant computations: the deadline-anchored
//! retention ramp (A1), the Wilson readiness band (A5), the confusion-queue
//! interleave (A3), and the step-grading tolerance checks (A10).
//!
//! Keeping these free of `Collection` lets them be unit-tested directly and
//! reused by the RPC service impls.

use super::constants;

/// A1 — deadline-anchored desired-retention ramp.
///
/// `days_to_exam >= RAMP_HORIZON_DAYS` (or open horizon handled by the caller)
/// → floor retention; `<= 0` (exam day or past) → peak retention; linear in
/// between. Returns an `f64` in `[RAMP_MIN_RETENTION, RAMP_MAX_RETENTION]`.
pub(crate) fn exam_desired_retention(days_to_exam: i64) -> f64 {
    if days_to_exam >= constants::RAMP_HORIZON_DAYS {
        constants::RAMP_MIN_RETENTION
    } else if days_to_exam <= 0 {
        constants::RAMP_MAX_RETENTION
    } else {
        let span = constants::RAMP_MAX_RETENTION - constants::RAMP_MIN_RETENTION;
        constants::RAMP_MIN_RETENTION
            + span * (constants::RAMP_HORIZON_DAYS - days_to_exam) as f64
                / constants::RAMP_HORIZON_DAYS as f64
    }
}

/// A5 — Wilson score interval (95%) on an observed accuracy, returned as a
/// percentage band `(low, high)` in `0..=100`. Widens as `n` shrinks.
pub(crate) fn wilson_band(correct: f64, total: f64) -> (f64, f64) {
    if total <= 0.0 {
        return (0.0, 100.0);
    }
    // z for 95% two-sided.
    const Z: f64 = 1.959_963_984_540_054;
    let n = total;
    let p = (correct / n).clamp(0.0, 1.0);
    let z2 = Z * Z;
    let denom = 1.0 + z2 / n;
    let centre = p + z2 / (2.0 * n);
    let margin = Z * ((p * (1.0 - p) / n) + z2 / (4.0 * n * n)).sqrt();
    let low = ((centre - margin) / denom).clamp(0.0, 1.0);
    let high = ((centre + margin) / denom).clamp(0.0, 1.0);
    (low * 100.0, high * 100.0)
}

/// A5 — confidence label from sealed-attempt volume.
pub(crate) fn confidence_label(attempts: u32) -> &'static str {
    if attempts >= constants::CONFIDENCE_HIGH_MIN {
        "High"
    } else {
        "Med"
    }
}

/// A3 — interleave items (identified by their confusion tag) so that no tag
/// appears 3+ times in a row, preferring the most-frequent remaining tag that
/// does not break the rule. Input order within a tag is preserved. Returns the
/// reordered indices into `tags`.
///
/// `tags[i]` is the discriminating tag of item `i`; all items belong to the
/// same confusion set. Uses a greedy "pick the tag with the most remaining that
/// is not the last-placed tag when an alternative exists" strategy, which
/// guarantees no 3-in-a-row whenever the multiset admits such an ordering (no
/// single tag is a strict majority beyond what interleaving can absorb).
pub(crate) fn interleave_by_tag(tags: &[String]) -> Vec<usize> {
    use std::collections::BTreeMap;

    // Preserve stable input order per tag via a queue of original indices.
    let mut buckets: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
    for (i, t) in tags.iter().enumerate() {
        buckets.entry(t.as_str()).or_default().push(i);
    }

    let mut out: Vec<usize> = Vec::with_capacity(tags.len());
    let mut last_tag: Option<String> = None;
    let mut run: usize = 0;

    while out.iter().len() < tags.len() {
        // Candidate tags with remaining items.
        let mut candidates: Vec<(&str, usize)> = buckets
            .iter()
            .filter(|(_, v)| !v.is_empty())
            .map(|(k, v)| (*k, v.len()))
            .collect();
        // Sort by most-remaining first, then tag name for determinism.
        candidates.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));

        // If the top candidate would make a 3rd consecutive of the same tag,
        // and another candidate exists, skip to the alternative.
        let pick = if run >= 2 && last_tag.as_deref() == Some(candidates[0].0) {
            candidates
                .iter()
                .find(|(t, _)| Some(*t) != last_tag.as_deref())
                .copied()
                .unwrap_or(candidates[0])
        } else {
            candidates[0]
        };

        let idx = buckets.get_mut(pick.0).unwrap().remove(0);
        out.push(idx);

        if last_tag.as_deref() == Some(pick.0) {
            run += 1;
        } else {
            run = 1;
            last_tag = Some(pick.0.to_string());
        }
    }
    out
}

/// A10 — does an observed numeric value match the answer key within tolerance?
/// Both are parsed leniently (stripping `$ , %` and whitespace); a
/// non-numeric key falls back to a trimmed, case-insensitive string compare.
pub(crate) fn numeric_matches(answer_key: &str, submitted: &str, tolerance: f64) -> bool {
    match (parse_number(answer_key), parse_number(submitted)) {
        (Some(k), Some(v)) => (k - v).abs() <= tolerance,
        _ => normalize_text(answer_key) == normalize_text(submitted),
    }
}

/// A10 — exact (tolerant) match for a text field (e.g. account name, dr/cr).
pub(crate) fn text_matches(answer_key: &str, submitted: &str) -> bool {
    normalize_text(answer_key) == normalize_text(submitted)
}

fn normalize_text(s: &str) -> String {
    s.trim().to_lowercase()
}

fn parse_number(s: &str) -> Option<f64> {
    let cleaned: String = s
        .chars()
        .filter(|c| !matches!(c, '$' | ',' | '%' | ' ' | '\t'))
        .collect();
    if cleaned.is_empty() {
        return None;
    }
    cleaned.parse::<f64>().ok()
}

/// A9/A10 — default equal weights summing to 1.0 for `n` steps.
pub(crate) fn default_weight(n: usize) -> f64 {
    if n == 0 {
        0.0
    } else {
        1.0 / n as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn approx(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-9
    }

    #[test]
    fn ramp_hits_the_pinned_anchor_points() {
        // A1 AC1/AC2/AC3 — exact ramp values.
        assert!(approx(exam_desired_retention(90), 0.80));
        assert!(approx(exam_desired_retention(60), 0.80));
        assert!(approx(exam_desired_retention(30), 0.875));
        assert!(approx(exam_desired_retention(0), 0.95));
        assert!(approx(exam_desired_retention(-5), 0.95));
    }

    #[test]
    fn ramp_is_monotonic_increasing_as_exam_nears() {
        let far = exam_desired_retention(90);
        let mid = exam_desired_retention(30);
        let near = exam_desired_retention(1);
        assert!(far < mid && mid < near);
    }

    #[test]
    fn wilson_band_is_an_interval_not_a_point() {
        let (lo, hi) = wilson_band(20.0, 40.0);
        assert!(lo < hi);
        assert!(lo >= 0.0 && hi <= 100.0);
    }

    #[test]
    fn wilson_band_widens_as_volume_drops_at_fixed_accuracy() {
        // A5 AC4 — 50% on 40 vs 50% on 20 attempts.
        let (l1, h1) = wilson_band(20.0, 40.0);
        let (l2, h2) = wilson_band(10.0, 20.0);
        assert!((h2 - l2) > (h1 - l1));
    }

    #[test]
    fn interleave_never_places_three_in_a_row() {
        let tags: Vec<String> = ["a", "a", "a", "b", "b", "b"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let order = interleave_by_tag(&tags);
        assert_eq!(order.len(), 6);
        let seq: Vec<&str> = order.iter().map(|&i| tags[i].as_str()).collect();
        for w in seq.windows(3) {
            assert!(!(w[0] == w[1] && w[1] == w[2]), "3-in-a-row: {seq:?}");
        }
    }

    #[test]
    fn interleave_handles_lopsided_multiset_without_three_in_a_row() {
        // 4 of "a", 2 of "b", 2 of "c" — still interleavable.
        let mut tags = vec!["a".to_string(); 4];
        tags.extend(vec!["b".to_string(); 2]);
        tags.extend(vec!["c".to_string(); 2]);
        let order = interleave_by_tag(&tags);
        let seq: Vec<&str> = order.iter().map(|&i| tags[i].as_str()).collect();
        for w in seq.windows(3) {
            assert!(!(w[0] == w[1] && w[1] == w[2]), "3-in-a-row: {seq:?}");
        }
    }

    #[test]
    fn numeric_tolerance_matches_within_band_only() {
        assert!(numeric_matches("1000", "1000.40", 0.5));
        assert!(numeric_matches("$1,000.00", "1000", 0.01));
        assert!(!numeric_matches("1000", "1002", 0.5));
    }

    #[test]
    fn text_match_is_case_and_whitespace_insensitive() {
        assert!(text_matches(" Cash ", "cash"));
        assert!(!text_matches("Cash", "Accounts Receivable"));
    }

    #[test]
    fn default_weights_sum_to_one() {
        let w = default_weight(4);
        assert!(approx(w * 4.0, 1.0));
    }
}
