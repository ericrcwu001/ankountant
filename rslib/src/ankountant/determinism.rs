// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! #4 — the shared Rust backend is **deterministic** in what it recommends and
//! scores. Given the same collection, the three scores, the readiness band, the
//! confusion-queue order and every card's next "Good" interval are identical on
//! repeated computation. The only randomness in scheduling is the interval
//! *fuzz*, which in production is seeded from `(card_id + reps)` and in the test
//! harness is disabled outright (`get_fuzz_seed_for_id_and_reps` -> `None`), so
//! the recommendation is reproducible either way.
//!
//! The `#[ignore]`d `emit_determinism_evidence` recomputes the snapshot and
//! writes `docs_ankountant/evidence/determinism.{json,html}`; it runs only via
//! `just ankountant-evidence`, never in `just test-rust`.

use anki_proto::scheduler::BuildConfusionQueueRequest;
use anki_proto::scheduler::GetReadinessRequest;
use rand::rngs::StdRng;
use rand::Rng;
use rand::SeedableRng;
use serde_json::json;
use serde_json::Value;

use super::evidence;
use crate::prelude::*;
use crate::scheduler::states::fuzz::with_review_fuzz;
use crate::scheduler::states::CardState;
use crate::scheduler::states::NormalState;
use crate::search::SortMode;
use crate::services::SchedulerService;

fn seeded_with_history() -> Collection {
    let mut col = Collection::new();
    col.ankountant_load_far_seed(true).unwrap();
    col
}

/// A JSON snapshot of everything the backend "recommends" for FAR: the three
/// scores (with their bands), the readiness projection, the confusion-queue
/// order, and each review card's next "Good" interval.
fn recommendation_snapshot(col: &mut Collection) -> Value {
    let readiness = SchedulerService::get_readiness(
        col,
        GetReadinessRequest {
            section: "FAR".into(),
        },
    )
    .unwrap();
    let r = readiness.readiness.clone().unwrap();
    let topics: Vec<Value> = readiness
        .topics
        .iter()
        .map(|t| {
            json!({
                "set_id": t.set_id,
                "memory": t.memory,
                "memory_low": t.memory_low,
                "memory_high": t.memory_high,
                "performance": t.performance,
                "performance_low": t.performance_low,
                "performance_high": t.performance_high,
                "gap": t.gap,
                "memory_insufficient": t.memory_insufficient,
            })
        })
        .collect();

    let queue = SchedulerService::build_confusion_queue(
        col,
        BuildConfusionQueueRequest {
            section: "FAR".into(),
            max_items: 0,
        },
    )
    .unwrap();
    let queue_order: Vec<Value> = queue
        .items
        .iter()
        .map(|it| json!({ "note_id": it.note_id, "set_id": it.set_id }))
        .collect();

    // The scheduler's next-card recommendation: the "Good" interval per
    // non-new, non-suspended study card.
    let cids = col
        .search_cards(
            "deck:Ankountant::Study::FAR::* -is:new -is:suspended",
            SortMode::NoOrder,
        )
        .unwrap();
    let mut intervals: Vec<Value> = Vec::new();
    for cid in cids {
        if let CardState::Normal(NormalState::Review(rv)) =
            col.get_scheduling_states(cid).unwrap().good
        {
            intervals.push(json!({ "card_id": cid.0, "good_days": rv.scheduled_days }));
        }
    }
    intervals.sort_by_key(|v| v["card_id"].as_i64().unwrap());

    json!({
        "readiness": {
            "abstain": r.abstain,
            "reason": r.reason,
            "band_low": r.band_low,
            "band_high": r.band_high,
            "point_estimate": r.point_estimate,
            "coverage": r.coverage,
            "confidence": r.confidence,
            "reasons": r.reasons,
        },
        "topics": topics,
        "confusion_queue": queue_order,
        "intervals": intervals,
    })
}

/// The content-addressed part of a snapshot (drops per-collection card ids so it
/// can be compared across independently seeded collections).
fn content_snapshot(snap: &Value) -> Value {
    let queue_order: Vec<&Value> = snap["confusion_queue"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| &v["set_id"])
        .collect();
    json!({
        "readiness": snap["readiness"],
        "topics": snap["topics"],
        "confusion_queue_order": queue_order,
    })
}

#[test]
fn determinism_recommendations_are_byte_identical_across_runs() {
    let mut col = seeded_with_history();
    let a = recommendation_snapshot(&mut col);
    let b = recommendation_snapshot(&mut col);
    assert_eq!(
        a, b,
        "backend recommendation/scoring was not deterministic across repeated computation"
    );
}

#[test]
fn determinism_independent_collections_agree_on_scores_and_order() {
    // Two independently seeded collections must agree on the content-addressed
    // outputs (scores, readiness band, confusion-queue set-id order) — this is
    // the "someone else can re-run and get the same result" guarantee. Card ids
    // legitimately differ, so they are excluded from the comparison.
    let mut col1 = seeded_with_history();
    let mut col2 = seeded_with_history();
    let c1 = content_snapshot(&recommendation_snapshot(&mut col1));
    let c2 = content_snapshot(&recommendation_snapshot(&mut col2));
    assert_eq!(c1, c2, "independent seeds disagreed on scores/queue order");
}

#[test]
fn determinism_interval_fuzz_is_a_pure_function_of_its_seed() {
    // In production the fuzz RNG is seeded with `(card_id + reps)`
    // (`get_fuzz_seed_for_id_and_reps`); in the test harness fuzzing is disabled
    // entirely. Here we prove the *mechanism* is reproducible, not wall-clock:
    // a given seed yields a fixed fuzz factor, and `with_review_fuzz` is a pure
    // function of `(factor, interval, bounds)`.
    let factor_for = |seed: u64| -> f32 { StdRng::seed_from_u64(seed).random_range(0.0..1.0) };

    // Same (card_id, reps) -> same seed -> same factor, every call.
    let seed = 123u64.wrapping_add(4);
    assert_eq!(factor_for(seed), factor_for(seed));
    // Distinct card states are seeded differently (not a shared constant).
    assert_ne!(factor_for(seed), factor_for(seed.wrapping_add(1)));

    // Interval selection is pure: identical inputs -> identical day, repeatably,
    // and inside the constrained fuzz band.
    let f = factor_for(seed);
    let a = with_review_fuzz(Some(f), 100.0, 1, 36_500);
    let b = with_review_fuzz(Some(f), 100.0, 1, 36_500);
    assert_eq!(a, b);
    assert!(a >= 1);
}

#[test]
#[ignore = "evidence emitter; run via `just ankountant-evidence`"]
fn emit_determinism_evidence() {
    let mut col = seeded_with_history();
    let run1 = recommendation_snapshot(&mut col);
    let run2 = recommendation_snapshot(&mut col);

    let mut col2 = seeded_with_history();
    let independent = content_snapshot(&recommendation_snapshot(&mut col2));

    let identical = run1 == run2;
    let independent_agrees = content_snapshot(&run1) == independent;

    // Fuzz reproducibility demonstration.
    let factor_for = |seed: u64| -> f32 { StdRng::seed_from_u64(seed).random_range(0.0..1.0) };
    let fuzz_rows: Vec<Value> = [(1001u64, 0u32), (1001, 1), (2002, 0), (2002, 5)]
        .iter()
        .map(|(id, reps)| {
            let seed = id.wrapping_add(*reps as u64);
            let f = factor_for(seed);
            json!({
                "card_id": id,
                "reps": reps,
                "seed": seed,
                "fuzz_factor": f,
                "fuzzed_interval_from_100": with_review_fuzz(Some(f), 100.0, 1, 36_500),
            })
        })
        .collect();

    let data = json!({
        "title": "Backend determinism (rubric #4)",
        "generated_at": TimestampSecs::now().0,
        "reproduce": "just ankountant-evidence",
        "claim": "Given a fixed collection, the shared Rust core's scores, readiness band, confusion-queue order, and next-card intervals are identical on repeat runs. The only scheduling randomness (interval fuzz) is a pure function of (card_id + reps).",
        "verdicts": {
            "repeat_run_identical": identical,
            "independent_seed_agrees": independent_agrees,
        },
        "run1": run1,
        "run2": run2,
        "fuzz_reproducibility": fuzz_rows,
    });

    // The artifact must only ever be written from a passing state.
    assert!(identical && independent_agrees);
    evidence::write_artifact("determinism", evidence::DETERMINISM_TEMPLATE, &data);
}
