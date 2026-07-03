// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! #7d — the paraphrase test: proof the Performance signal measures *applying*
//! a fact to a reworded question, not just recalling the study card.
//!
//! Memory reads trailing-30d recall on the **study pile**; Performance reads the
//! **sealed bank** — the label-stripped "which treatment applies?" items that
//! restate the same idea in new words (the "2 reworded questions" of the
//! rubric). The two signals come from disjoint data, so if Performance merely
//! echoed Memory the numbers would move together. This holds Memory constant
//! across two cohorts and varies only the reworded-item accuracy: Performance
//! follows the sealed items and the memory-minus-performance gap opens up — i.e.
//! Performance is **not** a copy of Memory.
//!
//! `emit_paraphrase_evidence` (`#[ignore]`d) writes
//! `docs_ankountant/evidence/paraphrase.{json,html}` via
//! `just ankountant-evidence`; the same claim is enforced by the ordinary
//! `paraphrase_*` tests in `just test-rust`.

use serde_json::json;
use serde_json::Value;

use super::attempt_log::NewAttempt;
use super::attempt_log::Outcome;
use super::evidence;
use crate::ops::Op;
use crate::prelude::*;
use crate::revlog::RevlogEntry;
use crate::revlog::RevlogId;
use crate::revlog::RevlogReviewKind;
use crate::search::SortMode;
use crate::timestamp::TimestampMillis;

fn seeded() -> Collection {
    let mut col = Collection::new();
    // `false` = no demo history, so the only Memory/Performance data is what the
    // cohort below seeds (a clean baseline, same as the ablation evidence).
    col.ankountant_load_far_seed(false).unwrap();
    col
}

/// Seed `total` trailing-30d recall reps on the first study card carrying `tag`,
/// `correct` of them Good (button > 1) — the **Memory** signal.
fn seed_memory_reps(col: &mut Collection, tag: &str, total: u32, correct: u32) {
    let cids = col
        .search_cards(
            &format!("tag:{tag} deck:Ankountant::Study::FAR::*"),
            SortMode::NoOrder,
        )
        .unwrap();
    let Some(&cid) = cids.first() else { return };
    let now = TimestampMillis::now().0;
    col.transact(Op::UpdateCard, |col| {
        for i in 0..total {
            let button = if i < correct { 3 } else { 1 };
            col.storage.add_revlog_entry(
                &RevlogEntry {
                    id: RevlogId(now + i as i64),
                    cid,
                    usn: Usn(-1),
                    button_chosen: button,
                    review_kind: RevlogReviewKind::Review,
                    ..Default::default()
                },
                false,
            )?;
        }
        Ok(())
    })
    .unwrap();
}

/// Seed `total` SEALED confusion attempts for `set_id`, `correct` of them right
/// — the **Performance** signal from reworded ("paraphrase") items.
fn seed_sealed_attempts(col: &mut Collection, set_id: &str, total: u32, correct: u32) {
    col.transact(Op::AddNote, |col| {
        for i in 0..total {
            col.ankountant_write_attempt(&NewAttempt {
                item_ref: NoteId(1),
                confusion_set_id: set_id.into(),
                mode: "confusion".into(),
                confidence: "confident".into(),
                latency_ms: 1000,
                outcome: Outcome {
                    credit: if i < correct { 1.0 } else { 0.0 },
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

/// One topic's paired signals, read back through the real readiness path.
struct TopicPair {
    set_id: String,
    memory: f64,
    performance: f64,
    gap: f64,
}

/// A cohort's two mean signals + their gap, over topics that have both a memory
/// base (>= MEMORY_MIN_REPS recall) and reworded-item evidence.
struct Cohort {
    name: String,
    mean_memory: f64,
    mean_performance: f64,
    mean_gap: f64,
    topics: Vec<TopicPair>,
}

/// Seed every confusion set with `mem_correct/mem_total` study recall and
/// `perf_correct/perf_total` reworded-item accuracy, then read Memory vs
/// Performance per topic through the real `ankountant_get_readiness`.
fn measure(
    name: &str,
    mem_correct: u32,
    mem_total: u32,
    perf_correct: u32,
    perf_total: u32,
) -> Cohort {
    let mut col = seeded();
    let sets: Vec<(String, Vec<String>)> = col
        .ankountant_confusable_map("FAR")
        .iter()
        .map(|(k, v)| (k.clone(), v.tags.clone()))
        .collect();
    for (set_id, tags) in &sets {
        if let Some(tag) = tags.first() {
            seed_memory_reps(&mut col, tag, mem_total, mem_correct);
        }
        seed_sealed_attempts(&mut col, set_id, perf_total, perf_correct);
    }

    let resp = col.ankountant_get_readiness("FAR").unwrap();
    let topics: Vec<TopicPair> = resp
        .topics
        .iter()
        // Only topics with a Memory base — those are the ones we can honestly
        // compare recall against reworded-item accuracy on. Every set is seeded
        // with sealed attempts, so Performance always has evidence.
        .filter(|t| !t.memory_insufficient)
        .map(|t| TopicPair {
            set_id: t.set_id.clone(),
            memory: t.memory,
            performance: t.performance,
            gap: t.gap,
        })
        .collect();

    let n = topics.len().max(1) as f64;
    Cohort {
        name: name.to_string(),
        mean_memory: topics.iter().map(|t| t.memory).sum::<f64>() / n,
        mean_performance: topics.iter().map(|t| t.performance).sum::<f64>() / n,
        mean_gap: topics.iter().map(|t| t.gap).sum::<f64>() / n,
        topics,
    }
}

/// Pretty-print a snake_case set id for a human-facing row.
fn pretty(set_id: &str) -> String {
    set_id.replace('_', " ")
}

#[test]
fn paraphrase_performance_is_not_a_copy_of_memory() {
    // Both cohorts share the SAME study recall (Memory); only the reworded-item
    // (sealed) accuracy differs.
    let memorizer = measure("Rote memorizer", 9, 10, 10, 20); // Memory 90%, Performance 50%
    let mastery = measure("Genuine mastery", 9, 10, 17, 20); // Memory 90%, Performance 85%

    assert!(
        !memorizer.topics.is_empty() && !mastery.topics.is_empty(),
        "expected a FAR cohort with a memory base"
    );

    // Memory is held constant across the two cohorts...
    assert!(
        (memorizer.mean_memory - mastery.mean_memory).abs() < 0.05,
        "memory should be ~equal across cohorts: {} vs {}",
        memorizer.mean_memory,
        mastery.mean_memory
    );
    // ...yet Performance follows the reworded items, not Memory.
    assert!(
        memorizer.mean_performance + 0.2 < mastery.mean_performance,
        "performance must track the sealed items: {} vs {}",
        memorizer.mean_performance,
        mastery.mean_performance
    );
    // The memorizer shows a real Memory-minus-Performance gap; the master doesn't.
    assert!(
        memorizer.mean_gap > 0.2 && memorizer.mean_gap > mastery.mean_gap + 0.15,
        "gap should open for the memorizer only: {} vs {}",
        memorizer.mean_gap,
        mastery.mean_gap
    );
}

#[test]
fn paraphrase_gap_is_per_topic_not_global() {
    // Every memorizer topic recalls the card well but under-performs on the
    // reworded sealed items — the gap is a per-topic property, not an artifact
    // of averaging.
    let memorizer = measure("Rote memorizer", 9, 10, 10, 20);
    for t in &memorizer.topics {
        assert!(
            t.memory > t.performance,
            "topic {} should recall > apply: mem={} perf={}",
            t.set_id,
            t.memory,
            t.performance
        );
    }
}

#[test]
#[ignore = "evidence emitter; run via `just ankountant-evidence`"]
fn emit_paraphrase_evidence() {
    let memorizer = measure("Rote memorizer", 9, 10, 10, 20);
    let mastery = measure("Genuine mastery", 9, 10, 17, 20);

    let cohort_json = |c: &Cohort| -> Value {
        json!({
            "name": c.name,
            "mean_memory": c.mean_memory,
            "mean_performance": c.mean_performance,
            "mean_gap": c.mean_gap,
            "topics": c
                .topics
                .iter()
                .map(|t| json!({
                    "topic": pretty(&t.set_id),
                    "memory": t.memory,
                    "performance": t.performance,
                    "gap": t.gap,
                }))
                .collect::<Vec<_>>(),
        })
    };

    let memory_constant = (memorizer.mean_memory - mastery.mean_memory).abs() < 0.05;
    let performance_tracks = memorizer.mean_performance + 0.2 < mastery.mean_performance;
    let gap_opens = memorizer.mean_gap > 0.2 && memorizer.mean_gap > mastery.mean_gap + 0.15;
    let passed = memory_constant && performance_tracks && gap_opens;

    let data = json!({
        "title": "Paraphrase test — Performance is not a copy of Memory (rubric 7d)",
        "generated_at": TimestampSecs::now().0,
        "reproduce": "just ankountant-evidence",
        "method": "Two cohorts share the SAME study-pile recall (Memory); only the sealed reworded-item accuracy (Performance) differs. Memory reads trailing-30d recall on the study cards; Performance reads the label-stripped sealed 'which treatment applies?' items — the same idea in new words. If Performance merely echoed Memory the two would move together; instead Performance follows the reworded items and the gap opens.",
        "cohorts": [cohort_json(&memorizer), cohort_json(&mastery)],
        "verdict": {
            "memory_held_constant": memory_constant,
            "performance_tracks_reworded_items": performance_tracks,
            "gap_reflects_divergence": gap_opens,
            "passed": passed,
        },
        "note": "A fair test that could fail: had Performance copied Memory, both cohorts would read ~90% Performance and ~0 gap regardless of the reworded-item accuracy. It does not — Performance tracks the sealed items, so the two signals are genuinely distinct.",
    });

    assert!(passed);
    evidence::write_artifact("paraphrase", evidence::PARAPHRASE_TEMPLATE, &data);
}
