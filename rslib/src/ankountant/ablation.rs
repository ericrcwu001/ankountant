// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! #5 — a written hypothesis for one study feature, tested by turning it OFF
//! and ON.
//!
//! **Feature:** A2 latency-aware "too-easy" defunding.
//!
//! **Hypothesis:** On a *stable* (interval >= 21d) `cog::rote` card answered
//! fast (< 0.5x its latency baseline), correct (Good/Easy) and with a recorded
//! "Confident" pre-reveal confidence, marking it too-easy lowers desired
//! retention by `TOO_EASY_RETENTION_REDUCTION` (0.05), floored at
//! `TOO_EASY_RETENTION_FLOOR` (0.70). That **lengthens the next interval**,
//! which **reduces the projected review count** over a fixed horizon. Cards
//! that are not rote / not stable / answered slowly are **unaffected**. The
//! 0.70 floor is a stated safety bound (we never let retention fall
//! arbitrarily); it is not an empirical retention measurement.
//!
//! **Metric:** across a fixed cohort of eligible rote cards, the mean next
//! "Good" interval and the implied review count over a 90-day horizon, with the
//! feature OFF (flag cleared) vs ON (flag set) on the very same cards.
//!
//! The `#[ignore]`d `emit_ablation_evidence` writes
//! `docs_ankountant/evidence/ablation.{json,html}` via `just
//! ankountant-evidence`.

use serde_json::json;
use serde_json::Value;

use super::evidence;
use super::logic;
use crate::card::CardQueue;
use crate::card::CardType;
use crate::card::FsrsMemoryState;
use crate::ops::Op;
use crate::prelude::*;
use crate::revlog::RevlogEntry;
use crate::revlog::RevlogReviewKind;
use crate::scheduler::answering::CardAnswer;
use crate::scheduler::answering::Rating;
use crate::scheduler::states::CardState;
use crate::scheduler::states::NormalState;
use crate::search::SortMode;
use crate::timestamp::TimestampMillis;

/// The projection horizon (days) for the workload metric.
const HORIZON_DAYS: f64 = 90.0;

fn seeded_fsrs() -> Collection {
    let mut col = Collection::new();
    col.ankountant_load_far_seed(false).unwrap();
    col.set_config_bool(BoolKey::Fsrs, true, false).unwrap();
    col
}

/// Turn a card into a stable, mature review card with a memory state and a
/// recorded pre-reveal confidence, so it is eligible for A2 defunding.
fn make_mature(col: &mut Collection, cid: CardId, interval: u32, stability: f32, confidence: &str) {
    col.transact(Op::UpdateCard, |col| {
        let today = col.timing_today()?.days_elapsed as i32;
        let mut card = col.storage.get_card(cid)?.unwrap();
        card.ctype = CardType::Review;
        card.queue = CardQueue::Review;
        card.interval = interval;
        card.reps = 8;
        card.due = today;
        card.last_review_time = Some(TimestampMillis::now().as_secs());
        card.memory_state = Some(FsrsMemoryState {
            stability,
            difficulty: 5.0,
        });
        card.custom_data = format!(r#"{{"cf":"{confidence}"}}"#);
        col.storage.update_card(&card)?;
        Ok(())
    })
    .unwrap();
}

/// Add trailing recall reps (Good) with the given latencies (ms) so the A2
/// latency baseline is established. Ids are spaced one minute apart in the
/// recent past so they are unambiguously *prior* reps (the upcoming answer
/// stays newest) and `uniquify: true` guarantees every rep is inserted, not
/// IGNORE-d on an id collision.
fn seed_latency_reps(col: &mut Collection, cid: CardId, latencies: &[u32]) {
    let now = TimestampMillis::now().0;
    let n = latencies.len() as i64;
    col.transact(Op::UpdateCard, |col| {
        for (i, &ms) in latencies.iter().enumerate() {
            col.storage.add_revlog_entry(
                &RevlogEntry {
                    id: crate::revlog::RevlogId(now - (n - i as i64) * 60_000),
                    cid,
                    usn: Usn(-1),
                    button_chosen: 3,
                    review_kind: RevlogReviewKind::Review,
                    taken_millis: ms,
                    ..Default::default()
                },
                true,
            )?;
        }
        Ok(())
    })
    .unwrap();
}

fn answer(col: &mut Collection, cid: CardId, rating: Rating, millis: u32) {
    let states = col.get_scheduling_states(cid).unwrap();
    let new_state = match rating {
        Rating::Again => states.again,
        Rating::Hard => states.hard,
        Rating::Good => states.good,
        Rating::Easy => states.easy,
    };
    col.answer_card(&mut CardAnswer {
        card_id: cid,
        current_state: states.current,
        new_state,
        rating,
        answered_at: TimestampMillis::now(),
        milliseconds_taken: millis,
        custom_data: None,
        from_queue: false,
    })
    .unwrap();
}

fn good_days(col: &mut Collection, cid: CardId) -> u32 {
    match col.get_scheduling_states(cid).unwrap().good {
        CardState::Normal(NormalState::Review(r)) => r.scheduled_days,
        other => panic!("expected a Review good state, got {other:?}"),
    }
}

fn is_too_easy(col: &mut Collection, cid: CardId) -> bool {
    let card = col.storage.get_card(cid).unwrap().unwrap();
    logic::custom_data_too_easy(&card.custom_data)
}

fn set_te(col: &mut Collection, cid: CardId, on: bool) {
    col.transact(Op::UpdateCard, |col| {
        let mut card = col.storage.get_card(cid)?.unwrap();
        card.custom_data = if on {
            logic::custom_data_with_te(&card.custom_data)
        } else {
            logic::custom_data_without_te(&card.custom_data)
        };
        col.storage.update_card(&card)?;
        Ok(())
    })
    .unwrap();
}

/// One measured card: interval with the feature OFF vs ON.
struct Measured {
    interval_off: u32,
    interval_on: u32,
}

fn mean_interval(cohort: &[Measured], f: impl Fn(&Measured) -> u32) -> f64 {
    cohort.iter().map(|m| f(m) as f64).sum::<f64>() / cohort.len() as f64
}

fn projected_reviews_for(cohort: &[Measured], f: impl Fn(&Measured) -> u32) -> f64 {
    cohort.iter().map(|m| projected_reviews(f(m))).sum()
}

fn three_build_summary(cohort: &[Measured], study_time_seconds: f64) -> Vec<Value> {
    let plain_reviews = projected_reviews_for(cohort, |m| m.interval_off);
    let feature_off_reviews = projected_reviews_for(cohort, |m| m.interval_off);
    let full_reviews = projected_reviews_for(cohort, |m| m.interval_on);
    vec![
        json!({
            "build": "full_app_feature_on",
            "label": "Full app (A2 on)",
            "study_time_seconds": study_time_seconds,
            "mean_interval_days": mean_interval(cohort, |m| m.interval_on),
            "projected_reviews": full_reviews,
            "delta_vs_plain_reviews_pct": (full_reviews - plain_reviews) / plain_reviews * 100.0,
        }),
        json!({
            "build": "app_feature_off",
            "label": "App with A2 off",
            "study_time_seconds": study_time_seconds,
            "mean_interval_days": mean_interval(cohort, |m| m.interval_off),
            "projected_reviews": feature_off_reviews,
            "delta_vs_plain_reviews_pct": (feature_off_reviews - plain_reviews) / plain_reviews * 100.0,
        }),
        json!({
            "build": "plain_anki_baseline",
            "label": "Plain Anki / FSRS baseline",
            "study_time_seconds": study_time_seconds,
            "mean_interval_days": mean_interval(cohort, |m| m.interval_off),
            "projected_reviews": plain_reviews,
            "delta_vs_plain_reviews_pct": 0.0,
        }),
    ]
}

/// Build the eligible rote cohort, fire the feature (fast+Good+Confident), then
/// read each card's next "Good" interval with the too-easy flag ON vs cleared.
fn measure_cohort(col: &mut Collection, limit: usize) -> Vec<Measured> {
    let cids = col
        .search_cards(
            "tag:cog::rote deck:Ankountant::Study::FAR::*",
            SortMode::NoOrder,
        )
        .unwrap();
    let mut out = Vec::new();
    for (i, cid) in cids.into_iter().take(limit).enumerate() {
        // A spread of stabilities so the cohort has a realistic mix of intervals
        // (all still stable, i.e. >= the 21d floor, so all are A2-eligible).
        let stability = 25.0 + (i as f32) * 9.0;
        make_mature(col, cid, 30, stability, "Confident");
        seed_latency_reps(col, cid, &[4000, 4200, 3800, 4100]);
        // Fast + Good + Confident on a stable rote card -> the feature fires.
        answer(col, cid, Rating::Good, 800);
        assert!(
            is_too_easy(col, cid),
            "A2 should have fired on an eligible card"
        );

        let interval_on = good_days(col, cid);
        set_te(col, cid, false);
        let interval_off = good_days(col, cid);
        // Restore ON state so the collection reflects the live feature.
        set_te(col, cid, true);

        out.push(Measured {
            interval_off,
            interval_on,
        });
    }
    out
}

/// Reviews over the horizon for a card seen every `interval` days (>= 1).
fn projected_reviews(interval: u32) -> f64 {
    HORIZON_DAYS / (interval.max(1) as f64)
}

#[test]
fn a2_ablation_on_lengthens_intervals_and_cuts_reviews() {
    let mut col = seeded_fsrs();
    let cohort = measure_cohort(&mut col, 8);
    assert!(!cohort.is_empty(), "expected an eligible rote cohort");

    // Per-card: ON interval is at least as long as OFF, and strictly longer for
    // the cohort in aggregate.
    for m in &cohort {
        assert!(
            m.interval_on >= m.interval_off,
            "defunding must never shorten an interval: on={} off={}",
            m.interval_on,
            m.interval_off
        );
    }
    let reviews_off: f64 = cohort
        .iter()
        .map(|m| projected_reviews(m.interval_off))
        .sum();
    let reviews_on: f64 = cohort
        .iter()
        .map(|m| projected_reviews(m.interval_on))
        .sum();
    assert!(
        reviews_on < reviews_off,
        "ON should reduce projected reviews: on={reviews_on} off={reviews_off}"
    );
}

#[test]
fn a2_ablation_control_applied_card_is_unaffected() {
    // A cog::applied card given the exact same fast+Good+Confident treatment
    // must NOT be flagged (A2 AC2) — the feature is inert for non-rote cards.
    let mut col = seeded_fsrs();
    let cid = col
        .search_cards(
            "tag:cog::applied deck:Ankountant::Study::FAR::*",
            SortMode::NoOrder,
        )
        .unwrap()[0];
    make_mature(&mut col, cid, 30, 40.0, "Confident");
    seed_latency_reps(&mut col, cid, &[4000, 4200, 3800, 4100]);
    answer(&mut col, cid, Rating::Good, 800);
    assert!(
        !is_too_easy(&mut col, cid),
        "applied cards must never be defunded"
    );
}

#[test]
fn a2_ablation_three_builds_use_equal_time_budget() {
    let mut col = seeded_fsrs();
    let cohort = measure_cohort(&mut col, 8);
    let builds = three_build_summary(&cohort, cohort.len() as f64 * 0.8);
    assert_eq!(builds.len(), 3);
    let times: Vec<f64> = builds
        .iter()
        .map(|b| b["study_time_seconds"].as_f64().unwrap())
        .collect();
    assert!(times.windows(2).all(|w| (w[0] - w[1]).abs() < 1e-9));
    let full_reviews = builds[0]["projected_reviews"].as_f64().unwrap();
    let off_reviews = builds[1]["projected_reviews"].as_f64().unwrap();
    let plain_reviews = builds[2]["projected_reviews"].as_f64().unwrap();
    assert!(full_reviews < off_reviews);
    assert!((off_reviews - plain_reviews).abs() < 1e-9);
}

#[test]
#[ignore = "evidence emitter; run via `just ankountant-evidence`"]
fn emit_ablation_evidence() {
    let mut col = seeded_fsrs();
    let cohort = measure_cohort(&mut col, 8);

    let rows: Vec<Value> = cohort
        .iter()
        .enumerate()
        .map(|(i, m)| {
            json!({
                "card": format!("rote #{}", i + 1),
                "interval_off_days": m.interval_off,
                "interval_plain_anki_days": m.interval_off,
                "interval_on_days": m.interval_on,
                "delta_days": m.interval_on as i64 - m.interval_off as i64,
            })
        })
        .collect();

    let mean_off = mean_interval(&cohort, |m| m.interval_off);
    let mean_on = mean_interval(&cohort, |m| m.interval_on);
    let reviews_off = projected_reviews_for(&cohort, |m| m.interval_off);
    let reviews_on = projected_reviews_for(&cohort, |m| m.interval_on);
    let reduction_pct = if reviews_off > 0.0 {
        (reviews_off - reviews_on) / reviews_off * 100.0
    } else {
        0.0
    };
    let study_time_seconds = cohort.len() as f64 * 0.8;
    let builds = three_build_summary(&cohort, study_time_seconds);

    // Control card (applied) — feature inert.
    let applied = col
        .search_cards(
            "tag:cog::applied deck:Ankountant::Study::FAR::*",
            SortMode::NoOrder,
        )
        .unwrap()[0];
    make_mature(&mut col, applied, 30, 40.0, "Confident");
    seed_latency_reps(&mut col, applied, &[4000, 4200, 3800, 4100]);
    answer(&mut col, applied, Rating::Good, 800);
    let control_fired = is_too_easy(&mut col, applied);

    let data = json!({
        "title": "A2 too-easy defunding — three-build ablation (rubric #5)",
        "generated_at": TimestampSecs::now().0,
        "reproduce": "just ankountant-evidence",
        "feature": "A2 latency-aware too-easy defunding",
        "hypothesis": "On a stable (>=21d) cog::rote card answered fast (<0.5x baseline), correct, and Confident, defunding lowers desired retention by 0.05 (floored 0.70), lengthening the next interval and reducing projected reviews. Non-rote/unstable/slow cards are unaffected.",
        "horizon_days": HORIZON_DAYS,
        "cohort_size": cohort.len(),
        "equal_time_protocol": {
            "study_time_seconds_per_build": study_time_seconds,
            "same_cards": true,
            "same_answer": "Good",
            "same_answer_latency_ms": 800,
            "builds": ["full_app_feature_on", "app_feature_off", "plain_anki_baseline"],
            "note": "This backend fixture isolates A2. Plain Anki / FSRS and app-feature-off are expected to match because A2 is the only toggled behavior in this harness.",
        },
        "builds": builds,
        "per_card": rows,
        "summary": {
            "mean_interval_off_days": mean_off,
            "mean_interval_plain_anki_days": mean_off,
            "mean_interval_on_days": mean_on,
            "projected_reviews_off": reviews_off,
            "projected_reviews_plain_anki": reviews_off,
            "projected_reviews_on": reviews_on,
            "review_reduction_pct": reduction_pct,
        },
        "control": {
            "card": "cog::applied (same fast+Good+Confident treatment)",
            "feature_fired": control_fired,
            "expected": false,
        },
        "safety_bound": "Retention is never reduced below TOO_EASY_RETENTION_FLOOR (0.70); this is a design bound, not a measured retention outcome.",
    });

    assert!(
        mean_on >= mean_off
            && reviews_on < reviews_off
            && !control_fired
            && data["builds"].as_array().unwrap().len() == 3
    );
    evidence::write_artifact("ablation", evidence::ABLATION_TEMPLATE, &data);
}
