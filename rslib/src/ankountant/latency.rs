// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! Challenge 7h / section 10 — the "one-command benchmark". Load a large deck
//! and report the median (p50), 95th percentile (p95) and worst case for the
//! latency-critical study actions, checked against the stated speed targets:
//!
//! | action                                      | target (p95) |
//! | ------------------------------------------- | ------------ |
//! | button press acknowledged (`answer_card`)   |  < 50 ms     |
//! | next card appears (`get_queued_cards`)      |  < 100 ms    |
//! | dashboard first load (`get_readiness`)      |  < 1000 ms   |
//! | dashboard refresh (`build_confusion_queue`) |  < 500 ms    |
//!
//! This measures the **shared Rust engine in-process** (no PyO3 / IPC / render),
//! on one machine — the reproducible floor the desktop and iOS clients build on.
//! Numbers are only meaningful from an optimized build, so the emitter runs via
//! `just ankountant-bench` (release) and records the profile in the artifact. It
//! never asserts a wall-clock threshold (those are machine-dependent); it
//! reports pass/fail against the targets and always emits, per the doc's
//! "report the numbers, including the ones that did not work" rule.

use std::time::Duration;
use std::time::Instant;

use anki_proto::scheduler::BuildConfusionQueueRequest;
use anki_proto::scheduler::GetReadinessRequest;
use serde_json::json;
use serde_json::Value;

use super::evidence;
use crate::card::CardQueue;
use crate::card::CardType;
use crate::card::FsrsMemoryState;
use crate::prelude::*;
use crate::scheduler::answering::CardAnswer;
use crate::scheduler::answering::Rating;
use crate::services::SchedulerService;

/// Default filler-card count; override with `ANKOUNTANT_BENCH_CARDS`. The doc's
/// reference size is 50,000 — set the env var for the headline run.
const DEFAULT_CARDS: usize = 10_000;
/// Cap on answered cards so the run stays bounded on very large decks.
const DEFAULT_ANSWER_CAP: usize = 5_000;
/// Repeat count for the (idempotent) dashboard queries.
const DEFAULT_DASH_ITERS: usize = 100;

/// Raw per-action samples, in milliseconds.
struct Samples {
    next_card: Vec<f64>,
    answer_ack: Vec<f64>,
    dashboard_load: Vec<f64>,
    dashboard_refresh: Vec<f64>,
}

struct Stat {
    key: &'static str,
    label: &'static str,
    unit: &'static str,
    n: usize,
    p50: f64,
    p95: f64,
    worst: f64,
    target_p95: f64,
    pass: bool,
}

fn ms(d: Duration) -> f64 {
    d.as_secs_f64() * 1000.0
}

/// Nearest-rank percentile over an already-sorted ascending slice.
fn percentile(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let rank = (p / 100.0 * sorted.len() as f64).ceil() as usize;
    let idx = rank.saturating_sub(1).min(sorted.len() - 1);
    sorted[idx]
}

fn stat(key: &'static str, label: &'static str, samples: &[f64], target_p95: f64) -> Stat {
    let mut s = samples.to_vec();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let p95 = percentile(&s, 95.0);
    Stat {
        key,
        label,
        unit: "ms",
        n: s.len(),
        p50: percentile(&s, 50.0),
        p95,
        worst: s.last().copied().unwrap_or(0.0),
        target_p95,
        pass: !s.is_empty() && p95 <= target_p95,
    }
}

fn to_stats(s: &Samples) -> Vec<Stat> {
    vec![
        stat(
            "answer_ack",
            "Button press acknowledged (answer_card)",
            &s.answer_ack,
            50.0,
        ),
        stat(
            "next_card",
            "Next card appears (get_queued_cards)",
            &s.next_card,
            100.0,
        ),
        stat(
            "dashboard_load",
            "Dashboard first load (get_readiness)",
            &s.dashboard_load,
            1000.0,
        ),
        stat(
            "dashboard_refresh",
            "Dashboard refresh (build_confusion_queue)",
            &s.dashboard_refresh,
            500.0,
        ),
    ]
}

/// Add `n` due FSRS review cards to the Default deck, lifting the daily limits
/// so the whole pile is actually queued.
fn add_bench_cards(col: &mut Collection, n: usize) {
    col.update_default_deck_config(|c| {
        c.new_per_day = 9_999_999;
        c.reviews_per_day = 9_999_999;
    });
    let nids: Vec<NoteId> = (0..n)
        .map(|i| {
            NoteAdder::basic(col)
                .fields(&[&format!("BQ{i}"), &format!("BA{i}")])
                .add(col)
                .id
        })
        .collect();

    let now = TimestampMillis::now().as_secs();
    col.transact(Op::UpdateCard, |col| {
        let today = col.timing_today()?.days_elapsed as i32;
        for nid in &nids {
            let cid = col.storage.all_cards_of_note(*nid)?[0].id;
            let mut card = col.storage.get_card(cid)?.unwrap();
            card.ctype = CardType::Review;
            card.queue = CardQueue::Review;
            card.interval = 30;
            card.reps = 8;
            card.due = today;
            card.last_review_time = Some(now);
            card.memory_state = Some(FsrsMemoryState {
                stability: 30.0,
                difficulty: 5.0,
            });
            col.storage.update_card(&card)?;
        }
        Ok(())
    })
    .unwrap();
    col.clear_study_queues();
}

/// Build a realistic collection: the FAR seed (for the dashboard queries) plus
/// `n_filler` due review cards (for the answer/next-card queue).
fn build_bench_collection(n_filler: usize) -> Collection {
    let mut col = Collection::new();
    col.set_config_bool(BoolKey::Fsrs, true, false).unwrap();
    col.ankountant_load_far_seed(true).unwrap();
    add_bench_cards(&mut col, n_filler);
    col.set_current_deck(DeckId(1)).unwrap();
    col
}

fn collect_samples(col: &mut Collection, answer_cap: usize, dash_iters: usize) -> Samples {
    // Warm the queue so the first sample isn't a one-off build cost.
    let _ = col.get_queued_cards(1, false).unwrap();

    let mut next_card = Vec::new();
    let mut answer_ack = Vec::new();
    for _ in 0..answer_cap {
        let t = Instant::now();
        let queued = col.get_queued_cards(1, false).unwrap();
        next_card.push(ms(t.elapsed()));

        let Some(qc) = queued.cards.into_iter().next() else {
            break;
        };
        let mut ans = CardAnswer {
            card_id: qc.card.id,
            current_state: qc.states.current,
            new_state: qc.states.good,
            rating: Rating::Good,
            answered_at: TimestampMillis::now(),
            milliseconds_taken: 5000,
            custom_data: None,
            from_queue: true,
        };
        let t = Instant::now();
        col.answer_card(&mut ans).unwrap();
        answer_ack.push(ms(t.elapsed()));
    }

    let mut dashboard_load = Vec::new();
    for _ in 0..dash_iters {
        let t = Instant::now();
        let _resp = SchedulerService::get_readiness(
            col,
            GetReadinessRequest {
                section: "FAR".into(),
            },
        )
        .unwrap();
        dashboard_load.push(ms(t.elapsed()));
    }

    let mut dashboard_refresh = Vec::new();
    for _ in 0..dash_iters {
        let t = Instant::now();
        let _resp = SchedulerService::build_confusion_queue(
            col,
            BuildConfusionQueueRequest {
                section: "FAR".into(),
                max_items: 0,
            },
        )
        .unwrap();
        dashboard_refresh.push(ms(t.elapsed()));
    }

    Samples {
        next_card,
        answer_ack,
        dashboard_load,
        dashboard_refresh,
    }
}

fn env_usize(key: &str, default: usize) -> usize {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

#[test]
fn latency_harness_produces_ordered_percentiles() {
    // Tiny, fast sanity check for the measurement harness (runs in test-rust):
    // every action yields samples and p50 <= p95 <= worst. No wall-clock
    // thresholds are asserted — those belong to the release bench.
    let mut col = build_bench_collection(120);
    let samples = collect_samples(&mut col, 40, 3);
    for st in to_stats(&samples) {
        assert!(st.n > 0, "no samples collected for {}", st.key);
        assert!(st.p50 <= st.p95 + 1e-9, "p50 > p95 for {}", st.key);
        assert!(st.p95 <= st.worst + 1e-9, "p95 > worst for {}", st.key);
    }
}

#[test]
#[ignore = "latency bench; run via `just ankountant-bench` (release)"]
fn emit_latency_bench() {
    let cards = env_usize("ANKOUNTANT_BENCH_CARDS", DEFAULT_CARDS);
    let dash_iters = env_usize("ANKOUNTANT_BENCH_DASH_ITERS", DEFAULT_DASH_ITERS);
    let answer_cap = env_usize("ANKOUNTANT_BENCH_ANSWERS", DEFAULT_ANSWER_CAP).min(cards);

    let mut col = build_bench_collection(cards);
    let total_cards: i64 = col
        .storage
        .db
        .query_row("select count() from cards", [], |r| r.get(0))
        .unwrap();

    let samples = collect_samples(&mut col, answer_cap, dash_iters);
    let stats = to_stats(&samples);

    let profile = if cfg!(debug_assertions) {
        "debug (numbers not representative — build with --release)"
    } else {
        "release"
    };
    let all_pass = stats.iter().all(|s| s.pass);

    let actions: Vec<Value> = stats
        .iter()
        .map(|s| {
            json!({
                "key": s.key,
                "action": s.label,
                "unit": s.unit,
                "samples": s.n,
                "p50": s.p50,
                "p95": s.p95,
                "worst": s.worst,
                "target_p95": s.target_p95,
                "pass": s.pass,
            })
        })
        .collect();

    let data = json!({
        "title": "Latency benchmark — study actions vs speed targets (challenge 7h / section 10)",
        "generated_at": TimestampSecs::now().0,
        "reproduce": "just ankountant-bench   (ANKOUNTANT_BENCH_CARDS=50000 for the headline run)",
        "claim": "On a large deck, the shared Rust engine acknowledges an answer, serves the next card, and powers the dashboard within the stated p95 speed targets. Percentiles are reported as p50 / p95 / worst — no single hand-picked number.",
        "profile": profile,
        "all_targets_met": all_pass,
        "deck": {
            "filler_review_cards": cards,
            "total_cards": total_cards,
            "answers_measured": samples.answer_ack.len(),
            "dashboard_iters": dash_iters,
        },
        "methodology": "In-process Rust engine, single machine. Times exclude the PyO3/IPC boundary and UI rendering; they are the engine floor the desktop (Python) and iOS (Swift) clients add to. Percentiles use the nearest-rank method.",
        "actions": actions,
    });

    // Harness sanity only — never gate the artifact on machine-dependent ms.
    for s in &stats {
        assert!(s.n > 0, "no samples collected for {}", s.key);
        assert!(s.p50 <= s.p95 + 1e-9);
        assert!(s.p95 <= s.worst + 1e-9);
    }
    evidence::write_artifact("latency", evidence::LATENCY_TEMPLATE, &data);
}
