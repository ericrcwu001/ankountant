// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Integration tests for the Ankountant shared core (Phase A). Each test maps
//! to one or more contract assertions (A03–A40); the pure-logic assertions live
//! next to their functions in `logic.rs` and `grading.rs`.
//!
//! The module is already `#[cfg(test)]`-gated by its declaration in `mod.rs`.

use std::collections::HashSet;

use anki_proto::scheduler::BuildConfusionQueueRequest;
use anki_proto::scheduler::ComputeExamScheduleRequest;
use anki_proto::scheduler::GetReadinessRequest;
use anki_proto::scheduler::SubmitPerformanceAttemptRequest;
use serde_json::json;

use super::config;
use super::seed::SeedSummary;
use crate::card::CardQueue;
use crate::card::CardType;
use crate::card::FsrsMemoryState;
use crate::prelude::*;
use crate::revlog::RevlogEntry;
use crate::revlog::RevlogReviewKind;
use crate::scheduler::answering::CardAnswer;
use crate::scheduler::answering::Rating;
use crate::scheduler::states::CardState;
use crate::scheduler::states::NormalState;
use crate::search::SortMode;
use crate::services::SchedulerService;
use crate::timestamp::TimestampMillis;

fn seeded() -> (Collection, SeedSummary) {
    let mut col = Collection::new();
    // Content only (no injected history) — the A4/A5 tests drive history
    // themselves to exercise the thresholds.
    let summary = col.ankountant_load_far_seed(false).unwrap();
    (col, summary)
}

fn set_exam_date(col: &mut Collection, iso: &str) {
    col.set_config_json(&config::exam_date_key("FAR"), &iso.to_string(), false)
        .unwrap();
}

fn compute_schedule(col: &mut Collection, exam_date: &str) -> f64 {
    SchedulerService::compute_exam_schedule(
        col,
        ComputeExamScheduleRequest {
            section: "FAR".into(),
            exam_date: exam_date.into(),
        },
    )
    .unwrap()
    .desired_retention
}

// --- A1 (A03–A09) ------------------------------------------------------------

#[test]
fn a1_ramp_at_anchor_dates_via_rpc() {
    let mut col = Collection::new();
    let today = chrono::Local::now().date_naive();
    let d90 = (today + chrono::Duration::days(90))
        .format("%Y-%m-%d")
        .to_string();
    let d30 = (today + chrono::Duration::days(30))
        .format("%Y-%m-%d")
        .to_string();
    let d0 = today.format("%Y-%m-%d").to_string();
    let past = (today - chrono::Duration::days(10))
        .format("%Y-%m-%d")
        .to_string();

    assert!((compute_schedule(&mut col, &d90) - 0.80).abs() < 1e-9); // A03
    assert!((compute_schedule(&mut col, &d30) - 0.875).abs() < 1e-9); // A04
    assert!((compute_schedule(&mut col, &d0) - 0.95).abs() < 1e-9); // A05
    assert!((compute_schedule(&mut col, &past) - 0.95).abs() < 1e-9); // A05 clamp
}

#[test]
fn a1_no_exam_date_falls_back_to_configured_retention() {
    // A06 — with no exam date, use the preset's configured desired retention.
    let mut col = Collection::new();
    let configured = col
        .storage
        .get_deck_config(DeckConfigId(1))
        .unwrap()
        .unwrap()
        .inner
        .desired_retention as f64;
    let got = compute_schedule(&mut col, "");
    assert!((got - configured).abs() < 1e-6);
}

#[test]
fn a1_nearer_exam_yields_shorter_interval_for_same_card() {
    // A07 — same stable memory state, dr(30d)=0.875 vs dr(90d)=0.80 ->
    // the higher-retention (nearer) date produces a shorter next interval.
    let mut col = Collection::new();
    let dr_far = 0.80f32;
    let dr_near = 0.875f32;
    let ivl_far = col
        .ankountant_preview_interval_for_memory(50.0, 5.0, dr_far)
        .unwrap();
    let ivl_near = col
        .ankountant_preview_interval_for_memory(50.0, 5.0, dr_near)
        .unwrap();
    assert!(
        ivl_near < ivl_far,
        "nearer exam (dr {dr_near}) should shorten interval: near={ivl_near} far={ivl_far}"
    );
}

#[test]
fn a1_exam_date_from_col_config_changes_ramp() {
    // A09 — exam date read from col config via config-set; changing it moves
    // the ramp output.
    let mut col = Collection::new();
    let today = chrono::Local::now().date_naive();
    set_exam_date(
        &mut col,
        &(today + chrono::Duration::days(90))
            .format("%Y-%m-%d")
            .to_string(),
    );
    let far = compute_schedule(&mut col, "");
    set_exam_date(
        &mut col,
        &(today + chrono::Duration::days(30))
            .format("%Y-%m-%d")
            .to_string(),
    );
    let near = compute_schedule(&mut col, "");
    assert!((far - 0.80).abs() < 1e-9);
    assert!((near - 0.875).abs() < 1e-9);
    assert!(near > far);
}

#[test]
fn a1_compute_exam_schedule_propagates_malformed_search() {
    let mut col = Collection::new();

    let err = col.ankountant_compute_exam_schedule("\"", "").unwrap_err();

    assert!(
        matches!(err, AnkiError::SearchError { .. }),
        "expected malformed section to surface a search error, got {err:?}"
    );
}

#[test]
fn ankountant_rpc_sections_are_normalized_and_validated() {
    let mut col = Collection::new();

    let expected = compute_schedule(&mut col, "");
    let got = SchedulerService::compute_exam_schedule(
        &mut col,
        ComputeExamScheduleRequest {
            section: " far ".into(),
            exam_date: String::new(),
        },
    )
    .unwrap()
    .desired_retention;
    assert!((got - expected).abs() < 1e-6);

    let err = SchedulerService::get_readiness(
        &mut col,
        GetReadinessRequest {
            section: "NOPE".into(),
        },
    )
    .unwrap_err();
    match err {
        AnkiError::InvalidInput { source } => {
            assert_eq!(source.message(), "Unknown CPA section: NOPE");
        }
        other => panic!("unexpected error: {other:?}"),
    }
}

// --- A1-live + A2 latency-defunding ------------------------------------------

/// Enable FSRS and turn the first study card tagged `tag` into a mature review
/// card with `interval` days, a memory state, and an optional recorded
/// pre-reveal confidence (`cd.cf`). Returns its id.
fn setup_study_card(
    col: &mut Collection,
    tag: &str,
    interval: u32,
    confidence: Option<&str>,
) -> CardId {
    col.ankountant_load_far_seed(false).unwrap();
    col.set_config_bool(BoolKey::Fsrs, true, false).unwrap();
    let cid = col
        .search_cards(
            &format!("tag:{tag} deck:Ankountant::Study::FAR::*"),
            SortMode::NoOrder,
        )
        .unwrap()[0];
    let custom_data = match confidence {
        Some(c) => format!(r#"{{"cf":"{c}"}}"#),
        None => String::new(),
    };
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
            stability: 50.0,
            difficulty: 5.0,
        });
        card.custom_data = custom_data.clone();
        col.storage.update_card(&card)?;
        Ok(())
    })
    .unwrap();
    cid
}

/// Add trailing recall reps (Good) with the given latencies (ms) to a card.
fn seed_latency_reps(col: &mut Collection, cid: CardId, latencies: &[u32]) {
    let now = TimestampMillis::now().0;
    col.transact(Op::UpdateCard, |col| {
        for (i, &ms) in latencies.iter().enumerate() {
            col.storage.add_revlog_entry(
                &RevlogEntry {
                    id: crate::revlog::RevlogId(now + i as i64),
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

/// Answer `cid` with `rating`, taking `millis`, reusing the live preview
/// states.
fn answer_with(col: &mut Collection, cid: CardId, rating: Rating, millis: u32) {
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

fn card_is_too_easy(col: &mut Collection, cid: CardId) -> bool {
    let card = col.storage.get_card(cid).unwrap().unwrap();
    super::logic::custom_data_too_easy(&card.custom_data)
}

fn good_scheduled_days(col: &mut Collection, cid: CardId) -> u32 {
    match col.get_scheduling_states(cid).unwrap().good {
        CardState::Normal(NormalState::Review(r)) => r.scheduled_days,
        other => panic!("expected a Review good state, got {other:?}"),
    }
}

#[test]
fn a1_live_previewed_interval_shortens_as_exam_nears() {
    // A1-live — the live button preview for a FAR study card uses the deadline
    // ramp, so a nearer exam (higher retention) yields a shorter next interval.
    let mut col = Collection::new();
    let cid = setup_study_card(&mut col, "cog::rote", 30, None);
    let today = chrono::Local::now().date_naive();

    set_exam_date(
        &mut col,
        &(today + chrono::Duration::days(90))
            .format("%Y-%m-%d")
            .to_string(),
    );
    let ivl_far = good_scheduled_days(&mut col, cid);

    set_exam_date(
        &mut col,
        &(today + chrono::Duration::days(5))
            .format("%Y-%m-%d")
            .to_string(),
    );
    let ivl_near = good_scheduled_days(&mut col, cid);

    assert!(
        ivl_near < ivl_far,
        "nearer exam should shorten the live interval: near={ivl_near} far={ivl_far}"
    );
}

#[test]
fn a2_ac1_defund_flags_and_lengthens_next_interval() {
    // A2 AC1 — a stable rote card answered fast + Good + Confident is flagged
    // too-easy, and the flag lowers desired retention so the next previewed
    // interval is longer than the same card without the flag.
    let mut col = Collection::new();
    let cid = setup_study_card(&mut col, "cog::rote", 30, Some("Confident"));
    // >= 3 trailing reps around 4s -> an 800ms answer is fast (< 0.5x).
    seed_latency_reps(&mut col, cid, &[4000, 4200, 3800, 4100]);

    answer_with(&mut col, cid, Rating::Good, 800);
    assert!(
        card_is_too_easy(&mut col, cid),
        "fast+Good+Confident sets te"
    );

    let ivl_defunded = good_scheduled_days(&mut col, cid);

    // Clear the flag (keeping everything else) and re-preview as the control.
    col.transact(Op::UpdateCard, |col| {
        let mut card = col.storage.get_card(cid)?.unwrap();
        card.custom_data = super::logic::custom_data_without_te(&card.custom_data);
        col.storage.update_card(&card)?;
        Ok(())
    })
    .unwrap();
    let ivl_control = good_scheduled_days(&mut col, cid);

    assert!(
        ivl_defunded > ivl_control,
        "defunded interval should be longer: defunded={ivl_defunded} control={ivl_control}"
    );
}

#[test]
fn a2_ac2_applied_cards_never_defund() {
    // A2 AC2 — a cog::applied card, fast + correct + Confident, is never flagged.
    let mut col = Collection::new();
    let cid = setup_study_card(&mut col, "cog::applied", 30, Some("Confident"));
    seed_latency_reps(&mut col, cid, &[4000, 4200, 3800, 4100]);
    answer_with(&mut col, cid, Rating::Good, 800);
    assert!(!card_is_too_easy(&mut col, cid));
}

#[test]
fn a2_ac3_new_or_learning_rote_never_defunds() {
    // A2 AC3 — a rote card below the 21d stable floor is never flagged.
    let mut col = Collection::new();
    let cid = setup_study_card(&mut col, "cog::rote", 10, Some("Confident"));
    seed_latency_reps(&mut col, cid, &[4000, 4200, 3800, 4100]);
    answer_with(&mut col, cid, Rating::Good, 800);
    assert!(!card_is_too_easy(&mut col, cid));
}

#[test]
fn a2_ac4_cohort_baseline_used_when_few_own_reps() {
    // A2 AC4 — with < 3 own reps, the rote cohort EMA is the baseline and the
    // feature still fires.
    let mut col = Collection::new();
    let cid = setup_study_card(&mut col, "cog::rote", 30, Some("Confident"));
    col.set_config_json(super::config::latency_rote_key(), &4000.0f64, false)
        .unwrap();
    // No own reps seeded -> the baseline falls back to the cohort EMA (4000ms).
    answer_with(&mut col, cid, Rating::Good, 800);
    assert!(card_is_too_easy(&mut col, cid));
}

#[test]
fn a2_ac5_slow_or_incorrect_clears_flag() {
    // A2 AC5 — a flagged card answered slow / Again drops the flag.
    let mut col = Collection::new();
    let cid = setup_study_card(&mut col, "cog::rote", 30, Some("Confident"));
    seed_latency_reps(&mut col, cid, &[4000, 4200, 3800, 4100]);
    answer_with(&mut col, cid, Rating::Good, 800);
    assert!(card_is_too_easy(&mut col, cid));

    answer_with(&mut col, cid, Rating::Again, 9000);
    assert!(!card_is_too_easy(&mut col, cid));
}

#[test]
fn a2_ac6_flag_stays_within_custom_data_limits() {
    // A2 AC6 — the flag keeps custom_data a valid <=100-byte / <=8-byte-key
    // object.
    let mut col = Collection::new();
    let cid = setup_study_card(&mut col, "cog::rote", 30, Some("Confident"));
    seed_latency_reps(&mut col, cid, &[4000, 4200, 3800, 4100]);
    answer_with(&mut col, cid, Rating::Good, 800);
    let card = col.storage.get_card(cid).unwrap().unwrap();
    assert!(card.validate_custom_data().is_ok());
    assert!(card.custom_data.len() <= 100);
    assert!(super::logic::custom_data_too_easy(&card.custom_data));
}

// --- A6 (A20–A23) ------------------------------------------------------------

#[test]
fn a6_query_notes_by_ds_tag() {
    // A20 — a query returns all notes for a ds:: tag.
    let (mut col, _) = seeded();
    let nids = col
        .search_notes_unordered("tag:ds::lease::finance")
        .unwrap();
    assert!(!nids.is_empty(), "expected notes tagged ds::lease::finance");
}

#[test]
fn a6_confusable_map_resolves_each_tag_to_one_set() {
    // A21 — no tag belongs to two sets.
    let (col, _) = seeded();
    let map = col.ankountant_confusable_map("FAR");
    let mut seen: HashSet<&str> = HashSet::new();
    for set in map.values() {
        for tag in &set.tags {
            assert!(seen.insert(tag.as_str()), "tag {tag} in two sets");
            let resolved = Collection::ankountant_set_for_tag(&map, tag);
            assert!(resolved.is_some());
        }
    }
}

#[test]
fn a6_cards_filterable_by_cog_tag() {
    // A22.
    let (mut col, _) = seeded();
    let rote = col
        .search_cards("tag:cog::rote", SortMode::NoOrder)
        .unwrap();
    let applied = col
        .search_cards("tag:cog::applied", SortMode::NoOrder)
        .unwrap();
    assert!(!rote.is_empty());
    assert!(!applied.is_empty());
}

#[test]
fn a6_tags_round_trip_through_save_reopen() {
    // A23.
    let (mut col, tmp) = crate::tests::open_fs_test_collection("ankountant_tags");
    col.ankountant_load_far_seed(false).unwrap();
    let before = col
        .search_notes_unordered("tag:ds::lease::finance")
        .unwrap()
        .len();
    let mut builder = col.as_builder();
    col.close(None).unwrap();
    let mut col = builder.build().unwrap();
    let after = col
        .search_notes_unordered("tag:ds::lease::finance")
        .unwrap()
        .len();
    assert_eq!(before, after);
    assert!(after > 0);
    drop(tmp);
}

// --- A7 (A24–A26) ------------------------------------------------------------

#[test]
fn a7_sealed_cards_never_in_study_queue() {
    // A24 — sealed cards are suspended and excluded from GetQueuedCards.
    let (mut col, _) = seeded();
    let queued = SchedulerService::get_queued_cards(
        &mut col,
        anki_proto::scheduler::GetQueuedCardsRequest {
            fetch_limit: 500,
            intraday_learning_only: false,
        },
    )
    .unwrap();
    for qc in &queued.cards {
        let cid = CardId(qc.card.as_ref().unwrap().id);
        let card = col.storage.get_card(cid).unwrap().unwrap();
        assert_ne!(card.queue, CardQueue::Suspended);
    }
    // And every sealed card is indeed suspended.
    let sealed = col
        .search_cards("deck:Ankountant::Sealed::FAR::*", SortMode::NoOrder)
        .unwrap();
    assert!(!sealed.is_empty());
    for cid in sealed {
        assert_eq!(
            col.storage.get_card(cid).unwrap().unwrap().queue,
            CardQueue::Suspended
        );
    }
}

#[test]
fn a7_sealed_and_study_items_are_distinct_notes() {
    // A25.
    let (mut col, _) = seeded();
    let study: HashSet<i64> = col
        .search_notes_unordered("deck:Ankountant::Study::FAR::*")
        .unwrap()
        .into_iter()
        .map(|n| n.0)
        .collect();
    let sealed: HashSet<i64> = col
        .search_notes_unordered("deck:Ankountant::Sealed::FAR::*")
        .unwrap()
        .into_iter()
        .map(|n| n.0)
        .collect();
    assert!(!study.is_empty() && !sealed.is_empty());
    assert!(study.is_disjoint(&sealed));
}

// --- A8 (A27–A30) ------------------------------------------------------------

fn submit(
    col: &mut Collection,
    nid: NoteId,
    mode: &str,
    submission: serde_json::Value,
    confidence: &str,
) -> anki_proto::scheduler::SubmitPerformanceAttemptResponse {
    submit_result(col, nid, mode, submission, confidence).unwrap()
}

fn submit_result(
    col: &mut Collection,
    nid: NoteId,
    mode: &str,
    submission: serde_json::Value,
    confidence: &str,
) -> Result<anki_proto::scheduler::SubmitPerformanceAttemptResponse> {
    submit_result_with_latency(col, nid, mode, submission, confidence, 4200)
}

fn submit_result_with_latency(
    col: &mut Collection,
    nid: NoteId,
    mode: &str,
    submission: serde_json::Value,
    confidence: &str,
    latency_ms: u32,
) -> Result<anki_proto::scheduler::SubmitPerformanceAttemptResponse> {
    SchedulerService::submit_performance_attempt(
        col,
        SubmitPerformanceAttemptRequest {
            item_note_id: nid.0,
            mode: mode.into(),
            submission_json: submission.to_string(),
            confidence: confidence.into(),
            latency_ms,
        },
    )
}

fn invalid_input_message(err: AnkiError) -> String {
    match err {
        AnkiError::InvalidInput { source } => source.message(),
        other => panic!("unexpected error: {other:?}"),
    }
}

fn first_sealed_mcq(col: &mut Collection) -> NoteId {
    // A sealed single-choice ("choice" step) item.
    let nids = col
        .search_notes_unordered("deck:Ankountant::Sealed::FAR::* note:\"Ankountant TBS\"")
        .unwrap();
    for nid in nids {
        let note = col.storage.get_note(nid).unwrap().unwrap();
        if note.fields()[super::notetypes::tbs_fields::STEPS_JSON].contains("\"choice\"") {
            return nid;
        }
    }
    panic!("no sealed mcq found");
}

fn attempt_log_count(col: &mut Collection) -> usize {
    col.ankountant_attempts("FAR").unwrap().len()
}

#[test]
fn a8_confusion_answer_writes_one_attempt_note_with_fields() {
    // A27.
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let before = attempt_log_count(&mut col);
    let resp = submit(
        &mut col,
        nid,
        "confusion",
        json!({"choice": "Capitalize"}),
        "confident",
    );
    assert!(resp.attempt_note_id > 0);
    let attempts = col.ankountant_attempts("FAR").unwrap();
    assert_eq!(attempts.len(), before + 1);
    let last = attempts.iter().max_by_key(|a| a.ts).unwrap();
    assert_eq!(last.confidence, "confident");
    assert_eq!(last.latency_ms, 4200);
    assert!(!last.confusion_set_id.is_empty());
    assert_eq!(last.mode, "confusion");
}

#[test]
fn a8_tbs_attempt_stores_per_step_credit() {
    // A28 — outcome_json holds per-step credit for a TBS attempt.
    let (mut col, _) = seeded();
    let je = je_note(&mut col);
    let resp = submit(
        &mut col,
        je,
        "tbs",
        json!({"steps":[
          {"id":"l1","value":{"account":"ROU Asset","side":"dr","amount":10000}},
          {"id":"l2","value":{"account":"Lease Liability","side":"cr","amount":10000}},
          {"id":"l3","value":{"account":"Interest Expense","side":"dr","amount":500}},
          {"id":"l4","value":{"account":"Cash","side":"cr","amount":999}}
        ]}),
        "unsure",
    );
    assert_eq!(resp.steps.len(), 4);
    let attempts = col.ankountant_attempts("FAR").unwrap();
    let last = attempts.iter().max_by_key(|a| a.ts).unwrap();
    assert_eq!(last.outcome.steps.len(), 4);
    assert!((last.outcome.credit - 0.75).abs() < 1e-9);
}

#[test]
fn a8_malformed_attempt_outcome_fails_fast() {
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let resp = submit(
        &mut col,
        nid,
        "confusion",
        json!({"choice":"Expense"}),
        "guess",
    );

    let mut note = col
        .storage
        .get_note(NoteId(resp.attempt_note_id))
        .unwrap()
        .unwrap();
    note.set_field(super::notetypes::attempt_fields::OUTCOME_JSON, "{not json")
        .unwrap();
    col.update_note(&mut note).unwrap();

    let err = col.ankountant_attempts("FAR").unwrap_err();
    match err {
        AnkiError::InvalidInput { source } => {
            assert_eq!(source.message(), "invalid Attempt Log outcome_json");
        }
        other => panic!("unexpected error: {other:?}"),
    }
}

#[test]
fn a8_malformed_attempt_latency_fails_fast() {
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let resp = submit(
        &mut col,
        nid,
        "confusion",
        json!({"choice":"Expense"}),
        "guess",
    );

    let mut note = col
        .storage
        .get_note(NoteId(resp.attempt_note_id))
        .unwrap()
        .unwrap();
    note.set_field(super::notetypes::attempt_fields::LATENCY_MS, "slow")
        .unwrap();
    col.update_note(&mut note).unwrap();

    let err = col.ankountant_attempts("FAR").unwrap_err();
    assert_eq!(invalid_input_message(err), "invalid Attempt Log latency_ms");
}

#[test]
fn a8_submit_rejects_malformed_payload_before_logging() {
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let before = attempt_log_count(&mut col);

    let err = submit_result(&mut col, nid, "confusion", json!({}), "guess").unwrap_err();
    assert_eq!(
        invalid_input_message(err),
        "confusion submission missing choice"
    );
    assert_eq!(attempt_log_count(&mut col), before);
}

#[test]
fn a8_submit_rejects_incomplete_tbs_step_before_logging() {
    let (mut col, _) = seeded();
    let nid = je_note(&mut col);
    let before = attempt_log_count(&mut col);

    let err = submit_result(
        &mut col,
        nid,
        "tbs",
        json!({"steps":[{"id":"l1"}]}),
        "guess",
    )
    .unwrap_err();
    assert_eq!(
        invalid_input_message(err),
        "performance submission step missing value"
    );
    assert_eq!(attempt_log_count(&mut col), before);
}

#[test]
fn a8_submit_rejects_bad_tbs_weights_before_logging() {
    let (mut col, _) = seeded();
    let nid = je_note(&mut col);
    let mut note = col.storage.get_note(nid).unwrap().unwrap();
    note.set_field(
        super::notetypes::tbs_fields::STEPS_JSON,
        r#"[
            {"id":"l1","answer_key":1,"weight":0.8},
            {"id":"l2","answer_key":2,"weight":0.8}
        ]"#,
    )
    .unwrap();
    col.update_note(&mut note).unwrap();
    let before = attempt_log_count(&mut col);

    let err = submit_result(
        &mut col,
        nid,
        "tbs",
        json!({"steps":[{"id":"l1","value":1},{"id":"l2","value":2}]}),
        "guess",
    )
    .unwrap_err();
    assert_eq!(
        invalid_input_message(err),
        "TBS note step weights must sum to 1.0"
    );
    assert_eq!(attempt_log_count(&mut col), before);
}

#[test]
fn a8_submit_rejects_negative_tbs_weight_before_logging() {
    let (mut col, _) = seeded();
    let nid = je_note(&mut col);
    let mut note = col.storage.get_note(nid).unwrap().unwrap();
    note.set_field(
        super::notetypes::tbs_fields::STEPS_JSON,
        r#"[
            {"id":"l1","answer_key":1,"weight":-0.1},
            {"id":"l2","answer_key":2,"weight":1.1}
        ]"#,
    )
    .unwrap();
    col.update_note(&mut note).unwrap();
    let before = attempt_log_count(&mut col);

    let err = submit_result(
        &mut col,
        nid,
        "tbs",
        json!({"steps":[{"id":"l1","value":1},{"id":"l2","value":2}]}),
        "guess",
    )
    .unwrap_err();
    assert_eq!(
        invalid_input_message(err),
        "TBS note has invalid weight for step l1"
    );
    assert_eq!(attempt_log_count(&mut col), before);
}

#[test]
fn a8_submit_rejects_mode_item_mismatch_before_logging() {
    let (mut col, _) = seeded();
    let nid = je_note(&mut col);
    let before = attempt_log_count(&mut col);

    let err = submit_result(
        &mut col,
        nid,
        "research",
        json!({"citation":"ASC 842-20-25-1"}),
        "guess",
    )
    .unwrap_err();
    assert_eq!(
        invalid_input_message(err),
        "performance mode research does not match item type journal_entry"
    );
    assert_eq!(attempt_log_count(&mut col), before);
}

#[test]
fn a8_submit_rejects_unknown_mode_before_logging() {
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let before = attempt_log_count(&mut col);

    let err = submit_result(
        &mut col,
        nid,
        "essay",
        json!({"choice":"Capitalize"}),
        "guess",
    )
    .unwrap_err();
    assert_eq!(
        invalid_input_message(err),
        "Unknown performance mode: essay"
    );
    assert_eq!(attempt_log_count(&mut col), before);
}

#[test]
fn a8_submit_rejects_unmapped_item_before_logging() {
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let mut note = col.storage.get_note(nid).unwrap().unwrap();
    note.set_field(super::notetypes::tbs_fields::SCHEMA_TAG, "")
        .unwrap();
    note.tags.clear();
    col.update_note(&mut note).unwrap();
    let before = attempt_log_count(&mut col);

    let err = submit_result(
        &mut col,
        nid,
        "confusion",
        json!({"choice":"Capitalize"}),
        "guess",
    )
    .unwrap_err();
    assert_eq!(
        invalid_input_message(err),
        "Performance item missing confusion set"
    );
    assert_eq!(attempt_log_count(&mut col), before);
}

#[test]
fn a8_attempt_notes_never_in_study_queue() {
    // A29.
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let _ = submit(
        &mut col,
        nid,
        "confusion",
        json!({"choice":"Expense"}),
        "guess",
    );
    let queued = SchedulerService::get_queued_cards(
        &mut col,
        anki_proto::scheduler::GetQueuedCardsRequest {
            fetch_limit: 500,
            intraday_learning_only: false,
        },
    )
    .unwrap();
    let log_nt = col
        .get_notetype_by_name(super::notetypes::ATTEMPT_LOG_NOTETYPE)
        .unwrap()
        .unwrap();
    for qc in &queued.cards {
        let cid = CardId(qc.card.as_ref().unwrap().id);
        let card = col.storage.get_card(cid).unwrap().unwrap();
        let note = col.storage.get_note(card.note_id).unwrap().unwrap();
        assert_ne!(note.notetype_id, log_nt.id);
    }
}

#[test]
fn a8_no_schema_change_and_queryable_after_save_reopen() {
    // A30 — PRAGMA table_info identical before/after writing attempts + reopen.
    let (mut col, tmp) = crate::tests::open_fs_test_collection("ankountant_schema");
    col.ankountant_load_far_seed(false).unwrap();

    let schema_before = table_info(&col);

    let nid = first_sealed_mcq(&mut col);
    let _ = submit(
        &mut col,
        nid,
        "confusion",
        json!({"choice":"Capitalize"}),
        "confident",
    );

    let schema_after = table_info(&col);
    assert_eq!(
        schema_before, schema_after,
        "schema changed after writing attempts"
    );

    // Reopen and confirm attempts remain queryable + schema still identical.
    let mut builder = col.as_builder();
    col.close(None).unwrap();
    let mut col = builder.build().unwrap();
    assert_eq!(table_info(&col), schema_before);
    assert!(attempt_log_count(&mut col) >= 1);
    drop(tmp);
}

fn table_info(col: &Collection) -> Vec<String> {
    let mut out = Vec::new();
    for table in ["notes", "cards", "revlog"] {
        let mut stmt = col
            .storage
            .db
            .prepare(&format!("PRAGMA table_info({table})"))
            .unwrap();
        let rows = stmt
            .query_map([], |row| {
                Ok(format!(
                    "{}:{}:{}",
                    row.get::<_, i64>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?
                ))
            })
            .unwrap();
        for r in rows {
            out.push(format!("{table}.{}", r.unwrap()));
        }
    }
    out
}

// --- A9 (A31–A34) ------------------------------------------------------------

#[test]
fn a9_notetype_stores_je_and_numeric_tbs() {
    // A31.
    let (mut col, _) = seeded();
    let je = col
        .search_notes_unordered("note:\"Ankountant TBS\" \"Record the entry*\"")
        .unwrap();
    assert!(!je.is_empty());
    let numeric = col
        .search_notes_unordered("note:\"Ankountant TBS\" \"Compute the amounts*\"")
        .unwrap();
    assert!(!numeric.is_empty());
}

#[test]
fn a9_steps_support_n_weighted_steps_summing_to_one() {
    // A32.
    let (mut col, _) = seeded();
    let je = je_note(&mut col);
    let note = col.storage.get_note(je).unwrap().unwrap();
    let steps =
        super::grading::parse_steps(&note.fields()[super::notetypes::tbs_fields::STEPS_JSON])
            .unwrap();
    assert_eq!(steps.len(), 4);
    let weights = super::grading::effective_weights(&steps);
    let sum: f64 = weights.iter().sum();
    assert!((sum - 1.0).abs() < 1e-9);
    for s in &steps {
        assert!(!s.id.is_empty());
    }
}

#[test]
fn a9_doc_review_and_research_stored_without_schema_change() {
    // A33 — research + doc_review are stored on the shared union note type (no
    // new field/table), now as real content (ADR 0008), not stored-only stubs.
    let (mut col, _) = seeded();
    for shape in ["research", "doc_review"] {
        assert!(
            !tbs_notes_of_type(&mut col, shape).is_empty(),
            "missing {shape} TBS"
        );
    }
}

/// All `Ankountant TBS` note ids whose `tbs_type` (field 0) equals `shape`.
fn tbs_notes_of_type(col: &mut Collection, shape: &str) -> Vec<NoteId> {
    col.search_notes_unordered("note:\"Ankountant TBS\"")
        .unwrap()
        .into_iter()
        .filter(|nid| {
            let note = col.storage.get_note(*nid).unwrap().unwrap();
            note.fields()[super::notetypes::tbs_fields::TBS_TYPE] == shape
        })
        .collect()
}

/// First `Ankountant TBS` note of `shape` tagged `sec::<section>`.
fn section_tbs_note(col: &mut Collection, section: &str, shape: &str) -> NoteId {
    let want = format!("{}{}", super::SEC_TAG_PREFIX, section);
    tbs_notes_of_type(col, shape)
        .into_iter()
        .find(|nid| {
            let note = col.storage.get_note(*nid).unwrap().unwrap();
            note.tags.iter().any(|t| t == &want)
        })
        .unwrap_or_else(|| panic!("no {section} {shape} note"))
}

#[test]
fn a9_provenance_fields_exist_and_default_empty() {
    // A34.
    let (mut col, _) = seeded();
    let nt = col.ankountant_tbs_notetype().unwrap();
    let names: Vec<&str> = nt.fields.iter().map(|f| f.name.as_str()).collect();
    for prov in ["source_passage", "gen_method", "checker_status"] {
        assert!(names.contains(&prov), "missing provenance field {prov}");
    }
    let je = je_note(&mut col);
    let note = col.storage.get_note(je).unwrap().unwrap();
    let fields = note.fields();
    assert_eq!(fields[super::notetypes::tbs_fields::SOURCE_PASSAGE], "");
    assert_eq!(fields[super::notetypes::tbs_fields::GEN_METHOD], "");
    assert_eq!(fields[super::notetypes::tbs_fields::CHECKER_STATUS], "");
}

fn je_note(col: &mut Collection) -> NoteId {
    col.search_notes_unordered("note:\"Ankountant TBS\" \"Record the entry*\"")
        .unwrap()[0]
}

#[test]
fn study_notetype_carries_provenance_fields_blank_for_seed() {
    // Phase-2a — the recall (Study) note type exposes the same three provenance
    // fields as TBS, so RAG-generated recall cards can record
    // source_passage / gen_method / checker_status. Hand-authored seed recall
    // cards leave them blank (doc 6); the human-readable Source rides in Back.
    let (mut col, _) = seeded();
    let nt = col.ankountant_study_notetype().unwrap();
    let names: Vec<&str> = nt.fields.iter().map(|f| f.name.as_str()).collect();
    for prov in ["source_passage", "gen_method", "checker_status"] {
        assert!(names.contains(&prov), "missing provenance field {prov}");
    }
    let recall = col
        .search_notes_unordered("deck:Ankountant::Study::FAR::* note:\"Ankountant Study\"")
        .unwrap()[0];
    let note = col.storage.get_note(recall).unwrap().unwrap();
    let fields = note.fields();
    assert_eq!(fields[super::notetypes::study_fields::SOURCE_PASSAGE], "");
    assert_eq!(fields[super::notetypes::study_fields::GEN_METHOD], "");
    assert_eq!(fields[super::notetypes::study_fields::CHECKER_STATUS], "");
}

// --- A10 (A35–A39) -----------------------------------------------------------

#[test]
fn a10_je_partial_credit_matches_worked_example() {
    // A35 / A36.
    let (mut col, _) = seeded();
    let je = je_note(&mut col);
    let resp = submit(
        &mut col,
        je,
        "tbs",
        json!({"steps":[
          {"id":"l1","value":{"account":"ROU Asset","side":"dr","amount":10000}},
          {"id":"l2","value":{"account":"Lease Liability","side":"cr","amount":10000}},
          {"id":"l3","value":{"account":"Interest Expense","side":"dr","amount":500}},
          {"id":"l4","value":{"account":"Cash","side":"cr","amount":1}}
        ]}),
        "confident",
    );
    let flags: Vec<bool> = resp.steps.iter().map(|s| s.correct).collect();
    assert_eq!(flags, vec![true, true, true, false]);
    assert!((resp.total_credit - 0.75).abs() < 1e-9);
}

#[test]
fn a10_numeric_per_cell_tolerance() {
    // A37.
    let (mut col, _) = seeded();
    let numeric = col
        .search_notes_unordered("note:\"Ankountant TBS\" \"Compute the amounts*\"")
        .unwrap()[0];
    let resp = submit(
        &mut col,
        numeric,
        "tbs",
        json!({"steps":[
          {"id":"c1","value":250000.5},
          {"id":"c2","value":99999}
        ]}),
        "unsure",
    );
    assert!(resp.steps[0].correct);
    assert!(!resp.steps[1].correct);
    assert!((resp.total_credit - 0.5).abs() < 1e-9);
}

#[test]
fn a10_every_submit_writes_exactly_one_attempt_note() {
    // A38.
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let before = attempt_log_count(&mut col);
    let _ = submit(
        &mut col,
        nid,
        "confusion",
        json!({"choice":"Capitalize"}),
        "confident",
    );
    let _ = submit(
        &mut col,
        nid,
        "confusion",
        json!({"choice":"Expense"}),
        "guess",
    );
    assert_eq!(attempt_log_count(&mut col), before + 2);
}

// --- A3 (A10–A12) ------------------------------------------------------------

#[test]
fn a3_queue_never_three_consecutive_same_tag() {
    // A10 (contract).
    let (mut col, _) = seeded();
    let resp = SchedulerService::build_confusion_queue(
        &mut col,
        BuildConfusionQueueRequest {
            section: "FAR".into(),
            max_items: 0,
        },
    )
    .unwrap();
    assert!(!resp.items.is_empty());
    // Recover each item's tag via its note.
    let tags: Vec<String> = resp
        .items
        .iter()
        .map(|it| {
            let note = col.storage.get_note(NoteId(it.note_id)).unwrap().unwrap();
            note.fields()[super::notetypes::tbs_fields::SCHEMA_TAG].clone()
        })
        .collect();
    // Only assert within runs of the same set_id (interleaving is per-set).
    let set_ids: Vec<&str> = resp.items.iter().map(|it| it.set_id.as_str()).collect();
    for w in tags.windows(3).zip(set_ids.windows(3)) {
        let (t, s) = w;
        if s[0] == s[1] && s[1] == s[2] && t[0] == t[1] && t[1] == t[2] {
            panic!("3-in-a-row same tag within a set: {t:?}");
        }
    }
}

#[test]
fn a3_weaker_set_ranks_before_stronger_set() {
    // A11 — seed a 40%-accuracy set and an 80%-accuracy set via Attempt Log.
    let (mut col, _) = seeded();
    // Weak set: capitalize_vs_expense (40% -> 2/5 correct).
    seed_confusion_accuracy(&mut col, "capitalize_vs_expense", 2, 3);
    // Strong set: operating_vs_finance_lease (80% -> 4/1).
    seed_confusion_accuracy(&mut col, "operating_vs_finance_lease", 4, 1);

    let resp = SchedulerService::build_confusion_queue(
        &mut col,
        BuildConfusionQueueRequest {
            section: "FAR".into(),
            max_items: 0,
        },
    )
    .unwrap();
    let weak_positions: Vec<usize> = resp
        .items
        .iter()
        .enumerate()
        .filter(|(_, it)| it.set_id == "capitalize_vs_expense")
        .map(|(i, _)| i)
        .collect();
    let strong_positions: Vec<usize> = resp
        .items
        .iter()
        .enumerate()
        .filter(|(_, it)| it.set_id == "operating_vs_finance_lease")
        .map(|(i, _)| i)
        .collect();
    assert!(!weak_positions.is_empty() && !strong_positions.is_empty());
    let last_weak = *weak_positions.iter().max().unwrap();
    let first_strong = *strong_positions.iter().min().unwrap();
    assert!(
        last_weak < first_strong,
        "all weak-set items must precede strong-set items: weak {weak_positions:?} strong {strong_positions:?}"
    );
}

#[test]
fn a3_dto_has_no_label_field() {
    // A12 — the ConfusionItem DTO exposes no populated category/topic/deck
    // label. The proto message only has note_id/prompt/treatments/set_id; the
    // prompt is a task question, not a category label.
    let (mut col, _) = seeded();
    let resp = SchedulerService::build_confusion_queue(
        &mut col,
        BuildConfusionQueueRequest {
            section: "FAR".into(),
            max_items: 5,
        },
    )
    .unwrap();
    for it in &resp.items {
        // prompt must not echo the internal ds:: tag or a topic label.
        assert!(!it.prompt.contains("ds::"));
    }
}

#[test]
fn note_section_validates_explicit_tag() {
    let tags = vec!["ds::x".to_string(), "sec:: reg ".to_string()];
    assert_eq!(super::note_section(&tags).unwrap(), "REG");

    let empty: Vec<String> = Vec::new();
    assert_eq!(super::note_section(&empty).unwrap(), super::DEFAULT_SECTION);

    let bad = vec!["sec::NOPE".to_string()];
    let err = super::note_section(&bad).unwrap_err();
    match err {
        AnkiError::InvalidInput { source } => {
            assert_eq!(source.message(), "Unknown CPA section tag: sec::NOPE");
        }
        other => panic!("unexpected error: {other:?}"),
    }
}

#[test]
fn a3_all_section_queue_spans_sections() {
    let (mut col, _) = seeded();
    let resp = SchedulerService::build_confusion_queue(
        &mut col,
        BuildConfusionQueueRequest {
            section: " all ".into(),
            max_items: 0,
        },
    )
    .unwrap();
    let sections: HashSet<String> = resp
        .items
        .iter()
        .map(|it| {
            let note = col.storage.get_note(NoteId(it.note_id)).unwrap().unwrap();
            super::note_section(&note.tags).unwrap()
        })
        .collect();
    for section in super::SECTIONS {
        assert!(
            sections.contains(section),
            "all-section queue missing {section}: {sections:?}"
        );
    }
}

#[test]
fn a3_seeded_confusion_queue_has_authored_prompts() {
    let (mut col, _) = seeded();
    let resp = SchedulerService::build_confusion_queue(
        &mut col,
        BuildConfusionQueueRequest {
            section: "FAR".into(),
            max_items: 0,
        },
    )
    .unwrap();
    assert!(!resp.items.is_empty());
    for item in resp.items {
        assert!(
            !item.prompt.starts_with("Which treatment applies?"),
            "generic fallback prompt leaked for {}: {}",
            item.set_id,
            item.prompt
        );
    }
}

#[test]
fn a3_queue_rejects_blank_prompts() {
    let (mut col, _) = seeded();
    let nid = first_sealed_mcq(&mut col);
    let mut note = col.storage.get_note(nid).unwrap().unwrap();
    note.set_field(super::notetypes::tbs_fields::PROMPT, " ")
        .unwrap();
    col.update_note(&mut note).unwrap();

    let err = SchedulerService::build_confusion_queue(
        &mut col,
        BuildConfusionQueueRequest {
            section: "FAR".into(),
            max_items: 0,
        },
    )
    .unwrap_err();
    assert_eq!(invalid_input_message(err), "Confusion item missing prompt");
}

/// Seed `correct` correct + `wrong` wrong confusion attempts for a set by
/// writing Attempt Log notes directly.
fn seed_confusion_accuracy(col: &mut Collection, set_id: &str, correct: u32, wrong: u32) {
    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    col.transact(crate::ops::Op::AddNote, |col| {
        for _ in 0..correct {
            col.ankountant_write_attempt(&NewAttempt {
                item_ref: NoteId(1),
                confusion_set_id: set_id.into(),
                mode: "confusion".into(),
                confidence: "confident".into(),
                latency_ms: 1000,
                outcome: Outcome {
                    credit: 1.0,
                    steps: vec![],
                    elapsed_ms: None,
                },
                section: "FAR".into(),
                sealed: true,
            })?;
        }
        for _ in 0..wrong {
            col.ankountant_write_attempt(&NewAttempt {
                item_ref: NoteId(1),
                confusion_set_id: set_id.into(),
                mode: "confusion".into(),
                confidence: "guess".into(),
                latency_ms: 1000,
                outcome: Outcome {
                    credit: 0.0,
                    steps: vec![],
                    elapsed_ms: None,
                },
                section: "FAR".into(),
                sealed: true,
            })?;
        }
        Ok(())
    })
    .unwrap();
}

// --- A4 (A13–A15) + A26 ------------------------------------------------------

/// Seed N sealed confusion attempts spread across sets to satisfy volume +
/// coverage, at a given fraction correct.
fn seed_sealed_attempts(col: &mut Collection, per_set: u32, correct_frac: f64) {
    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    let sets: Vec<String> = col
        .ankountant_confusable_map("FAR")
        .keys()
        .cloned()
        .collect();
    col.transact(crate::ops::Op::AddNote, |col| {
        for set_id in &sets {
            for i in 0..per_set {
                let correct = (i as f64) < (per_set as f64 * correct_frac);
                col.ankountant_write_attempt(&NewAttempt {
                    item_ref: NoteId(1),
                    confusion_set_id: set_id.clone(),
                    mode: "confusion".into(),
                    confidence: "confident".into(),
                    latency_ms: 1000,
                    outcome: Outcome {
                        credit: if correct { 1.0 } else { 0.0 },
                        steps: vec![],
                        elapsed_ms: None,
                    },
                    section: "FAR".into(),
                    sealed: true,
                })?;
            }
        }
        Ok(())
    })
    .unwrap();
}

fn readiness(col: &mut Collection) -> anki_proto::scheduler::GetReadinessResponse {
    SchedulerService::get_readiness(
        col,
        GetReadinessRequest {
            section: "FAR".into(),
        },
    )
    .unwrap()
}

#[test]
fn a4_gap_equals_memory_minus_performance() {
    // A13.
    let (mut col, _) = seeded();
    seed_memory_reps(&mut col, "ds::lease::finance", 8, 6); // 6/8 correct
    seed_sealed_attempts(&mut col, 6, 0.5);
    let resp = readiness(&mut col);
    for t in &resp.topics {
        assert!((t.gap - (t.memory - t.performance)).abs() < 1e-9);
    }
}

#[test]
fn a4_performance_only_from_sealed_no_study_leakage() {
    // A14 / A26 — study-pile attempts (sealed=false) never move performance.
    let (mut col, _) = seeded();
    // Write only NON-sealed attempts on a set: performance must stay 0.
    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    col.transact(crate::ops::Op::AddNote, |col| {
        for _ in 0..10 {
            col.ankountant_write_attempt(&NewAttempt {
                item_ref: NoteId(1),
                confusion_set_id: "capitalize_vs_expense".into(),
                mode: "confusion".into(),
                confidence: "confident".into(),
                latency_ms: 1000,
                outcome: Outcome {
                    credit: 1.0,
                    steps: vec![],
                    elapsed_ms: None,
                },
                section: "FAR".into(),
                sealed: false,
            })?;
        }
        Ok(())
    })
    .unwrap();
    let resp = readiness(&mut col);
    let cap = resp
        .topics
        .iter()
        .find(|t| t.set_id == "capitalize_vs_expense")
        .unwrap();
    assert_eq!(
        cap.performance, 0.0,
        "study-pile attempts leaked into performance"
    );
}

#[test]
fn a4_tbs_partial_credit_moves_performance() {
    // A15 — a fractional TBS credit contributes fractionally, not pass/fail.
    let (mut col, _) = seeded();
    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    col.transact(crate::ops::Op::AddNote, |col| {
        col.ankountant_write_attempt(&NewAttempt {
            item_ref: NoteId(1),
            confusion_set_id: "trading_afs_htm".into(),
            mode: "tbs".into(),
            confidence: "unsure".into(),
            latency_ms: 1000,
            outcome: Outcome {
                credit: 0.5,
                steps: vec![],
                elapsed_ms: None,
            },
            section: "FAR".into(),
            sealed: true,
        })
    })
    .unwrap();
    let resp = readiness(&mut col);
    let topic = resp
        .topics
        .iter()
        .find(|t| t.set_id == "trading_afs_htm")
        .unwrap();
    assert!((topic.performance - 0.5).abs() < 1e-9);
}

#[test]
fn a4_slow_correct_attempt_lowers_performance() {
    let (mut col, _) = seeded();
    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    col.transact(crate::ops::Op::AddNote, |col| {
        col.ankountant_write_attempt(&NewAttempt {
            item_ref: NoteId(1),
            confusion_set_id: "capitalize_vs_expense".into(),
            mode: "confusion".into(),
            confidence: "confident".into(),
            latency_ms: super::constants::PERFORMANCE_CONFUSION_TARGET_MS * 2,
            outcome: Outcome {
                credit: 1.0,
                steps: vec![],
                elapsed_ms: None,
            },
            section: "FAR".into(),
            sealed: true,
        })
    })
    .unwrap();
    let resp = readiness(&mut col);
    let topic = resp
        .topics
        .iter()
        .find(|t| t.set_id == "capitalize_vs_expense")
        .unwrap();
    assert!((topic.performance - 0.5).abs() < 1e-9);
}

#[test]
fn a4_research_counts_as_tbs_performance_without_timing_penalty() {
    let (mut col, _) = seeded();
    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    col.transact(crate::ops::Op::AddNote, |col| {
        for _ in 0..10 {
            col.ankountant_write_attempt(&NewAttempt {
                item_ref: NoteId(1),
                confusion_set_id: "capitalize_vs_expense".into(),
                mode: "confusion".into(),
                confidence: "guess".into(),
                latency_ms: 1000,
                outcome: Outcome {
                    credit: 0.0,
                    steps: vec![],
                    elapsed_ms: None,
                },
                section: "FAR".into(),
                sealed: true,
            })?;
        }
        col.ankountant_write_attempt(&NewAttempt {
            item_ref: NoteId(1),
            confusion_set_id: "capitalize_vs_expense".into(),
            mode: "research".into(),
            confidence: "confident".into(),
            latency_ms: super::constants::PERFORMANCE_CONFUSION_TARGET_MS * 10,
            outcome: Outcome {
                credit: 1.0,
                steps: vec![],
                elapsed_ms: Some(super::constants::PERFORMANCE_CONFUSION_TARGET_MS * 10),
            },
            section: "FAR".into(),
            sealed: true,
        })
    })
    .unwrap();
    let resp = readiness(&mut col);
    let topic = resp
        .topics
        .iter()
        .find(|t| t.set_id == "capitalize_vs_expense")
        .unwrap();
    assert!((topic.performance - 0.5).abs() < 1e-9);
}

// --- A5 (A16–A19) ------------------------------------------------------------

#[test]
fn a5_abstain_on_insufficient_volume() {
    // A16 — < 20 sealed attempts.
    let (mut col, _) = seeded();
    seed_sealed_attempts(&mut col, 1, 0.5); // 13 sets * 1 = 13 attempts (< 20)
    let r = readiness(&mut col).readiness.unwrap();
    assert!(r.abstain);
    assert_eq!(r.reason, "insufficient volume");
}

#[test]
fn a5_abstain_on_insufficient_coverage() {
    // A17 — >= 20 attempts but < 60% coverage.
    let (mut col, _) = seeded();
    // Put all 24 attempts in a single set -> coverage 1/13 ≈ 8%.
    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    col.transact(crate::ops::Op::AddNote, |col| {
        for i in 0..24 {
            col.ankountant_write_attempt(&NewAttempt {
                item_ref: NoteId(1),
                confusion_set_id: "capitalize_vs_expense".into(),
                mode: "confusion".into(),
                confidence: "confident".into(),
                latency_ms: 1000,
                outcome: Outcome {
                    credit: if i % 2 == 0 { 1.0 } else { 0.0 },
                    steps: vec![],
                    elapsed_ms: None,
                },
                section: "FAR".into(),
                sealed: true,
            })?;
        }
        Ok(())
    })
    .unwrap();
    let r = readiness(&mut col).readiness.unwrap();
    assert!(r.abstain);
    assert_eq!(r.reason, "insufficient coverage");
}

#[test]
fn a5_band_with_sufficient_evidence() {
    // A18 — sufficient volume + coverage -> band with low < high + confidence.
    let (mut col, _) = seeded();
    seed_sealed_attempts(&mut col, 8, 0.5); // 32 attempts across 4 sets
    let r = readiness(&mut col).readiness.unwrap();
    assert!(!r.abstain);
    assert!(r.band_low < r.band_high);
    assert!(!r.confidence.is_empty());
}

#[test]
fn a5_band_widens_when_volume_halves() {
    // A19 — verified on the pure Wilson fn (see logic.rs), reconfirm end-to-end.
    let (mut col_hi, _) = seeded();
    seed_sealed_attempts(&mut col_hi, 10, 0.5); // 40 attempts
    let hi = readiness(&mut col_hi).readiness.unwrap();

    let (mut col_lo, _) = seeded();
    seed_sealed_attempts(&mut col_lo, 5, 0.5); // 20 attempts
    let lo = readiness(&mut col_lo).readiness.unwrap();

    assert!(!hi.abstain && !lo.abstain);
    assert!(
        (lo.band_high - lo.band_low) > (hi.band_high - hi.band_low),
        "band should widen as volume halves"
    );
}

#[test]
fn a5_band_reasons_do_not_infer_gap_without_performance() {
    let (mut col, _) = seeded();
    seed_memory_reps(&mut col, "ds::securities::trading", 8, 8);

    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    let covered_sets: Vec<String> = col
        .ankountant_confusable_map("FAR")
        .keys()
        .filter(|set_id| set_id.as_str() != "trading_afs_htm")
        .take(8)
        .cloned()
        .collect();
    assert_eq!(covered_sets.len(), 8);

    col.transact(crate::ops::Op::AddNote, |col| {
        for set_id in &covered_sets {
            for i in 0..3 {
                col.ankountant_write_attempt(&NewAttempt {
                    item_ref: NoteId(1),
                    confusion_set_id: set_id.clone(),
                    mode: "confusion".into(),
                    confidence: "confident".into(),
                    latency_ms: 1000,
                    outcome: Outcome {
                        credit: if i == 0 { 0.0 } else { 1.0 },
                        steps: vec![],
                        elapsed_ms: None,
                    },
                    section: "FAR".into(),
                    sealed: true,
                })?;
            }
        }
        Ok(())
    })
    .unwrap();

    let resp = readiness(&mut col);
    let r = resp.readiness.unwrap();
    assert!(!r.abstain, "expected readiness band, got {}", r.reason);
    let trading = resp
        .topics
        .iter()
        .find(|t| t.set_id == "trading_afs_htm")
        .unwrap();
    assert!(!trading.memory_insufficient);
    assert_eq!(trading.performance_high, 0.0);
    assert!(
        !r.reasons
            .iter()
            .any(|reason| reason.contains("Largest gap: trading afs htm")),
        "gap reason should not cite a topic without performance evidence: {:?}",
        r.reasons
    );
}

#[test]
fn a5_band_reasons_report_timing_drag() {
    let (mut col, _) = seeded();
    use super::attempt_log::NewAttempt;
    use super::attempt_log::Outcome;
    let covered_sets: Vec<String> = col
        .ankountant_confusable_map("FAR")
        .keys()
        .take(8)
        .cloned()
        .collect();
    let slow_set = covered_sets[0].clone();

    col.transact(crate::ops::Op::AddNote, |col| {
        for set_id in &covered_sets {
            for _ in 0..3 {
                col.ankountant_write_attempt(&NewAttempt {
                    item_ref: NoteId(1),
                    confusion_set_id: set_id.clone(),
                    mode: "confusion".into(),
                    confidence: "confident".into(),
                    latency_ms: if set_id == &slow_set {
                        super::constants::PERFORMANCE_CONFUSION_TARGET_MS * 2
                    } else {
                        1000
                    },
                    outcome: Outcome {
                        credit: 1.0,
                        steps: vec![],
                        elapsed_ms: None,
                    },
                    section: "FAR".into(),
                    sealed: true,
                })?;
            }
        }
        Ok(())
    })
    .unwrap();

    let r = readiness(&mut col).readiness.unwrap();
    assert!(!r.abstain, "expected readiness band, got {}", r.reason);
    assert!(
        r.reasons.iter().any(|reason| reason.contains(&format!(
            "Largest timing drag: {} (-50 pts)",
            slow_set.replace('_', " ")
        ))),
        "timing drag reason missing: {:?}",
        r.reasons
    );
}

// --- F016 seed (A40) ---------------------------------------------------------

#[test]
fn f016_seed_crosses_the_thresholds() {
    // A40.
    let (_, summary) = seeded();
    assert!(
        summary.confusion_sets >= 4,
        "sets: {}",
        summary.confusion_sets
    );
    assert!(
        summary.sealed_items >= 24,
        "sealed: {}",
        summary.sealed_items
    );
    assert!(summary.sealed_je_tbs >= 3, "je: {}", summary.sealed_je_tbs);
    assert!(
        summary.sealed_numeric_tbs >= 2,
        "numeric: {}",
        summary.sealed_numeric_tbs
    );
    // The sealed TBS note ids (JE + numeric) are tracked so the e2e fixture can
    // deep-link the B4 surface (?note=<id>).
    assert!(
        summary.sealed_tbs_note_ids.len() >= summary.sealed_je_tbs + summary.sealed_numeric_tbs,
        "tbs ids: {} vs {}+{}",
        summary.sealed_tbs_note_ids.len(),
        summary.sealed_je_tbs,
        summary.sealed_numeric_tbs
    );
}

#[test]
fn f016_load_far_seed_response_maps_summary_to_proto() {
    // The RPC entry point (LoadFarSeed) returns the same counts as the builder
    // and carries the sealed TBS note ids for the e2e fixture. Each returned id
    // resolves to a real Ankountant TBS note.
    let mut col = Collection::new();
    let resp = col.ankountant_load_far_seed_response(false).unwrap();
    assert!(resp.confusion_sets >= 4);
    assert!(resp.sealed_items >= 24);
    assert!(resp.sealed_je_tbs >= 3);
    assert!(resp.sealed_numeric_tbs >= 2);
    assert!(!resp.sealed_tbs_note_ids.is_empty());
    let tbs_ntid = col.ankountant_tbs_notetype().unwrap().id;
    for nid in &resp.sealed_tbs_note_ids {
        let note = col.storage.get_note(NoteId(*nid)).unwrap().unwrap();
        assert_eq!(note.notetype_id, tbs_ntid);
    }
}

#[test]
fn f016_content_seed_has_real_recall_and_mcqs() {
    // The content layer alone (no history) yields ~130 real recall cards and
    // the real sealed MCQ/TBS bank.
    let (mut col, summary) = seeded();
    assert!(
        summary.study_recall_cards >= 120,
        "recall: {}",
        summary.study_recall_cards
    );
    let sealed_tbs = col
        .search_notes_unordered("deck:Ankountant::Sealed::FAR::* note:\"Ankountant TBS\"")
        .unwrap();
    assert!(
        sealed_tbs.len() >= 24,
        "sealed tbs notes: {}",
        sealed_tbs.len()
    );
    // Every FAR topic has real recall cards backing its Memory (e.g. taxes).
    let taxes = col.search_notes_unordered("tag:far::taxes").unwrap();
    assert!(!taxes.is_empty(), "expected far::taxes recall cards");
}

#[test]
fn f016_demo_history_is_strong_on_most_topics_with_a_few_weak_spots() {
    // with_history=true injects a lived-in profile: every FAR topic is reviewed
    // and scored — most strongly (Memory & Performance both > 80) with a handful
    // of genuine weak spots (both < 75). The aggregate therefore emits an honest
    // band. (The per-topic give-up rule itself is covered by the A5 coverage
    // test; here the demo intentionally covers every topic.)
    let mut col = Collection::new();
    col.ankountant_load_far_seed(true).unwrap();
    let resp = readiness(&mut col);
    let r = resp.readiness.clone().unwrap();
    assert!(
        !r.abstain,
        "demo profile should band, abstained: {}",
        r.reason
    );
    assert!(r.band_low < r.band_high);
    assert!(!r.confidence.is_empty());

    // Every topic is covered with a real Memory base and real Performance — no
    // thin/insufficient topic in the lived-in profile.
    for t in &resp.topics {
        assert!(
            !t.memory_insufficient,
            "topic {} should have a memory base",
            t.set_id
        );
        assert!(
            t.performance > 0.0,
            "topic {} should have performance",
            t.set_id
        );
    }

    // Most topics are strong on BOTH signals...
    let strong = resp
        .topics
        .iter()
        .filter(|t| t.memory > 0.80 && t.performance > 0.80)
        .count();
    assert!(
        strong >= 8,
        "expected most topics strong (mem & perf > 80), got {strong}"
    );

    // ...and 2-3 are weak on BOTH signals (the intended FAR pain points).
    let weak = resp
        .topics
        .iter()
        .filter(|t| t.memory < 0.75 && t.performance < 0.75)
        .count();
    assert!(
        (2..=3).contains(&weak),
        "expected 2-3 weak topics (mem & perf < 75), got {weak}"
    );

    let tax_timing = resp
        .topics
        .iter()
        .find(|t| t.set_id == "tax_timing")
        .unwrap();
    assert!(
        tax_timing.gap >= 0.25,
        "expected tax_timing to show a dashboard warning gap, got {:.3}",
        tax_timing.gap
    );
}

#[test]
fn f016_lived_in_history_reshapes_cards_and_spreads_activity() {
    // with_history=true should leave a *used*-looking collection, not a flat New
    // pile: FSRS on, an exam date set, a real mix of review/new study cards, and
    // review activity spread across many past days (so the stats heatmap/streak
    // and the deck due badges have something to show).
    let mut col = Collection::new();
    col.ankountant_load_far_seed(true).unwrap();

    // FSRS on (memory states / retrievability are live) + exam date set.
    assert!(col.get_config_bool(BoolKey::Fsrs), "FSRS should be enabled");
    assert!(
        col.ankountant_exam_date("FAR").unwrap().is_some(),
        "exam date should be seeded for the Home countdown"
    );

    // A believable mix: some cards reviewed, but still a fresh New pile left.
    let reviewed = col
        .search_cards("deck:Ankountant::Study::FAR::* -is:new", SortMode::NoOrder)
        .unwrap();
    let new = col
        .search_cards("deck:Ankountant::Study::FAR::* is:new", SortMode::NoOrder)
        .unwrap();
    assert!(!reviewed.is_empty(), "expected some reviewed study cards");
    assert!(!new.is_empty(), "expected a remaining New pile");

    // History spans weeks, not the last few seconds.
    let revlog = col
        .storage
        .get_all_revlog_entries(TimestampSecs(0))
        .unwrap();
    assert!(
        revlog.len() > 50,
        "expected a lived-in revlog, got {}",
        revlog.len()
    );
    let day = |id: i64| id / 86_400_000;
    let min_day = revlog.iter().map(|e| day(e.id.0)).min().unwrap();
    let max_day = revlog.iter().map(|e| day(e.id.0)).max().unwrap();
    assert!(
        max_day - min_day >= 20,
        "expected history spread across weeks, got {} days",
        max_day - min_day
    );
}

#[test]
fn f016_content_only_seed_stays_a_clean_slate() {
    // with_history=false must stay deterministic content-only (the e2e fixture +
    // threshold tests drive their own history): no exam date, FSRS untouched,
    // every study card still New, and no revlog.
    let mut col = Collection::new();
    col.ankountant_load_far_seed(false).unwrap();

    assert!(col.ankountant_exam_date("FAR").unwrap().is_none());
    assert!(!col.get_config_bool(BoolKey::Fsrs));
    let touched = col
        .search_cards("deck:Ankountant::Study::FAR::* -is:new", SortMode::NoOrder)
        .unwrap();
    assert!(touched.is_empty(), "content-only seed must leave cards New");
    let revlog = col
        .storage
        .get_all_revlog_entries(TimestampSecs(0))
        .unwrap();
    assert!(revlog.is_empty(), "content-only seed must add no revlog");
}

#[test]
fn f016_content_only_reseed_clears_demo_exam_date() {
    let mut col = Collection::new();
    col.ankountant_load_far_seed(true).unwrap();
    assert!(col.ankountant_exam_date("FAR").unwrap().is_some());

    col.ankountant_load_far_seed(false).unwrap();
    assert!(col.ankountant_exam_date("FAR").unwrap().is_none());
}

#[test]
fn exam_date_is_sync_safe_note_backed_newest_wins() {
    // The exam date must NOT live in col config (which syncs whole-blob,
    // last-writer-wins, so unrelated activity on another device could clobber
    // it). It is stored as a per-object Settings note; newest write wins. The
    // legacy col-config fallback is covered by the seed tests above, which write
    // the old key and read it back through ankountant_exam_date.
    let mut col = Collection::new();
    assert!(col.ankountant_exam_date("FAR").unwrap().is_none());

    col.ankountant_set_exam_date("FAR", "2026-05-01").unwrap();
    assert_eq!(
        col.ankountant_exam_date("FAR").unwrap().as_deref(),
        Some("2026-05-01")
    );

    // A later set wins (append + read-newest), and nothing lands in col config.
    col.ankountant_set_exam_date("FAR", "2026-06-15").unwrap();
    assert_eq!(
        col.ankountant_exam_date("FAR").unwrap().as_deref(),
        Some("2026-06-15")
    );
    let legacy: Option<String> = col.get_config_optional(config::exam_date_key("FAR").as_str());
    assert!(
        legacy.is_none(),
        "exam date must not be written to col config (clobber-prone)"
    );

    // An empty date clears it.
    col.ankountant_set_exam_date("FAR", "").unwrap();
    assert!(col.ankountant_exam_date("FAR").unwrap().is_none());
}

#[test]
fn f016_reseed_replaces_instead_of_stacking() {
    // The seed is idempotent: pressing "Load FAR demo content" again wipes the
    // prior FAR seed and rebuilds it, so counts stay put instead of doubling.
    let count_study = |col: &mut Collection| {
        col.search_cards("deck:Ankountant::Study::FAR::*", SortMode::NoOrder)
            .unwrap()
            .len()
    };
    let count_tbs = |col: &mut Collection| {
        col.search_notes_unordered("note:\"Ankountant TBS\"")
            .unwrap()
            .len()
    };
    let count_decks = |col: &Collection| {
        col.get_all_deck_names(false)
            .unwrap()
            .into_iter()
            .filter(|(_, name)| name.starts_with("Ankountant"))
            .count()
    };

    let mut col = Collection::new();
    col.ankountant_load_far_seed(true).unwrap();
    let (study1, tbs1, decks1) = (
        count_study(&mut col),
        count_tbs(&mut col),
        count_decks(&col),
    );
    assert!(study1 > 100, "expected the full recall pile, got {study1}");

    // Re-seed twice more — every count must be unchanged (a replace, not append).
    col.ankountant_load_far_seed(true).unwrap();
    col.ankountant_load_far_seed(true).unwrap();
    assert_eq!(
        count_study(&mut col),
        study1,
        "study cards doubled on reseed"
    );
    assert_eq!(
        count_tbs(&mut col),
        tbs1,
        "sealed TBS notes doubled on reseed"
    );
    assert_eq!(
        count_decks(&col),
        decks1,
        "Ankountant decks doubled on reseed"
    );

    // The demo still bands after a reseed (attempt history was rebuilt, not lost).
    let r = readiness(&mut col).readiness.unwrap();
    assert!(
        !r.abstain,
        "reseeded demo should still emit a band: {}",
        r.reason
    );
}

// --- helpers -----------------------------------------------------------------

/// Seed recall revlog entries in the trailing-30d window for the study cards
/// on `tag`: `total` reps, `correct` of them a Good/Easy (button > 1).
fn seed_memory_reps(col: &mut Collection, tag: &str, total: u32, correct: u32) {
    let cids = col
        .search_cards(
            &format!("tag:{tag} deck:Ankountant::Study::FAR::*"),
            SortMode::NoOrder,
        )
        .unwrap();
    let cid = cids[0];
    let now = TimestampMillis::now().0;
    col.transact(crate::ops::Op::UpdateCard, |col| {
        for i in 0..total {
            let button = if i < correct { 3 } else { 1 };
            col.storage.add_revlog_entry(
                &RevlogEntry {
                    id: crate::revlog::RevlogId(now + i as i64),
                    cid,
                    usn: Usn(-1),
                    button_chosen: button,
                    review_kind: RevlogReviewKind::Review,
                    ..Default::default()
                },
                true,
            )?;
        }
        Ok(())
    })
    .unwrap();
}

// --- ADR 0008: section-agnostic TBS (research/doc_review across sections)
// -----

#[test]
fn seed_spans_all_six_sections_with_typed_items() {
    // D8 — at least one seeded TBS item per CPA section, all on the single union
    // note type, discriminated by the sec:: tag.
    let (mut col, summary) = seeded();
    for section in super::SECTIONS {
        let n = col
            .search_notes_unordered(&format!("tag:sec::{section} note:\"Ankountant TBS\""))
            .unwrap();
        assert!(!n.is_empty(), "no seeded TBS item for section {section}");
    }
    assert_eq!(
        summary.sections_seeded.len(),
        6,
        "sections seeded: {:?}",
        summary.sections_seeded
    );
    assert!(
        summary.sealed_research_tbs >= 5,
        "research items: {}",
        summary.sealed_research_tbs
    );
    assert!(
        summary.sealed_doc_review_tbs >= 4,
        "doc_review items: {}",
        summary.sealed_doc_review_tbs
    );
}

#[test]
fn typed_section_item_schema_is_validated_at_seed_time() {
    // D9 — well-formed items validate; each structural/logical defect is rejected
    // (correctness is validated, not "unknown keys ignored").
    let good = r#"[
      {"section":"REG","tbs_type":"research","set_id":"reg_capitalize_vs_deduct",
       "prompt":"cite it","source":"s",
       "steps":[{"kind":"citation","id":"citation","accepted":["IRC \u00a7162"]}]}
    ]"#;
    assert_eq!(super::seed::validate_section_items_json(good).unwrap(), 1);

    let bad_cases = [
        // unknown section
        r#"[{"section":"XXX","tbs_type":"research","set_id":"s","prompt":"p","source":"s","steps":[{"kind":"citation","id":"citation","accepted":["IRC 162"]}]}]"#,
        // research with an empty accepted list
        r#"[{"section":"REG","tbs_type":"research","set_id":"s","prompt":"p","source":"s","steps":[{"kind":"citation","id":"citation","accepted":[]}]}]"#,
        // research step id is not "citation"
        r#"[{"section":"REG","tbs_type":"research","set_id":"s","prompt":"p","source":"s","steps":[{"kind":"citation","id":"c","accepted":["IRC 162"]}]}]"#,
        // doc_review blank answer_key is not one of the option ids
        r#"[{"section":"FAR","tbs_type":"doc_review","set_id":"s","prompt":"p","source":"s","exhibits":[{"title":"d","kind":"document","role":"document","body":"x <blank step=\"b1\">y</blank>"}],"steps":[{"kind":"blank","id":"b1","answer_key":"o9","options":[{"id":"o1","text":"a"},{"id":"o2","text":"b"}]}]}]"#,
        // doc_review exhibit kind is not renderable by clients
        r#"[{"section":"FAR","tbs_type":"doc_review","set_id":"s","prompt":"p","source":"s","exhibits":[{"title":"d","kind":"chart","role":"document","body":"x <blank step=\"b1\">y</blank>"}],"steps":[{"kind":"blank","id":"b1","answer_key":"o1","options":[{"id":"o1","text":"a"},{"id":"o2","text":"b"}]}]}]"#,
        // doc_review option id is empty
        r#"[{"section":"FAR","tbs_type":"doc_review","set_id":"s","prompt":"p","source":"s","exhibits":[{"title":"d","kind":"document","role":"document","body":"x <blank step=\"b1\">y</blank>"}],"steps":[{"kind":"blank","id":"b1","answer_key":"o2","options":[{"id":"","text":"a"},{"id":"o2","text":"b"}]}]}]"#,
        // doc_review option text is empty
        r#"[{"section":"FAR","tbs_type":"doc_review","set_id":"s","prompt":"p","source":"s","exhibits":[{"title":"d","kind":"document","role":"document","body":"x <blank step=\"b1\">y</blank>"}],"steps":[{"kind":"blank","id":"b1","answer_key":"o1","options":[{"id":"o1","text":""},{"id":"o2","text":"b"}]}]}]"#,
        // doc_review option kind is not renderable by clients
        r#"[{"section":"FAR","tbs_type":"doc_review","set_id":"s","prompt":"p","source":"s","exhibits":[{"title":"d","kind":"document","role":"document","body":"x <blank step=\"b1\">y</blank>"}],"steps":[{"kind":"blank","id":"b1","answer_key":"o1","options":[{"id":"o1","kind":"maybe","text":"a"},{"id":"o2","text":"b"}]}]}]"#,
        // doc_review missing a role:document exhibit
        r#"[{"section":"FAR","tbs_type":"doc_review","set_id":"s","prompt":"p","source":"s","steps":[{"kind":"blank","id":"b1","answer_key":"o1","options":[{"id":"o1","text":"a"},{"id":"o2","text":"b"}]}]}]"#,
        // doc_review blank with no marker in the document body
        r#"[{"section":"FAR","tbs_type":"doc_review","set_id":"s","prompt":"p","source":"s","exhibits":[{"title":"d","kind":"document","role":"document","body":"no markers"}],"steps":[{"kind":"blank","id":"b1","answer_key":"o1","options":[{"id":"o1","text":"a"},{"id":"o2","text":"b"}]}]}]"#,
        // serde structural error: citation step missing required `accepted`
        r#"[{"section":"REG","tbs_type":"research","set_id":"s","prompt":"p","source":"s","steps":[{"kind":"citation","id":"citation"}]}]"#,
    ];
    for (i, bad) in bad_cases.iter().enumerate() {
        assert!(
            super::seed::validate_section_items_json(bad).is_err(),
            "bad case {i} should have failed validation"
        );
    }
}

#[test]
fn research_submit_is_all_or_nothing_and_records_time() {
    // T1 end-to-end via the real submit path: the seeded FAR lease research item
    // grades correct on a normalized citation, wrong on a bad one, and writes
    // time-to-cite into outcome_json (never into credit).
    let (mut col, _) = seeded();
    let nid = section_tbs_note(&mut col, "FAR", "research"); // ASC 842-20-25-1

    let ok = submit(
        &mut col,
        nid,
        "research",
        json!({"citation":"fasb asc 842 20 25 1"}),
        "confident",
    );
    assert_eq!(ok.steps.len(), 1);
    assert!(ok.steps[0].correct);
    assert!((ok.total_credit - 1.0).abs() < 1e-9);

    let bad = submit(
        &mut col,
        nid,
        "research",
        json!({"citation":"ASC 999-10-10-1"}),
        "guess",
    );
    assert!(!bad.steps[0].correct);
    assert!(bad.total_credit.abs() < 1e-9);

    let attempts = col.ankountant_attempts("FAR").unwrap();
    let research = attempts.iter().find(|a| a.mode == "research").unwrap();
    assert_eq!(research.outcome.elapsed_ms, Some(4200));
}

#[test]
fn doc_review_partial_credit_feeds_fractional_readiness_per_section() {
    // T3 — a REG doc_review with 4 equally weighted blanks: 3/4 correct -> 0.75
    // credit, landing in the FRACTIONAL Performance bucket (A1) of the REG
    // section, not the pass/fail bucket (which would read 1.0).
    let (mut col, _) = seeded();
    let nid = section_tbs_note(&mut col, "REG", "doc_review");

    let resp = submit(
        &mut col,
        nid,
        "doc_review",
        json!({"steps":[
            {"id":"b1","value":"o1"},
            {"id":"b2","value":"o2"},
            {"id":"b3","value":"o2"},
            {"id":"b4","value":"o2"}
        ]}),
        "unsure",
    );
    assert_eq!(resp.steps.len(), 4);
    assert!((resp.total_credit - 0.75).abs() < 1e-9);

    let r = SchedulerService::get_readiness(
        &mut col,
        GetReadinessRequest {
            section: "REG".into(),
        },
    )
    .unwrap();
    let topic = r
        .topics
        .iter()
        .find(|t| t.set_id == "reg_capitalize_vs_deduct")
        .unwrap();
    assert!(
        (topic.performance - 0.75).abs() < 1e-9,
        "doc_review credit must feed fractional performance, got {}",
        topic.performance
    );
}

#[test]
fn every_research_item_citation_exists_in_its_section_corpus() {
    // T2 AC3 — each seeded research item's accepted citation resolves to a
    // passage in that section's committed literature corpus.
    let (mut col, _) = seeded();
    let mut checked = 0;
    for nid in tbs_notes_of_type(&mut col, "research") {
        let note = col.storage.get_note(nid).unwrap().unwrap();
        let section = super::note_section(&note.tags).unwrap();
        let corpus = super::literature::committed_corpus_for_section(&section);
        let steps =
            super::grading::parse_steps(&note.fields()[super::notetypes::tbs_fields::STEPS_JSON])
                .unwrap();
        let accepted: Vec<String> = match &steps[0].answer_key {
            serde_json::Value::Array(a) => a
                .iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect(),
            serde_json::Value::String(s) => vec![s.clone()],
            _ => vec![],
        };
        assert!(
            !accepted.is_empty(),
            "research item has no accepted citation"
        );
        let hit = accepted.iter().any(|acc| {
            corpus
                .iter()
                .any(|p| super::logic::citation_matches(&p.citation, acc))
        });
        assert!(
            hit,
            "no {section} corpus entry for research accepted={accepted:?}"
        );
        checked += 1;
    }
    assert!(checked >= 5, "expected >=5 research items, got {checked}");
}

#[test]
fn literature_loader_scopes_by_section_and_body() {
    // D10 — one loader, per-section bodies: FAR/BAR cite-only, REG verbatim.
    let (col, _) = seeded();
    let far = col.ankountant_literature("FAR").unwrap();
    assert!(!far.is_empty());
    assert!(far
        .iter()
        .all(|p| !p.verbatim && p.overlay_excerpt.is_none()));

    let reg = col.ankountant_literature("REG").unwrap();
    assert!(reg.iter().any(|p| p.verbatim && p.citation.contains("162")));
}

#[test]
fn research_and_doc_review_attempts_add_no_schema_change() {
    // A5 gate — a PRAGMA table_info round-trip proves the new section-agnostic
    // modes add NO new SQLite table/column and survive save + reopen.
    let (mut col, tmp) = crate::tests::open_fs_test_collection("ankountant_section_schema");
    col.ankountant_load_far_seed(false).unwrap();
    let before = table_info(&col);

    let research = section_tbs_note(&mut col, "AUD", "research");
    let _ = submit(
        &mut col,
        research,
        "research",
        json!({"citation":"AS 1105"}),
        "confident",
    );
    let dr = section_tbs_note(&mut col, "ISC", "doc_review");
    let _ = submit(
        &mut col,
        dr,
        "doc_review",
        json!({"steps":[{"id":"b1","value":"o1"}]}),
        "unsure",
    );

    assert_eq!(
        table_info(&col),
        before,
        "schema changed after section-item attempts"
    );

    let mut builder = col.as_builder();
    col.close(None).unwrap();
    let col = builder.build().unwrap();
    assert_eq!(table_info(&col), before);
    drop(tmp);
}
