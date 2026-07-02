# iOS Surface & Parity Plan — Research + Document-Review TBS

Read-only analysis. This documents how the iOS TBS/confusion surfaces work
today, what has to be added for **research** and **document-review** TBS, and the
exact resync steps if a new RPC (e.g. `SearchLiterature`) is appended.

Scope note: iOS is a **non-gated demo track**, but we want parity with desktop.
The shared Rust core already grades all shapes generically (see §1.4), so the
gap is almost entirely **client rendering + note content**, not backend.

Key file map (all paths repo-relative):

| Layer                      | File                                                                                                            |
| -------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Domain types               | `ios/Sources/AnkiKit/TbsModels.swift`                                                                           |
| Parsing/submission helpers | `ios/Sources/AnkiKit/TbsParsing.swift`                                                                          |
| Phase logic                | `ios/Sources/AnkiKit/StudyPhase.swift`                                                                          |
| Client facade              | `ios/Sources/AnkiClients/PerformanceClient.swift`                                                               |
| Client live impl           | `ios/Sources/AnkiClients/PerformanceClient+Live.swift`                                                          |
| Exam config client         | `ios/Sources/AnkiClients/ExamConfigClient.swift` (+`+Live`)                                                     |
| Service layer              | `ios/Sources/AnkiServices/SchedulerService.swift`                                                               |
| Hand-maintained dispatch   | `ios/Sources/AnkiBackend/AnkiBackend.swift`                                                                     |
| Task view                  | `ios/AnkountantApp/Sources/Simulations/TbsTaskView.swift`                                                       |
| Confusion drill            | `ios/AnkountantApp/Sources/Simulations/ConfusionDrillView.swift`                                                |
| Confidence gate            | `ios/AnkountantApp/Sources/Simulations/ConfidenceGateView.swift`                                                |
| Hub / list                 | `ios/AnkountantApp/Sources/Simulations/SimulationsHubView.swift`                                                |
| Parsing tests              | `ios/Tests/AnkiKitTests/TbsParsingTests.swift`                                                                  |
| Contract                   | `proto/anki/scheduler.proto`                                                                                    |
| Core grading               | `rslib/src/ankountant/grading.rs`, `logic.rs`, `service.rs`, `seed.rs`, `notetypes.rs`                          |
| Desktop parity ref         | `ts/routes/(ankountant)/ankountant-tbs/{lib.ts,TbsSurface.svelte}`, `ankountant-confusion/ConfusionMode.svelte` |

---

## 1. How iOS parses, renders, and submits a TBS note today

### 1.1 Parse (note → `TbsModel`)

- `PerformanceClient.loadTbs(noteId)` → live impl at
  `ios/Sources/AnkiClients/PerformanceClient+Live.swift:26-28` calls
  `buildTbsModel(fields:)` on `note.flds.components(separatedBy: "\u{1f}")`
  (the ASCII Unit-Separator that Anki uses between note fields; see
  `fields(of:)` at `PerformanceClient+Live.swift:12-15`).
- Field order is fixed by `TbsField` (`ios/Sources/AnkiKit/TbsParsing.swift:10-16`):
  `0 tbs_type · 1 prompt · 2 exhibits_json · 3 steps_json · 4 schema_tag`. This
  mirrors `tbs_fields` in `rslib/src/ankountant/notetypes.rs:47-72` (the Rust
  note type actually has **8** fields — it also carries `source_passage=5`,
  `gen_method=6`, `checker_status=7` — which iOS does not map; harmless for
  rendering but keep aligned if provenance is ever surfaced).
- `buildTbsModel` (`TbsParsing.swift:19-27`) sets:
  - `shape`: `TbsShape(rawValue:)` with `.journalEntry` fallback. The enum
    (`ios/Sources/AnkiKit/TbsModels.swift:11-16`) already declares all four
    cases: `journal_entry`, `numeric`, `research`, `doc_review`.
  - `exhibits`: `parseExhibits` (`TbsParsing.swift:30-40`) → `[Exhibit]`
    (`{id,title,body}`), defaulting `title`/`body` leniently.
  - `steps`: `parseSteps` (`TbsParsing.swift:45-57`) → `[RenderStep]`
    (`{id,label,weight}`). **The `answer_key` is intentionally never parsed**
    (grading stays server-authoritative); weight defaults to `1/N`. A test
    asserts the answer key cannot survive parsing
    (`TbsParsingTests.swift:31-34`).

### 1.2 Render (`TbsTaskView`)

- `TbsTaskView.content(_:)` (`TbsTaskView.swift:51-82`) shows the prompt,
  then `switch model.shape`:
  - `.numeric` → `numericGrid` (single value cell per step, decimal pad)
    `TbsTaskView.swift:87-115`.
  - `.journalEntry` → `journalEntryGrid` (account text field + Debit/Credit
    `Picker(.menu)` + amount field) `TbsTaskView.swift:120-158`.
  - **`.research, .docReview` → a hard-coded "This simulation type isn't
    supported yet." placeholder** (`TbsTaskView.swift:66-72`). **This is the gap.**
- Exhibits render via `exhibitsSection` (`TbsTaskView.swift:197-223`) — a
  title + monospace `body`, `textSelection(.enabled)`.
- Per-step correctness is shown by `stepMark(for:)` (`TbsTaskView.swift:228-234`)
  driven by `resultById` built from the graded response.
- Input state is held in `@State jeLines: [JeLineInput]` /
  `numericCells: [NumericCellInput]` (`TbsModels.swift:62-85`), one entry per
  step, seeded in `load()` (`TbsTaskView.swift:248-258`).
- List entry: `SimulationsHubView` lists sealed tasks via
  `performanceClient.listTbsTasks()` and already prints friendly labels for all
  four shapes in `shapeLabel` (`SimulationsHubView.swift:74-81`). Research /
  doc-review notes therefore already appear in the list and open `TbsTaskView`,
  which then shows the placeholder.

### 1.3 Submit (attempt → graded result)

- `TbsTaskView.submit(_:)` (`TbsTaskView.swift:260-275`):
  1. Builds `submissionJson` — `buildNumericSubmission` or `buildJeSubmission`
     (`TbsParsing.swift:60-80`). **Both emit `{"steps":[{"id":…,"value":…}]}`.**
  2. Computes `latencyMs` from `startedAt`.
  3. Calls `performanceClient.submitTbs(noteId, submissionJson, "Unsure", latencyMs)`
     (standalone TBS defaults confidence to `"Unsure"`, matching desktop
     `TbsSurface.svelte:41-50`).
- `PerformanceClient.submitTbs` → live impl (`PerformanceClient+Live.swift:29-31`)
  → `scheduler.submitPerformanceAttempt(noteId, "tbs", submissionJson, confidence, latencyMs)`.
- `SchedulerService.submitPerformanceAttempt` (`SchedulerService.swift:119-136`)
  builds `Anki_Scheduler_SubmitPerformanceAttemptRequest` and calls
  `backend.invoke(service: .scheduler /*13*/, method: .submitPerformanceAttempt)`.

**SchedulerMethod index → `SubmitPerformanceAttempt = 42`**
(`ios/Sources/AnkiBackend/AnkiBackend.swift:336`). Service = `scheduler = 13`
(`AnkiBackend.swift:266`).

### 1.4 Why grading already supports research + doc-review (no new grade path)

- `service.rs` `ankountant_submit_performance_attempt`
  (`rslib/src/ankountant/service.rs:24-103`) reads the note's `steps_json`,
  parses it with `grading::parse_steps`, and `parse_submission(&req.mode, …)`
  (`service.rs:115-137`): mode `"confusion"` → `{"choice":…}`; **anything else
  (incl. `"tbs"`) → `{"steps":[{id,value}]}`**.
- `grading::grade` (`rslib/src/ankountant/grading.rs:53-107`) is fully
  content-driven: each step's `answer_key` is an object (JE line
  `{account,side,amount}`) or a scalar (numeric / **string** citation / **string**
  option). `scalar_matches` tries numeric-with-tolerance then falls back to
  `text_matches` (case/space-insensitive, `logic.rs:214-228`).

➡️ **Research citation** = a step with `answer_key:"FASB ASC 842-20-25-1"`,
submitted as `{"steps":[{"id":"citation","value":"ASC 842-20-25-1"}]}`, mode
`"tbs"`. **Doc-review blank** = a step with `answer_key:"Overstated"`, submitted
as `{"steps":[{"id":"b1","value":"Overstated"}]}`, mode `"tbs"`. **No new RPC
and no Rust grading change are required for the submit/grade path.**

---

## 2. Confusion "which treatment?" + confidence gate (reuse targets)

### 2.1 `ConfidenceGateView` (`ConfidenceGateView.swift`)

- `@Binding committed: ConfidenceLevel?` + `onCommit` callback
  (`ConfidenceGateView.swift:11-12`). Three equal-weight buttons from
  `ConfidenceLevel.allCases` (Guess/Unsure/Confident, `TbsModels.swift:133-137`).
- Commit is **once-only**: after the first pick the others `.disabled` and the
  choice gets brand chrome + `.isSelected` a11y trait — never colour alone
  (`ConfidenceGateView.swift:32-53`). Directly reusable by any gated surface.

### 2.2 `ConfusionDrillView` "which treatment?" (`ConfusionDrillView.swift`)

- Loads the queue via `performanceClient.confusionQueue("FAR", 60)`
  (`ConfusionDrillView.swift:159`) → `SchedulerService.buildConfusionQueue`
  (`SchedulerService.swift:137-147`), service 13 / method **40**
  (`BuildConfusionQueue`, `AnkiBackend.swift:334`).
- Per item: strip dev slug via `stripConfusionSlug` (`TbsParsing.swift:89-100`),
  render `ConfidenceGateView`, and **only after commit** show the treatment
  choices (`ConfusionDrillView.swift:83-91`).
- **The choice control we want to reuse for doc-review blanks** is
  `treatmentButton` (`ConfusionDrillView.swift:103-125`): a full-width,
  left-aligned, ≥44pt tappable row with surface fill + border, `.disabled` once
  answered. It is exactly an option picker for a fixed enum of choices.
- Submit: `choose` (`ConfusionDrillView.swift:167-178`) →
  `performanceClient.submitConfusion(noteId, treatment, confidence, latencyMs)`
  → mode `"confusion"`, `buildChoiceSubmission` = `{"choice":…}`
  (`TbsParsing.swift:83-85`). Verdict = `totalCredit >= 1`.
- Verdict UI (`ConfusionDrillView.swift:127-155`) = icon + label + colour +
  "Next" — reusable for per-blank/per-citation feedback.

➡️ Two reuse options for a doc-review blank: (a) the confusion **button list**
(`treatmentButton`) for a small option set shown inline, or (b) the JE-grid
**`Picker(.menu)`** already used for Debit/Credit (`TbsTaskView.swift:135-140`)
for a compact dropdown. The exam form is a dropdown, so (b) is the closer parity.

---

## 3. New SwiftUI views + model additions

### 3.1 Model additions (`TbsModels.swift` + `TbsParsing.swift`)

All additive and answer-key-free (safe to ship to the client):

- `RenderStep.options: [String]?` — the selectable choices for a **doc-review
  dropdown blank** (the choices are not the key; the key stays server-side).
  `parseSteps` reads an `options` string array when present
  (`TbsParsing.swift:45-57`). Mirror in desktop `lib.ts:81-93`.
- `RenderStep.placeholder`/`format: String?` (optional) — a **research citation**
  input hint (e.g. `"ASC ###-##-##-#"`).
- New binding input structs (peers of `JeLineInput`/`NumericCellInput`,
  `TbsModels.swift:62-85`):
  - `DocReviewBlankInput { id; var selection: String }` (empty = unselected).
  - `ResearchInput { id; var citation: String }` (or per-segment fields if a
    segmented control is used).
- New generic submission builder in `TbsParsing.swift`:
  `buildStepsSubmission(_ pairs: [(id: String, value: String)]) -> String`
  emitting `{"steps":[{"id":…,"value":…}]}` (string values). Research and
  doc-review both use it; JE/numeric can stay on their typed builders. Add a unit
  test alongside `buildNumericSubmission`/`buildChoiceSubmission`
  (`TbsParsingTests.swift:108-128`).
- Doc-review passage: for the MVP, author the document as an **exhibit** (already
  supported) and the blanks as **steps with `label` + `options`**; the view lists
  "Blank 1: <label> [dropdown]". A richer inline-blank passage (tokens like
  `[[b1]]` interpolated into body text) is a follow-up and would need either a
  parsed `segments` model or a `passage` field — call this out but do not block
  MVP on it.

### 3.2 `DocReviewTaskView` (exhibits + dropdown blanks)

- Inputs: `model.exhibits` (the document/financial statements) rendered with the
  existing `exhibitsSection` styling; `model.steps` as the blanks.
- Each blank: a labeled row with `Picker(.menu)` bound to
  `DocReviewBlankInput.selection`, options = `step.options ?? []` plus a "Select"
  sentinel (parity with the JE Debit/Credit picker,
  `TbsTaskView.swift:135-140`). Reuse `stepMark` for post-submit ✓/✗.
- Submit: `buildStepsSubmission(blanks.map { ($0.id, $0.selection) })` →
  `performanceClient.submitTbs(noteId, json, "Unsure", latency)` — **the exact
  existing path**, no new client method.

### 3.3 `ResearchTaskView` (search pane + citation submit)

- Layout: scenario prompt + exhibits, a **search field + results list**, and a
  **citation input** (segmented `ASC [a]-[b]-[c]-[d]` or a single text field with
  `placeholder`).
- Search pane options (pick one; escalates in cost/risk):
  1. **Local bundled corpus (recommended MVP):** ship a small searchable
     FAR-relevant Codification excerpt set as an app resource and filter
     client-side. **Zero proto/index risk.**
  2. **New `SearchLiterature` RPC** backed by the Rust core (see §4). Only worth
     it for an authoritative, synced corpus.
- Submit: `buildStepsSubmission([("citation", enteredCitation)])` →
  `submitTbs(...)` mode `"tbs"`. Grading normalizes text
  (`logic.rs:222-228`), so author `answer_key` as the canonical citation and
  document any accepted variants at authoring time.

### 3.4 Wiring

- Replace the `.research, .docReview` placeholder branch in
  `TbsTaskView.content` (`TbsTaskView.swift:66-72`) with `ResearchTaskView` /
  `DocReviewTaskView`, **or** branch in `SimulationsHubView`'s `NavigationLink`
  (`SimulationsHubView.swift:34-40`) on `task.shape`. Keeping the switch inside
  `TbsTaskView` preserves the single `load()` path.
- New `.swift` files under `ios/AnkountantApp/Sources/Simulations/` are picked up
  automatically: the Xcode target sources `Sources` as a **group**
  (`ios/AnkountantApp/project.yml:40-44`), so `xcodegen generate` re-scans the
  folder — no manual `project.pbxproj` edits.

### 3.5 Content prerequisite (Rust core — blocks "test-accurate")

Today the seed writes research/doc-review as **empty placeholders** only:
`seed.rs:412-424` creates one `research` and one `doc_review` note with
`prompt:"Stored-only <shape> task"`, `exhibits_json:"[]"`, `steps_json:"[]"`.
`seed_content.json` has **no** research/doc-review entries (only `journal_entry`
/ `numeric` under `tbs`). So the new views will render _nothing gradable_ until
the seed is enriched with real research (scenario + citation `answer_key`) and
doc-review (document exhibits + blanks with `options` + `answer_key`) items in
`seed_content.json` + `seed.rs`. **This is the main non-iOS dependency for
"test-accurate" surfaces.**

---

## 4. Method-index resync if a new RPC (e.g. `SearchLiterature`) is appended

> First decide whether you even need one: the **submit/grade path does not**
> (§1.4). A new RPC is only for an in-app authoritative literature search. Prefer
> the local-corpus MVP (§3.3 option 1) to avoid all of the below.

### 4.1 Current index model (must understand before touching)

- Every `SchedulerService` method shares **service = 13**. The Swift enum values
  are **backend** method indices, and the backend service prepends its 3
  `BackendSchedulerService` methods (`ComputeFsrsParamsFromItems`,
  `FsrsBenchmark`, `ExportDataset` — `scheduler.proto:95-102`) before the
  collection methods, so **backend index = collection-method order + 3**
  (documented at `AnkiBackend.swift:311-313`).
- The Ankountant tail is currently (collection order → backend index):
  `ComputeExamSchedule 36→39`, `BuildConfusionQueue 37→40`, `GetReadiness 38→41`,
  `SubmitPerformanceAttempt 39→42`, `LoadFarSeed 40→43` — matching
  `AnkiBackend.swift:333-339` and the proto tail (`scheduler.proto:74-90`).

### 4.2 Resync steps (append `SearchLiterature`)

1. **proto:** add `rpc SearchLiterature(SearchLiteratureRequest) returns
   (SearchLiteratureResponse);` at the **very end of `service SchedulerService`
   (after `LoadFarSeed`, `scheduler.proto:90`)** + the two messages. Appending at
   the tail keeps 39–43 stable. **Do not insert mid-list** — that shifts every
   later index.
2. **Rust:** implement the collection method + service glue (peer of the impls in
   `rslib/src/ankountant/service.rs`; dispatch in the scheduler service module).
3. **`just check`** (NOT `cargo check`) — regenerates, in lockstep, the Rust
   dispatch, Python `out/pylib/anki/_backend_generated.py`, and TS
   `@generated/backend`. (Per `proto/CLAUDE.md` / `.cursor/rules/proto.mdc`.)
4. **Re-derive the iOS index by hand (no Swift codegen):** open the regenerated
   `out/pylib/anki/_backend_generated.py`, find `def search_literature(...)`, and
   read its `self._run_command(13, N, input)` call — `_run_command(service,
   method, input)` is defined at `pylib/anki/_backend.py:159-162`. `N` is the
   backend method index. Appended after `LoadFarSeed` (collection 40→43), the new
   method is **collection 41 → backend 44**. Add
   `searchLiterature: UInt32 = 44` to `SchedulerMethod`
   (`AnkiBackend.swift:314-340`). **Verify against the generated file; never
   guess.** If anyone inserted it mid-list, re-derive `computeExamSchedule` …
   `loadFarSeed` too.
5. **Regenerate Swift protobufs:** `ios/scripts/generate-protos.sh` so
   `Anki_Scheduler_SearchLiteratureRequest/Response` exist in `AnkiProto`.
6. **Rebuild the compiled core:** `ios/scripts/build-xcframework.sh`. The
   xcframework is a **compiled copy of `rslib/`**; without the rebuild, method 44
   does not exist in the binary and the call errors/misdispatches **even with the
   correct Swift index**.
7. **Service layer:** add a `searchLiterature` closure to `SchedulerService`
   (`SchedulerService.swift`) that builds the request and calls
   `backend.invoke(service: .scheduler, method: .searchLiterature, request:)`,
   mapping the response DTO.
8. **Client + call site:** add `PerformanceClient.searchLiterature` to the facade
   (`PerformanceClient.swift:10-22`) and the live impl delegating to
   `scheduler.searchLiterature` (`PerformanceClient+Live.swift:17-38`).
   `ResearchTaskView` then calls `performanceClient.searchLiterature(query)`.
   The `@DependencyClient` macro gives a default `testValue`
   (`PerformanceClient.swift:24-26`) so tests still build.
9. **Build/verify:** `cd ios/AnkountantApp && xcodegen generate`, then
   `xcodebuild build … -scheme AnkountantApp` and `swift test` (per
   `ios/CLAUDE.md`). SourceKit may show false positives — trust the CLI build.

### 4.3 How `PerformanceClient` would call it (sketch)

`ResearchTaskView` → `performanceClient.searchLiterature(query)` →
`PerformanceClient+Live` → `scheduler.searchLiterature(query)` →
`SchedulerService` builds `Anki_Scheduler_SearchLiteratureRequest`, calls
`backend.invoke(service: 13, method: 44)`, returns `[LiteratureHit]`. The
citation submit stays on the **existing** `submitTbs` path (§3.3) — the RPC is
search-only.

---

## 5. AnkiKit parsing changes for new `exhibits_json` / `steps_json` shapes

- **`exhibits_json`** is already generic `[{title, body}]`
  (`parseExhibits`, `TbsParsing.swift:30-40`). Doc-review documents/financial
  statements fit as exhibits with **no schema change**. Only add a `format` key
  if we need rich/HTML rendering beyond the current monospace `body`.
- **`steps_json`** (client side strips `answer_key`; keep it that way):
  - Add optional `options: [String]` (doc-review dropdown choices) to
    `parseSteps` / `RenderStep`.
  - Add optional `placeholder`/`format` (research citation hint).
  - Keep weight default `1/N` (`TbsParsing.swift:46`), matching Rust
    `default_weight` (`logic.rs:242-248`) and the desktop lib.
- **Keep desktop + iOS parsers in lockstep:** mirror the same additions in
  `ts/routes/(ankountant)/ankountant-tbs/lib.ts` (`parseSteps` at `lib.ts:81-93`,
  `RenderStep` at `lib.ts:31-35`) and add a shared `buildStepsSubmission`. Note
  the desktop `TbsSurface.svelte` also lacks real research/doc-review rendering
  today (`{:else}` renders the JE grid, `TbsSurface.svelte:115-180`), so
  "parity" means building these on **both** clients (and, ideally, a shared
  content authoring format).
- **Tests:** extend `ios/Tests/AnkiKitTests/TbsParsingTests.swift` with:
  (a) `parseSteps` preserving `options` and still stripping `answer_key` for the
  new shapes; (b) `buildTbsModel` shape routing for `research`/`doc_review`
  (currently only JE/numeric are asserted, `TbsParsingTests.swift:54-73`);
  (c) a `buildStepsSubmission` round-trip producing `{"steps":[{id,value}]}` with
  string values (peer of `buildNumericSubmission` at `TbsParsingTests.swift:108-123`).

---

## Build / parity checklist (summary)

1. Enrich the FAR seed (`rslib/.../seed_content.json` + `seed.rs:412-424`) with
   real research + doc-review items → `just check` (+ Rust tests).
2. Extend `TbsModels.swift` (`RenderStep.options`/`placeholder`, new input
   structs) and `TbsParsing.swift` (`parseSteps` options, `buildStepsSubmission`);
   mirror in desktop `lib.ts`; add `TbsParsingTests` coverage → `swift test`.
3. Add `DocReviewTaskView` + `ResearchTaskView`; replace the placeholder branch
   in `TbsTaskView.swift:66-72`; reuse `exhibitsSection`, `stepMark`, the JE
   `Picker(.menu)`, and (optionally) the confusion `treatmentButton`.
4. Submit through the **existing** `submitTbs` → `SubmitPerformanceAttempt`
   (service 13 / method 42) path. **No index change for submit.**
5. Only if adding an in-app search: follow §4 (append at proto tail →
   `just check` → re-derive index from `_backend_generated.py` → `= 44` →
   `generate-protos.sh` → `build-xcframework.sh` → service + client + call site).
6. `xcodegen generate` (auto-includes new files) → `xcodebuild build` →
   `swift test`.

### Risk register

- **Index drift (highest):** iOS `SchedulerMethod` is hand-maintained
  (`AnkiBackend.swift:314-340`). Appending anywhere but the proto tail silently
  reindexes 39–43 and every `SchedulerService` call misdispatches. Always
  re-derive from the generated Python.
- **Stale xcframework:** a new RPC needs `build-xcframework.sh`; the Swift index
  can be correct yet the compiled core lacks the method.
- **Content gap:** without seed enrichment the new views render empty/ungradable.
- **Answer leakage:** never add `answer_key` to `RenderStep`/`parseSteps`;
  `options` are safe, the key is not (guarded by `TbsParsingTests.swift:31-34`).
- **Parity asymmetry:** desktop also lacks real research/doc-review surfaces, so
  this is net-new on both clients, not a straight port.
