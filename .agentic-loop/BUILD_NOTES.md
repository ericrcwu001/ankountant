# agentic-loop BUILD NOTES — critical conventions + PRD-survey corrections

> Read this BEFORE implementing any feature. These rules override any stale path
> in the PRD/companions. Full per-feature ACs, proto message shapes, data model,
> and worked examples live in `docs_ankountant/prd/{rubrics-core.md,
> rubrics-frontend.md,contracts-and-data.md,build-spec.md}` — open the companion
> referenced by each feature's `acceptanceHint` before building it.

## Build order (hard)

Complete ALL of Phase A (F001,F003–F010 + F016 seed; F002 is P1/parkable) and get
`just check` + `just test-rust` green BEFORE starting Phase B desktop (F011–F015).
Phase-B features declare `dependsOn` on their Phase-A features — respect it.
Foundational features with no deps: F006 (tags), F007 (sealed bank), F008 (Attempt
Log), F009 (TBS note type) — start there.

## Proto (the #1 correctness risk)

1. Proto is a CONTRACT across Rust/Python/TS. After ANY `.proto` edit run
   **`just check`** (NOT `cargo check`) so `rslib/src/services.rs`,
   `out/pylib/anki/_backend_generated.py`, and `out/ts/lib/generated/backend.ts`
   regenerate in lockstep. NEVER edit generated code under `out/`.
2. **APPEND-ONLY + CORRECTION.** Append the 4 new RPCs (`ComputeExamSchedule`,
   `BuildConfusionQueue`, `GetReadiness`, `SubmitPerformanceAttempt`) at the END of
   `service SchedulerService` in `proto/anki/scheduler.proto`, and NEVER reorder
   existing methods. **The real tail of `SchedulerService` is `FuzzDelta`
   (`scheduler.proto:66`) — NOT `SimulateFsrsWorkload`.** The PRD /
   `contracts-and-data.md` names `simulateFsrsWorkload` as the tail, which is
   STALE: `EvaluateParams` / `EvaluateParamsLegacy` / `ComputeMemoryState` /
   `FuzzDelta` follow it. Appending after `SimulateFsrsWorkload` would REORDER
   those and silently break Python/TS dispatch AND the hand-maintained iOS indices.
   **Append AFTER `FuzzDelta`.** Note `scheduler.proto` also defines
   `BackendSchedulerService` (dual-service pattern, see `proto/CLAUDE.md`).
3. Exam date is SET via the existing config-set RPC in `config.proto` — there is
   NO new/5th setter RPC.

## Impl location (CORRECTION)

SchedulerService method impls live in **`rslib/src/scheduler/service/mod.rs`**
(per-area service dir). `contracts-and-data.md`'s `rslib/src/backend/scheduler.rs`
does NOT exist — read `rslib/src/scheduler/service/mod.rs` and follow its existing
pattern for adding a method.

## iOS resync (FR-6, mandatory — but iOS is NON-GATED)

No Swift codegen. After the proto change + `just check`, re-derive the new
SchedulerService method indices from `out/pylib/anki/_backend_generated.py` and
hand-append them to `ios/Sources/AnkiBackend/AnkiBackend.swift` (scheduler service
id 13); add a dispatch smoke test round-tripping one request/response per new method
(mis-dispatch is SILENT — no compile error). iOS is a NON-GATED demo track (cut
first if the night runs short) — do NOT let iOS block the objective contract, and
do NOT add iOS ACs to the contract.

## Sync-safe HARD rule (FR-5)

NO new SQLite tables/columns on `notes`/`cards`/`revlog`. Per-attempt data → hidden
"Attempt Log" notes; rollups/config → `col` config JSON under `ankountant.*`; small
per-card scalars → `card.custom_data` (JSON ≤100 bytes total, keys ≤8 bytes) at
`rslib/src/storage/card/data.rs`. Precedent to copy: the iOS Reader stores books as
ordinary notes (`ios/Sources/AnkiClients/ReaderBookClient*`) and reading progress as
a `col`-config manifest (`ReaderProgressSyncClient*`). Verify via a `PRAGMA
table_info` round-trip (contract A30).

## Scheduler integration

The desired-retention fed to FSRS is resolved at `Deck::effective_desired_retention`
(`rslib/src/decks/mod.rs:96`) — A1's ramp (and A2's rote reduction, if built) both
ADJUST the retention passed to `next_states` HERE; do NOT post-multiply the interval
(FSRS has no post-multiply hook). FSRS toggled in
`rslib/src/scheduler/answering/mod.rs`; latency already logged as
`RevlogEntry::taken_millis` (`rslib/src/revlog/mod.rs:55`).

## Constants in ONE module (FR-4)

ramp 0.80/0.95/60d; too-easy floor 21d, fast factor 0.5×, retention reduction −0.05
(floor 0.70), trailing-5, min-own-reps 3.

## Tests

Fast inner loop = `just test-rust && just test-py && just test-ts` (this is the
`testCmd` the evaluator runs). Keep `just test-e2e` (Playwright, slow/flaky) OUT of
`testCmd` — each desktop-UI contract assertion (A41–A57) is verified by its OWN
Playwright spec under `ts/tests/e2e/`, and the e2e fixture (`ts/tests/e2e/fixtures.ts`)
must load the FAR seed (F016) before each spec. Add a no-op `just test-ios` stub so
the name resolves; iOS stays non-gated. `.proto` changes need a full `just check`
before tests pass.

## Misc conventions

FTL translations → `ftl/core` (prefer core over qt). ADRs → `docs_ankountant/`. Rust
errors: `rslib` uses `error/mod.rs` `AnkiError`/`Result` + snafu; other crates
anyhow + context; use `rslib/{process,io}` helpers. Prefer reusing existing
utilities/patterns over new code. Per-area `CLAUDE.md` files exist — read the
relevant one (`rslib/src/scheduler/CLAUDE.md`, `proto/CLAUDE.md`, `pylib/anki/CLAUDE.md`,
`qt/aqt/CLAUDE.md`, `ts/CLAUDE.md`, `ios/CLAUDE.md`) before working in that area.

## Scope guard

- **A2 (F002)** latency defunding is P1/parkable and NOT in `contract.md` — build it
  only after all P0 features are green. If the night runs short, leave it `todo`.
- **iOS ACs** are a non-gated demo checklist — never contract assertions.
- **Provenance fields** on the TBS note type are STORED (in-scope, forward-compat)
  but UNPOPULATED (population is Phase 2a — out of scope).
