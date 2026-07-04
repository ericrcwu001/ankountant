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

/// A2 — should this answer defund a "too-easy" rote card?
///
/// True only for a rote card that is stable (interval >= the floor, so never
/// new/learning), answered correctly (Good/Easy) with a recorded pre-reveal
/// confidence of "Confident", in under `TOO_EASY_FAST_FACTOR` x its latency
/// baseline. `rating` is the answer-button number (1=Again..4=Easy).
pub(crate) fn too_easy_defund(
    interval_days: u32,
    taken_millis: u32,
    baseline_ms: f64,
    confidence: Option<&str>,
    rating: u8,
    is_rote: bool,
) -> bool {
    let correct = matches!(rating, 3 | 4);
    let confident = matches!(confidence, Some(c) if c.eq_ignore_ascii_case("confident"));
    let stable = interval_days >= constants::TOO_EASY_STABLE_FLOOR_DAYS;
    let fast =
        baseline_ms > 0.0 && (taken_millis as f64) < constants::TOO_EASY_FAST_FACTOR * baseline_ms;
    is_rote && stable && correct && confident && fast
}

/// Decode a card's `custom_data` JSON object (empty/invalid -> empty map).
fn custom_data_map(custom_data: &str) -> serde_json::Map<String, serde_json::Value> {
    if custom_data.trim().is_empty() {
        return serde_json::Map::new();
    }
    serde_json::from_str(custom_data).unwrap_or_default()
}

/// A2 — the pre-reveal confidence level recorded on the card (B1 writes `cf`).
pub(crate) fn custom_data_confidence(custom_data: &str) -> Option<String> {
    custom_data_map(custom_data)
        .get("cf")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

/// A2 — is the card currently flagged too-easy (`te == 1`)?
pub(crate) fn custom_data_too_easy(custom_data: &str) -> bool {
    custom_data_map(custom_data)
        .get("te")
        .and_then(|v| v.as_i64())
        == Some(1)
}

/// A2 — return `custom_data` with the too-easy flag set (`te = 1`), preserving
/// every other key (confidence, FSRS scheduling state, ...).
pub(crate) fn custom_data_with_te(custom_data: &str) -> String {
    let mut map = custom_data_map(custom_data);
    map.insert("te".to_string(), serde_json::json!(1));
    serde_json::to_string(&map).unwrap_or_default()
}

/// A2 — return `custom_data` with the too-easy flag cleared, preserving every
/// other key. Serializes to `{}` (treated as empty) when nothing else remains.
pub(crate) fn custom_data_without_te(custom_data: &str) -> String {
    let mut map = custom_data_map(custom_data);
    if map.remove("te").is_none() {
        return custom_data.to_string();
    }
    if map.is_empty() {
        return String::new();
    }
    serde_json::to_string(&map).unwrap_or_default()
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

/// A5 — project a sealed-bank accuracy in `0..=1` onto the CPA scaled-score
/// scale (`CPA_MIN_SCORE..=CPA_MAX_SCORE`, pass = `CPA_PASS_SCORE`) via a
/// documented, monotonic piecewise-linear transform anchored on the pass line
/// (`CPA_PASS_ACCURACY` -> `CPA_PASS_SCORE`).
///
/// This is an explicit, auditable heuristic — NOT the (non-public) AICPA
/// scaling — hence the "rough projection" label in the UI. Because it is
/// monotonic, mapping the two endpoints of a Wilson accuracy band through it
/// yields a valid CPA band (low stays below high). See ADR 0005.
pub(crate) fn cpa_scale_from_accuracy(accuracy: f64) -> f64 {
    let acc = accuracy.clamp(0.0, 1.0);
    if acc <= constants::CPA_PASS_ACCURACY {
        // [0, pass_acc] -> [min, pass_score]
        let frac = if constants::CPA_PASS_ACCURACY > 0.0 {
            acc / constants::CPA_PASS_ACCURACY
        } else {
            0.0
        };
        constants::CPA_MIN_SCORE + (constants::CPA_PASS_SCORE - constants::CPA_MIN_SCORE) * frac
    } else {
        // (pass_acc, 1] -> (pass_score, max]
        let span = (1.0 - constants::CPA_PASS_ACCURACY).max(f64::EPSILON);
        let frac = (acc - constants::CPA_PASS_ACCURACY) / span;
        constants::CPA_PASS_SCORE + (constants::CPA_MAX_SCORE - constants::CPA_PASS_SCORE) * frac
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

/// A4 — modes whose stored `credit` is fractional partial credit (averaged into
/// Performance) rather than pass/fail. `research` is not here because it is
/// correctness-only; readiness still scores it on the TBS side of the 50/50 mix.
pub(crate) fn is_partial_credit_mode(mode: &str) -> bool {
    matches!(mode, "tbs" | "doc_review")
}

/// T1 — canonicalize an authoritative-literature citation for comparison. Drops
/// an optional corpus prefix (`FASB ASC` / `ASC` / `IRC` / `AU-C` / `AS` /
/// `§`), unifies every separator (space / hyphen / en- or em-dash / dot /
/// slash) to a single `-`, and makes each numeric component
/// leading-zero-insensitive while preserving any trailing subsection letter
/// (`45A` stays `45A`, `05` -> `5`). So `FASB ASC 842-20-25-1`, `asc 842 20 25
/// 1`, and `842-20-25-01` all normalize to `842-20-25-1`.
pub(crate) fn citation_normalize(s: &str) -> String {
    let upper = s.trim().to_uppercase();
    // Everything before the first digit is a corpus prefix (ASC / FASB ASC /
    // IRC / AU-C / …) — drop it. A citation always contains digits; if it does
    // not, fall back to a whitespace-collapsed upper form.
    let Some(start) = upper.find(|c: char| c.is_ascii_digit()) else {
        return upper.split_whitespace().collect::<Vec<_>>().join(" ");
    };
    upper[start..]
        .split(|c: char| c.is_whitespace() || is_citation_separator(c))
        .filter(|p| !p.is_empty())
        .map(normalize_citation_component)
        .collect::<Vec<_>>()
        .join("-")
}

/// T1 — do two citations refer to the same paragraph/section after
/// normalization? The "accept the exact paragraph OR its parent section"
/// behaviour is authored into the multi-valued accepted-citation list (the
/// answer key lists both), so this stays a strict normalized equality.
pub(crate) fn citation_matches(accepted: &str, submitted: &str) -> bool {
    let sub = citation_normalize(submitted);
    !sub.is_empty() && citation_normalize(accepted) == sub
}

/// Separator characters unified to `-` inside a citation (hyphen family, dot,
/// slash). Whitespace is handled separately by the caller.
fn is_citation_separator(c: char) -> bool {
    matches!(
        c,
        '-' | '\u{2010}' // hyphen
            | '\u{2011}' // non-breaking hyphen
            | '\u{2012}' // figure dash
            | '\u{2013}' // en dash
            | '\u{2014}' // em dash
            | '\u{2212}' // minus sign
            | '.'
            | '/'
            | '_'
    )
}

/// Strip leading zeros from a component's numeric prefix while keeping any
/// trailing subsection letters (`007A` -> `7A`, `05` -> `5`, `0` -> `0`).
fn normalize_citation_component(part: &str) -> String {
    let digits_end = part
        .find(|c: char| !c.is_ascii_digit())
        .unwrap_or(part.len());
    let (num, rest) = part.split_at(digits_end);
    if num.is_empty() {
        return part.to_string();
    }
    let trimmed = num.trim_start_matches('0');
    let num = if trimmed.is_empty() { "0" } else { trimmed };
    format!("{num}{rest}")
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
    fn too_easy_defund_fires_only_when_all_signals_align() {
        let base = 4000.0;
        // Fast (< 0.5x), correct, confident, stable, rote -> defund.
        assert!(too_easy_defund(30, 1000, base, Some("Confident"), 3, true));
        assert!(too_easy_defund(30, 1000, base, Some("Confident"), 4, true));
        // A2 AC2 — not rote -> never.
        assert!(!too_easy_defund(
            30,
            1000,
            base,
            Some("Confident"),
            3,
            false
        ));
        // A2 AC3 — below the stable floor (new/learning) -> never.
        assert!(!too_easy_defund(20, 1000, base, Some("Confident"), 3, true));
        // Slow (>= 0.5x baseline) -> never.
        assert!(!too_easy_defund(30, 3000, base, Some("Confident"), 3, true));
        // Unconfident -> never.
        assert!(!too_easy_defund(30, 1000, base, Some("Unsure"), 3, true));
        assert!(!too_easy_defund(30, 1000, base, None, 3, true));
        // Incorrect (Again/Hard) -> never.
        assert!(!too_easy_defund(30, 1000, base, Some("Confident"), 1, true));
        assert!(!too_easy_defund(30, 1000, base, Some("Confident"), 2, true));
        // No baseline yet -> never (avoids div/zero false-positives).
        assert!(!too_easy_defund(30, 1000, 0.0, Some("Confident"), 3, true));
    }

    #[test]
    fn custom_data_te_roundtrips_and_preserves_other_keys() {
        // A2 AC6 — stays a compact object within the key/size limits.
        let with = custom_data_with_te(r#"{"cf":"Confident"}"#);
        assert!(custom_data_too_easy(&with));
        assert_eq!(custom_data_confidence(&with).as_deref(), Some("Confident"));
        assert!(with.len() <= 100);

        // Clearing keeps the confidence, drops the flag.
        let without = custom_data_without_te(&with);
        assert!(!custom_data_too_easy(&without));
        assert_eq!(
            custom_data_confidence(&without).as_deref(),
            Some("Confident")
        );

        // Setting on empty data yields just the flag; clearing empties it.
        let only = custom_data_with_te("");
        assert_eq!(only, r#"{"te":1}"#);
        assert_eq!(custom_data_without_te(&only), "");
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
    fn cpa_scale_hits_the_documented_anchor_points() {
        // ADR 0005 — 0% -> 0, pass-accuracy -> 75, 100% -> 99.
        assert!(approx(
            cpa_scale_from_accuracy(0.0),
            constants::CPA_MIN_SCORE
        ));
        assert!(approx(
            cpa_scale_from_accuracy(constants::CPA_PASS_ACCURACY),
            constants::CPA_PASS_SCORE
        ));
        assert!(approx(
            cpa_scale_from_accuracy(1.0),
            constants::CPA_MAX_SCORE
        ));
        // Clamped outside [0,1].
        assert!(approx(
            cpa_scale_from_accuracy(-0.5),
            constants::CPA_MIN_SCORE
        ));
        assert!(approx(
            cpa_scale_from_accuracy(1.5),
            constants::CPA_MAX_SCORE
        ));
    }

    #[test]
    fn cpa_scale_is_strictly_monotonic_so_a_band_stays_ordered() {
        // Monotonic transform: mapping a Wilson band's endpoints preserves order
        // (low < high) and keeps the point estimate inside the band.
        let samples = [0.0, 0.2, 0.4, 0.5, 0.6, 0.75, 0.8, 0.9, 1.0];
        for w in samples.windows(2) {
            assert!(
                cpa_scale_from_accuracy(w[0]) < cpa_scale_from_accuracy(w[1]),
                "not monotonic between {} and {}",
                w[0],
                w[1]
            );
        }
        let (lo, hi) = wilson_band(30.0, 50.0); // 0..100
        let cpa_lo = cpa_scale_from_accuracy(lo / 100.0);
        let cpa_hi = cpa_scale_from_accuracy(hi / 100.0);
        let cpa_point = cpa_scale_from_accuracy(30.0 / 50.0);
        assert!(cpa_lo < cpa_point && cpa_point < cpa_hi);
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

    #[test]
    fn is_partial_credit_mode_only_for_tbs_and_doc_review() {
        // A4 — fractional partial-credit modes vs the pass/fail bucket.
        assert!(is_partial_credit_mode("tbs"));
        assert!(is_partial_credit_mode("doc_review"));
        // research is binary (correctness-only), confusion/mcq are pass/fail.
        assert!(!is_partial_credit_mode("research"));
        assert!(!is_partial_credit_mode("confusion"));
        assert!(!is_partial_credit_mode("mcq"));
    }

    #[test]
    fn citation_normalize_strips_prefix_and_unifies_separators() {
        // T1 AC1 — prefix (ASC / FASB ASC), separator, and leading-zero variance
        // all collapse to one canonical form.
        let canonical = "842-20-25-1";
        for spelling in [
            "ASC 842-20-25-1",
            "FASB ASC 842-20-25-1",
            "asc 842 20 25 1",
            "842-20-25-01",
            "842.20.25.1",
            "  842 – 20 — 25 - 1  ",
            "FASB ASC 842-20-25-1.",
        ] {
            assert_eq!(
                citation_normalize(spelling),
                canonical,
                "normalize({spelling:?}) should be {canonical}"
            );
        }
    }

    #[test]
    fn citation_normalize_preserves_trailing_subsection_letter() {
        // "1, 2, or 3 digits followed in some cases by an upper case letter."
        assert_eq!(citation_normalize("ASC 225-20-45-2A"), "225-20-45-2A");
        assert_eq!(citation_normalize("asc 830-10-45-7"), "830-10-45-7");
    }

    #[test]
    fn citation_matches_is_normalized_equality() {
        // T1 — many spellings of one cite match; a different paragraph does not.
        assert!(citation_matches(
            "ASC 606-10-32-31",
            "fasb asc 606 10 32 31"
        ));
        assert!(citation_matches("606-10-32-31", "ASC 606-10-32-31"));
        assert!(!citation_matches("ASC 606-10-32-31", "ASC 606-10-32-39"));
        // A parent section is a distinct cite (acceptance comes from the key
        // listing it explicitly, exercised in grading::tests).
        assert!(!citation_matches("ASC 606-10-32-31", "ASC 606-10-32"));
        // Blank/garbage never matches.
        assert!(!citation_matches("ASC 606-10-32-31", ""));
        assert!(!citation_matches("ASC 606-10-32-31", "   "));
    }
}
