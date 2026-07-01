# Proto contracts, data model & technical integration

> Implementation reference for the Build agent. Referenced from the feature blocks in `../PRD.md` so it gets opened on demand. Nothing here is read by the loop's Plan/Contract phases.

## New proto surface (append-only, on `SchedulerService`)

Append after the current tail method `simulateFsrsWorkload` — **never reorder existing methods** (protects the hand-maintained iOS indices). Exam date is *set* via the existing config-set RPC (`config.proto`), so there is **no 5th RPC**.

```proto
message ComputeExamScheduleRequest { string section = 1; string exam_date = 2; } // ISO-8601; read-only preview
message ComputeExamScheduleResponse { double desired_retention = 1; repeated CardSchedulePreview cards = 2; }
message CardSchedulePreview { int64 card_id = 1; int32 next_interval_days = 2; }

message BuildConfusionQueueRequest { string section = 1; int32 max_items = 2; }
message BuildConfusionQueueResponse { repeated ConfusionItem items = 1; }
message ConfusionItem { int64 note_id = 1; string prompt = 2; repeated string treatments = 3; string set_id = 4; } // NO category-label field

message GetReadinessRequest { string section = 1; }
message GetReadinessResponse { repeated TopicScore topics = 1; Readiness readiness = 2; }
message TopicScore { string set_id = 1; double memory = 2; double performance = 3; double gap = 4; }
message Readiness { bool abstain = 1; string reason = 2; double band_low = 3; double band_high = 4; string confidence = 5; } // band = accuracy %, 0..100

message SubmitPerformanceAttemptRequest {
  int64 item_note_id = 1; string mode = 2;   // "confusion" | "tbs"
  string submission_json = 3;                // confusion: {"choice":"..."}; tbs: {"steps":[{"id":..,"value":..}]}
  string confidence = 4; uint32 latency_ms = 5;
}
message SubmitPerformanceAttemptResponse { repeated StepResult steps = 1; double total_credit = 2; int64 attempt_note_id = 3; }
message StepResult { string id = 1; bool correct = 2; double weight = 3; }
```

Codegen: edit `proto/anki/scheduler.proto` → **`just check`** (regenerates Rust `rslib/src/services.rs`, Python `out/pylib/anki/_backend_generated.py`, TS `out/ts/lib/generated/backend.ts`). Implement in `rslib/src/backend/scheduler.rs`; surface Python via `pylib/anki/scheduler`.

**iOS index resync (FR-6) — mandatory after each proto change:** re-derive the 4 new method indices from `out/pylib/anki/_backend_generated.py` and append them to `ios/Sources/AnkiBackend/AnkiBackend.swift` (scheduler service id 13; append after `simulateFsrsWorkload`). Add an iOS client **dispatch smoke test** that round-trips one known request/response per new method to catch mis-dispatch (silent, no compile error otherwise).

## Scheduler integration points (from the codebase survey)

- FSRS toggled at `rslib/src/scheduler/answering/mod.rs:179`; `answer_card_inner` at `:311`.
- Desired retention resolved at `Deck::effective_desired_retention` (`rslib/src/decks/mod.rs:96`) — **A1's ramp and A2's rote reduction both plug in here** (adjust the retention fed to `next_states`; do NOT post-multiply the interval — FSRS has no post-multiply hook).
- Latency already logged: `RevlogEntry::taken_millis` (`rslib/src/revlog/mod.rs:55`).
- `card.custom_data`: `rslib/src/storage/card/data.rs:135` — keys ≤ 8 bytes, JSON ≤ 100 bytes total. Holds `te` flag, trailing-5 latencies, latest confidence (A2/A8).
- `col` config JSON: `Collection::get_config_json`/`set_config_json`; namespaced `ankountant.*` keys (Reader already uses `ankountant.reader.progress`).
- Reader precedent (A8 blueprint): `ReaderBookClient*` = books as ordinary notes; `ReaderProgressSyncClient*` = progress as a `col` config manifest. Attempt Log copies the notes half; 3-score rollup copies the col-config half.

## Data model / entities (all standard Anki objects — sync-safe)

| Entity | Store | Key fields | Notes |
|---|---|---|---|
| Schema tag | Anki tag (`ds::…`) on notes | namespaced deep-structure tag | Groups by principle; syncs natively (A6). |
| Cognitive-demand tag | Anki tag (`cog::rote`\|`cog::applied`) on cards' notes | rote vs applied | Gates A2 (rote only). |
| CONFUSABLE map | `col` config `ankountant.confusable.FAR` | `{set_id: {tags:[…], treatments:[…]}}` | Seeded; drives A3/B2; resolves tag→set_id. |
| Study note | standard note/card + `ds::`/`cog::` tags | fields | Normal FSRS schedule. |
| Sealed Performance item | note in `Ankountant::Sealed::FAR`; cards `queue=-1` (suspended) | fields, `ds::` tag | Firewall = permanently suspended (A7). |
| Ankountant TBS note | new note type | `tbs_type`, `prompt`, `exhibits_json`, `steps_json` (`{id,answer_key,weight}`), `schema_tag`, provenance (stored, empty) | All 4 shapes (A9). |
| Attempt Log note | hidden note type, never-queued deck | `item_ref`, `confusion_set_id`, `mode`, `confidence`, `latency_ms`, `outcome_json`, `ts` | Sync-safe per-attempt store (A8); source for the 3 scores. |
| Per-card scalars | `card.custom_data` | `te` flag, trailing-5 latencies, latest confidence | ≤100 bytes (A2/A8). |
| Exam date | `col` config `ankountant.exam.FAR.date` | ISO date | First-class, synced; set via config-set RPC (A1). |
| 3-score rollup | `col` config `ankountant.readiness.FAR` | memory/performance/gap/readiness per topic | Cache; recomputed by A4. |
| Rote latency prior | `col` config `ankountant.latency.rote` | EMA of rote answer times | A2 cold-start baseline. |

## Sync-safety (hard rule, FR-5)

Standard Anki sync transports only notes, cards, notetypes, decks, deck configs, tags, revlog, and `col` config JSON; custom tables are stripped and the schema is force-downgraded to V18. Therefore: **no new SQLite tables or columns on `notes`/`cards`/`revlog`.** All per-attempt data → hidden notes (Attempt Log); all rollups/config → `col` config JSON `ankountant.*`; small per-card scalars → `card.custom_data`. Real cross-device sync is a Phase 2b gate (no server in Phase 1); Phase 1 verifies local round-trip only (A8 AC4).

## Objective gate commands (for the loop config)

- **buildCmd:** `just check` (format + build + clippy/mypy/ruff/tsc/svelte checks).
- **testCmd (fast inner loop):** `just test-rust && just test-py && just test-ts`. Keep `just test-e2e` **out** of the blanket testCmd (Playwright is slow/flaky every iteration); instead each desktop-UI assertion carries its **own** `howToVerify` = a specific Playwright spec the evaluator runs per-assertion.
- **lintCmd:** `just lint`.
- **iOS:** not in `just test`. Add a `just test-ios` stub (no-op placeholder is fine) so the command can be named without erroring; iOS is a non-gated demo track (see `rubrics-frontend.md`).
- Run `just check` (not `cargo check`) after any `.proto` edit.
