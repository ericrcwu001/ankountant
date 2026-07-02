# scheduler

Read before editing rslib/src/scheduler/.

The core spaced-repetition engine: builds the study queue, computes each
answer button's next state/interval, and persists the result. This is where
SM-2 and FSRS scheduling both live.

## What lives here

- `mod.rs` — `Collection::scheduler_info`/`timing_today`; day rollover,
  timezone, and the V1/V2 version split.
- `answering/` — `answer_card` / `answer_card_inner` (the main write path) and
  `get_scheduling_states` (read-only button preview). `CardStateUpdater` in
  `answering/mod.rs` gathers deck + config + FSRS inputs and applies the chosen
  state. Per-state apply logic in `answering/{new,learning,review,relearning,preview}.rs`;
  revlog rows in `answering/revlog.rs`.
- `states/` — pure state machine. `CardState` = Normal{New,Learning,Review,
  Relearning} or Filtered{Preview,Rescheduling}. `next_states(&StateContext)`
  computes the four buttons. Review intervals: `states/review.rs`. Fuzz:
  `states/fuzz.rs`. Load balancer: `states/load_balancer.rs`.
- `queue/` — the in-memory study queue. `get_next_card`/`get_queued_cards`/
  `update_queues_after_answering_card` in `queue/mod.rs`; `queue/builder/`
  gathers, sorts, intersperses, and buries when (re)building.
- `fsrs/` — FSRS wiring: `params.rs` (param compute + accessors), `retention.rs`
  (`compute_optimal_retention`), `memory_state.rs` (decay + memory state),
  `rescheduler.rs`, `simulator.rs`.
- `filtered/` — filtered/custom-study deck handling.
- `service/` — thin `SchedulerService` RPC impls dispatching into the above.

## Entry points

- Write: `Collection::answer_card` -> `answer_card_inner` (transaction). It
  rebuilds a `CardStateUpdater`, asserts the client's `current_state` matches
  (else "card was modified"), applies the new state, writes revlog + card, and
  updates queues when `from_queue` is set.
- Read: `get_scheduling_states` + `describe_next_states` produce the buttons.

## Gotchas

- The state machine (`states/`) is intentionally decoupled from `Collection`;
  all inputs arrive via `StateContext`. Don't reach back into the collection
  from there.
- `answer_card_inner` requires the submitted `current_state` to equal the
  recomputed one. `set_elapsed_secs_equal` papers over elapsed-time drift only;
  any other mismatch is a hard error.
- FSRS vs SM-2 is a runtime branch on `BoolKey::Fsrs`. When FSRS is on,
  `fsrs.next_states(...)` (in `card_state_updater`) supplies intervals and the
  SM-2 multipliers are bypassed; review.rs has both paths.
- Many tests bail early via `timing_today()?.near_cutoff()` — timing-sensitive.

## Cross-references

- `proto/anki/scheduler.proto` is the RPC contract for this subsystem
  (`AnswerCard`, `GetQueuedCards`, `GetSchedulingStates`, the FSRS RPCs, etc.).
  Editing it needs a full `just check`; see `proto/CLAUDE.md`.
- Deck config seam: `rslib/src/deckconfig/` (intervals, steps, retention).
  `CardStateUpdater` reads the home deck's preset via `get_deck_config`.
- pylib wrapper: `pylib/anki/scheduler/v3.py` (calls `answer_card`,
  `get_queued_cards`, `describe_next_states`).

## Ankountant work

This is THE core engine for the roadmap's deadline-anchored scheduler + FSRS
rework. The deadline ramp is wired into the live answer path (A1-live + A2).

- Desired-retention is the anchor point. It is read in
  `answering/mod.rs::card_state_updater` via `Deck::effective_desired_retention`
  (`rslib/src/decks/mod.rs`) and flows into `fsrs.next_states(...)`.
- For `Ankountant::Study::<section>::*` decks, `card_state_updater` overrides
  that value with `Collection::ankountant_desired_retention` (the days-to-exam
  ramp in `rslib/src/ankountant/schedule.rs`; open-horizon fallback to the
  preset value when no exam date is set), then subtracts the A2 latency-defund
  reduction when the card's `cd.te` flag is set (`rslib/src/ankountant/defund.rs`).
  `fsrs/memory_state.rs::compute_memory_state` mirrors the same override.
- Normal decks keep the stock per-preset value (`config.inner.desired_retention`,
  proto `deck_config.proto` field 37) with an optional per-deck override; the
  exam date itself lives in `col` config (`ankountant.<section>.exam.date`).
