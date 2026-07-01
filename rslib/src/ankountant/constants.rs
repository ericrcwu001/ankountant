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

// --- A2 (parked): latency-aware too-easy defunding (rote only) ---
/// A rote card is "stable" (eligible for defunding) at/above this interval.
#[allow(dead_code)]
pub(crate) const TOO_EASY_STABLE_FLOOR_DAYS: u32 = 21;
/// Fast answer = under this fraction of the latency baseline.
#[allow(dead_code)]
pub(crate) const TOO_EASY_FAST_FACTOR: f64 = 0.5;
/// Pre-FSRS desired-retention reduction applied on defunding.
#[allow(dead_code)]
pub(crate) const TOO_EASY_RETENTION_REDUCTION: f64 = 0.05;
/// Floor the reduced retention never drops below.
#[allow(dead_code)]
pub(crate) const TOO_EASY_RETENTION_FLOOR: f64 = 0.70;
/// Number of trailing own reps whose median forms the latency baseline.
#[allow(dead_code)]
pub(crate) const LATENCY_TRAILING_WINDOW: usize = 5;
/// Minimum own reps before the trailing baseline is trusted over the cohort.
#[allow(dead_code)]
pub(crate) const MIN_OWN_REPS_FOR_BASELINE: usize = 3;

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

// --- A10: grading tolerance ---
/// Default numeric tolerance when a step's answer key does not carry one.
pub(crate) const DEFAULT_NUMERIC_TOLERANCE: f64 = 0.01;
