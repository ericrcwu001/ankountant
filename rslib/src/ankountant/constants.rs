// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! FR-4 — every Ankountant tuning constant lives in this one module so the
//! behaviour is auditable in a single place. Nothing here reaches into the
//! collection; these are pure knobs consumed by the logic + service layers.

// --- A1: deadline-anchored retention ramp ---
/// Days-to-exam at/above which retention sits at the floor (open-horizon
/// study).
pub(crate) const RAMP_HORIZON_DAYS: i64 = 60;
/// Retention floor, used >= RAMP_HORIZON_DAYS out.
pub(crate) const RAMP_MIN_RETENTION: f64 = 0.80;
/// Retention peak, used on/after exam day.
pub(crate) const RAMP_MAX_RETENTION: f64 = 0.95;

// --- A2: latency-aware too-easy defunding (rote only) ---
/// A rote card is "stable" (eligible for defunding) at/above this interval.
pub(crate) const TOO_EASY_STABLE_FLOOR_DAYS: u32 = 21;
/// Fast answer = under this fraction of the latency baseline.
pub(crate) const TOO_EASY_FAST_FACTOR: f64 = 0.5;
/// Pre-FSRS desired-retention reduction applied on defunding.
pub(crate) const TOO_EASY_RETENTION_REDUCTION: f64 = 0.05;
/// Floor the reduced retention never drops below.
pub(crate) const TOO_EASY_RETENTION_FLOOR: f64 = 0.70;
/// Number of trailing own reps whose median forms the latency baseline.
pub(crate) const LATENCY_TRAILING_WINDOW: usize = 5;
/// Minimum own reps before the trailing baseline is trusted over the cohort.
pub(crate) const MIN_OWN_REPS_FOR_BASELINE: usize = 3;
/// Smoothing factor for the rote latency cohort EMA baseline.
pub(crate) const LATENCY_EMA_ALPHA: f64 = 0.2;

// --- A4: memory / performance ---
/// Trailing window (days) over which recall Memory accuracy is measured.
pub(crate) const MEMORY_WINDOW_DAYS: i64 = 30;
/// Minimum in-window recall reps before Memory is reported (else insufficient).
pub(crate) const MEMORY_MIN_REPS: u32 = 5;
/// FAR weighting of MCQ correctness vs TBS partial-credit in Performance.
pub(crate) const PERFORMANCE_MCQ_WEIGHT: f64 = 0.5;
pub(crate) const PERFORMANCE_TBS_WEIGHT: f64 = 0.5;

// --- A5: abstain thresholds + confidence ---
/// Minimum sealed attempts before a readiness band is emitted.
pub(crate) const ABSTAIN_MIN_ATTEMPTS: u32 = 20;
/// Minimum fraction of defined confusion sets that must have >= 1 attempt.
pub(crate) const ABSTAIN_MIN_COVERAGE: f64 = 0.60;
/// At/above this sealed-attempt count, readiness confidence is "High".
pub(crate) const CONFIDENCE_HIGH_MIN: u32 = 50;

// --- A5: CPA 0-99 readiness-scale transform (ADR 0005) ---
// Readiness is projected onto the CPA scaled-score scale (0-99, 75 = pass) via
// a documented, monotonic piecewise-linear transform anchored on the pass line.
// This is an explicit, auditable heuristic — NOT the (non-public) AICPA scaling
// — so the UI labels it a rough projection. See
// docs_ankountant/adr/0005-cpa-scale-readiness-transform.md.
/// Sealed-bank accuracy that maps to the CPA pass line (scaled 75). The claim
/// is only "~this fraction correct on held-out exam-style items is pass-ready".
pub(crate) const CPA_PASS_ACCURACY: f64 = 0.75;
/// The CPA scaled pass score the pass-accuracy anchor maps to.
pub(crate) const CPA_PASS_SCORE: f64 = 75.0;
/// Bottom of the reported CPA scale (0% accuracy anchor).
pub(crate) const CPA_MIN_SCORE: f64 = 0.0;
/// Top of the reported CPA scale (100% accuracy anchor).
pub(crate) const CPA_MAX_SCORE: f64 = 99.0;

// --- A10: grading tolerance ---
/// Default numeric tolerance when a step's answer key does not carry one.
pub(crate) const DEFAULT_NUMERIC_TOLERANCE: f64 = 0.01;

// --- F016: lived-in demo profile (the `with_history` seed) ---
/// Exam date offset (days from today) the lived-in seed writes, so the Home
/// countdown and the deadline-anchored retention ramp (A1) have a target.
pub(crate) const SEED_EXAM_OFFSET_DAYS: i64 = 45;
/// How far back (days) review activity is spread for the stats heatmap/streak.
pub(crate) const SEED_ACTIVITY_SPREAD_DAYS: i64 = 56;
/// Spread (days) for the in-window recall reps that back the readiness Memory
/// metric. MUST stay < MEMORY_WINDOW_DAYS so every seeded rep still counts.
pub(crate) const SEED_MEMORY_SPREAD_DAYS: i64 = 24;
/// Lived-in card-state mix, as parts of each `SEED_MIX_*` total of study cards:
/// new / learning / young-review / mature-review (4+3+8+5 = 20).
pub(crate) const SEED_MIX_NEW: u32 = 4;
pub(crate) const SEED_MIX_LEARN: u32 = 3;
pub(crate) const SEED_MIX_YOUNG: u32 = 8;
pub(crate) const SEED_MIX_MATURE: u32 = 5;
