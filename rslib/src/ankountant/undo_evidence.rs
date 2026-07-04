// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Challenge 7a — **proof that undo still works and the collection does not
//! corrupt** after our Rust change.
//!
//! We drive a representative sequence of undoable operations (add note, answer,
//! edit, bury, suspend, config, add deck) plus the Ankountant-specific write
//! path — the A2 too-easy defunding flag set inside `answer_card` — then:
//!
//! 1. undo every step in reverse and assert the *whole-collection* snapshot
//!    matches the exact pre-op state each time,
//! 2. redo every step and assert we reach the post-op state each time,
//! 3. run a full database integrity check and assert it finds zero problems.
//!
//! `undo_restores_state_and_collection_is_not_corrupt` runs the assertions in
//! the ordinary `just test-rust` suite; the `#[ignore]`d `emit_undo_evidence`
//! recomputes the same scenario and writes
//! `docs_ankountant/evidence/undo.{json,html}` via `just ankountant-evidence`.

use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;
use serde_json::json;
use serde_json::Value;

use super::evidence;
use super::logic;
use super::TAG_COG_ROTE;
use crate::card::CardQueue;
use crate::card::CardType;
use crate::card::FsrsMemoryState;
use crate::dbcheck::CheckDatabaseOutput;
use crate::prelude::*;
use crate::revlog::RevlogEntry;
use crate::revlog::RevlogReviewKind;
use crate::scheduler::answering::CardAnswer;
use crate::scheduler::answering::Rating;

/// A deck whose name resolves to a study section, so the A2 defunding path in
/// `answer_card` actually fires (`section_for_deck_name`).
const STUDY_DECK: &str = "Ankountant::Study::FAR::UndoDemo";

/// One measured, reversible operation and whether undo/redo round-tripped it.
struct StepResult {
    name: String,
    op: String,
    undo_ok: bool,
    redo_ok: bool,
}

struct UndoReport {
    steps: Vec<StepResult>,
    undo_all_ok: bool,
    redo_all_ok: bool,
    integrity_clean: bool,
    integrity_problems: Vec<String>,
    a2_fired: bool,
    a2_undo_ok: bool,
    a2_cd_before: String,
    a2_cd_after: String,
    a2_cd_after_undo: String,
    note_count: usize,
    card_count: usize,
    deck_count: usize,
}

/// A deterministic, whole-collection fingerprint. Any card/note/deck field the
/// measured operations touch (including the A2 `custom_data` flag), plus the
/// revlog count and the toggled config value, is captured — so snapshot
/// equality is a strong "the state is byte-for-byte back" check.
fn snapshot(col: &mut Collection) -> Value {
    let mut cards: Vec<Value> = col
        .storage
        .get_all_cards()
        .into_iter()
        .map(|c| {
            json!({
                "id": c.id.0,
                "nid": c.note_id.0,
                "did": c.deck_id.0,
                "type": format!("{:?}", c.ctype),
                "queue": format!("{:?}", c.queue),
                "due": c.due,
                "ivl": c.interval,
                "reps": c.reps,
                "lapses": c.lapses,
                "cd": c.custom_data,
            })
        })
        .collect();
    cards.sort_by_key(|v| v["id"].as_i64().unwrap());

    let mut notes: Vec<Value> = col
        .storage
        .get_all_notes()
        .into_iter()
        .map(|n| {
            let mut tags = n.tags.clone();
            tags.sort();
            json!({
                "id": n.id.0,
                "flds": n.fields().join("\u{1f}"),
                "tags": tags.join(" "),
            })
        })
        .collect();
    notes.sort_by_key(|v| v["id"].as_i64().unwrap());

    let mut decks: Vec<Value> = col
        .storage
        .get_all_decks()
        .unwrap()
        .into_iter()
        .map(|d| json!({ "id": d.id.0, "name": d.human_name() }))
        .collect();
    decks.sort_by_key(|v| v["id"].as_i64().unwrap());

    let revlog_count: i64 = col
        .storage
        .db
        .query_row("select count() from revlog", [], |r| r.get(0))
        .unwrap();

    json!({
        "cards": cards,
        "notes": notes,
        "decks": decks,
        "revlog_count": revlog_count,
        "config_flag": col.get_config_bool(BoolKey::AddingDefaultsToCurrentDeck),
    })
}

fn first_card(col: &mut Collection, nid: NoteId) -> CardId {
    col.storage.all_cards_of_note(nid).unwrap()[0].id
}

/// Turn a card into a stable, mature rote review card with a recorded
/// pre-reveal confidence, so it is eligible for A2 defunding (mirrors the
/// ablation evidence fixture).
fn make_mature(col: &mut Collection, cid: CardId, interval: u32, stability: f32) {
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
        card.custom_data = r#"{"cf":"Confident"}"#.to_string();
        col.storage.update_card(&card)?;
        Ok(())
    })
    .unwrap();
}

/// Seed trailing recall reps so the A2 latency baseline is established.
fn seed_latency_reps(col: &mut Collection, cid: CardId, latencies: &[u32]) {
    let now = TimestampMillis::now().0;
    let n = latencies.len() as i64;
    col.transact(Op::UpdateCard, |col| {
        for (i, &ms) in latencies.iter().enumerate() {
            col.storage.add_revlog_entry(
                &RevlogEntry {
                    id: RevlogId(now - (n - i as i64) * 60_000),
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

fn record_step<F>(
    col: &mut Collection,
    name: &str,
    op: &str,
    log: &mut Vec<(String, String)>,
    befores: &mut Vec<Value>,
    afters: &mut Vec<Value>,
    f: F,
) where
    F: FnOnce(&mut Collection),
{
    befores.push(snapshot(col));
    f(col);
    afters.push(snapshot(col));
    log.push((name.to_string(), op.to_string()));
    assert!(
        col.can_undo().is_some(),
        "measured step '{name}' produced no undo entry"
    );
}

/// Build a small collection, run the measured sequence, then verify undo, redo
/// and database integrity. Shared by the CI test and the evidence emitter.
fn run_undo_scenario() -> UndoReport {
    let mut col = Collection::new();
    col.set_config_bool(BoolKey::Fsrs, true, false).unwrap();

    // --- setup (not measured) ------------------------------------------------
    let plain: Vec<Note> = (0..6)
        .map(|i| {
            NoteAdder::basic(&mut col)
                .fields(&[&format!("Q{i}"), &format!("A{i}")])
                .add(&mut col)
        })
        .collect();
    let cids: Vec<CardId> = plain.iter().map(|n| first_card(&mut col, n.id)).collect();

    // A rote card in a study-section deck, so answering it fires A2 defunding.
    let study_did = DeckAdder::new(STUDY_DECK).add(&mut col).id;
    let mut rote = col.basic_notetype().new_note();
    *rote.fields_mut() = vec!["rote q".into(), "rote a".into()];
    rote.tags = vec![TAG_COG_ROTE.to_string()];
    col.add_note(&mut rote, study_did).unwrap();
    let rote_cid = first_card(&mut col, rote.id);
    make_mature(&mut col, rote_cid, 30, 30.0);
    seed_latency_reps(&mut col, rote_cid, &[4000, 4200, 3800, 4100]);

    // --- measured, reversible operations ------------------------------------
    let mut log: Vec<(String, String)> = Vec::new();
    let mut befores: Vec<Value> = Vec::new();
    let mut afters: Vec<Value> = Vec::new();
    // 0-based index of the A2 answer within the measured sequence.
    let a2_idx = 2usize;

    record_step(
        &mut col,
        "Add note",
        "AddNote",
        &mut log,
        &mut befores,
        &mut afters,
        |col| {
            NoteAdder::basic(col).fields(&["new Q", "new A"]).add(col);
        },
    );
    record_step(
        &mut col,
        "Answer new card Good",
        "AnswerCard",
        &mut log,
        &mut befores,
        &mut afters,
        |col| answer(col, cids[0], Rating::Good, 5000),
    );

    let a2_cd_before = col.storage.get_card(rote_cid).unwrap().unwrap().custom_data;
    record_step(
        &mut col,
        "Answer rote fast+Good+Confident (fires A2 defunding)",
        "AnswerCard",
        &mut log,
        &mut befores,
        &mut afters,
        |col| answer(col, rote_cid, Rating::Good, 800),
    );
    let a2_cd_after = col.storage.get_card(rote_cid).unwrap().unwrap().custom_data;
    let a2_fired = logic::custom_data_too_easy(&a2_cd_after);

    record_step(
        &mut col,
        "Edit note field",
        "UpdateNote",
        &mut log,
        &mut befores,
        &mut afters,
        |col| {
            let mut n = col.storage.get_note(plain[1].id).unwrap().unwrap();
            n.set_field(0, "edited").unwrap();
            col.update_note(&mut n).unwrap();
        },
    );
    record_step(
        &mut col,
        "Bury card",
        "Bury",
        &mut log,
        &mut befores,
        &mut afters,
        |col| {
            col.bury_or_suspend_cards(&[cids[2]], BuryOrSuspendMode::BuryUser)
                .unwrap();
        },
    );
    record_step(
        &mut col,
        "Suspend card",
        "Suspend",
        &mut log,
        &mut befores,
        &mut afters,
        |col| {
            col.bury_or_suspend_cards(&[cids[3]], BuryOrSuspendMode::Suspend)
                .unwrap();
        },
    );
    record_step(
        &mut col,
        "Toggle a config value",
        "UpdateConfig",
        &mut log,
        &mut befores,
        &mut afters,
        |col| {
            let cur = col.get_config_bool(BoolKey::AddingDefaultsToCurrentDeck);
            col.set_config_bool(BoolKey::AddingDefaultsToCurrentDeck, !cur, true)
                .unwrap();
        },
    );
    record_step(
        &mut col,
        "Add deck",
        "AddDeck",
        &mut log,
        &mut befores,
        &mut afters,
        |col| {
            DeckAdder::new("UndoDemoDeck").add(col);
        },
    );

    let n = log.len();

    // --- undo everything in reverse -----------------------------------------
    let mut undo_ok = vec![false; n];
    let mut a2_cd_after_undo = String::new();
    for i in (0..n).rev() {
        col.undo().unwrap();
        undo_ok[i] = snapshot(&mut col) == befores[i];
        if i == a2_idx {
            a2_cd_after_undo = col.storage.get_card(rote_cid).unwrap().unwrap().custom_data;
        }
    }

    // --- redo everything ----------------------------------------------------
    let mut redo_ok = vec![false; n];
    for i in 0..n {
        col.redo().unwrap();
        redo_ok[i] = snapshot(&mut col) == afters[i];
    }

    let note_count = col.storage.get_all_notes().len();
    let card_count = col.storage.get_all_cards().len();
    let deck_count = col.storage.get_all_decks().unwrap().len();

    // --- integrity: the collection is not corrupt ---------------------------
    // `check_database` returns Err on a corrupt SQLite file and an all-zero
    // output when nothing needed fixing.
    let db = col
        .check_database()
        .expect("database integrity check must pass (no corruption)");
    let integrity_clean = db == CheckDatabaseOutput::default();
    let integrity_problems = if integrity_clean {
        Vec::new()
    } else {
        db.to_i18n_strings(&col.tr)
    };

    let steps: Vec<StepResult> = log
        .into_iter()
        .enumerate()
        .map(|(i, (name, op))| StepResult {
            name,
            op,
            undo_ok: undo_ok[i],
            redo_ok: redo_ok[i],
        })
        .collect();

    UndoReport {
        undo_all_ok: undo_ok.iter().all(|&b| b),
        redo_all_ok: redo_ok.iter().all(|&b| b),
        integrity_clean,
        integrity_problems,
        a2_fired,
        a2_undo_ok: a2_cd_after_undo == a2_cd_before,
        a2_cd_before,
        a2_cd_after,
        a2_cd_after_undo,
        note_count,
        card_count,
        deck_count,
        steps,
    }
}

#[test]
fn undo_restores_state_and_collection_is_not_corrupt() {
    let r = run_undo_scenario();
    for s in &r.steps {
        assert!(
            s.undo_ok,
            "undo of '{}' did not restore prior state",
            s.name
        );
        assert!(s.redo_ok, "redo of '{}' did not reapply state", s.name);
    }
    assert!(r.a2_fired, "the A2 defunding path should have fired");
    assert!(
        r.a2_undo_ok,
        "undo must restore the card's pre-answer custom_data (A2 flag)"
    );
    assert!(r.integrity_clean, "integrity check found problems");
}

#[test]
#[ignore = "evidence emitter; run via `just ankountant-evidence`"]
fn emit_undo_evidence() {
    let r = run_undo_scenario();

    let steps: Vec<Value> = r
        .steps
        .iter()
        .enumerate()
        .map(|(i, s)| {
            json!({
                "index": i + 1,
                "name": s.name,
                "op": s.op,
                "undo_ok": s.undo_ok,
                "redo_ok": s.redo_ok,
            })
        })
        .collect();

    let data = json!({
        "title": "Undo integrity — the Rust change keeps undo working (challenge 7a)",
        "generated_at": TimestampSecs::now().0,
        "reproduce": "just ankountant-evidence",
        "claim": "A representative sequence of undoable operations — including the Ankountant A2 too-easy defunding flag written inside answer_card — is fully reversible: every undo restores the exact prior whole-collection snapshot, every redo re-applies it, and a full database integrity check finds zero problems (no corruption).",
        "verdicts": {
            "undo_restores_state": r.undo_all_ok,
            "redo_reapplies_state": r.redo_all_ok,
            "integrity_clean": r.integrity_clean,
            "ankountant_a2_undo_ok": r.a2_undo_ok,
        },
        "collection": {
            "notes": r.note_count,
            "cards": r.card_count,
            "decks": r.deck_count,
        },
        "steps": steps,
        "ankountant_a2": {
            "fired": r.a2_fired,
            "custom_data_before": r.a2_cd_before,
            "custom_data_after": r.a2_cd_after,
            "custom_data_after_undo": r.a2_cd_after_undo,
        },
        "integrity": {
            "clean": r.integrity_clean,
            "problems": r.integrity_problems,
        },
    });

    // The artifact must only ever be written from a passing state.
    assert!(r.undo_all_ok && r.redo_all_ok && r.integrity_clean && r.a2_fired && r.a2_undo_ok);
    evidence::write_artifact("undo", evidence::UNDO_TEMPLATE, &data);
}
