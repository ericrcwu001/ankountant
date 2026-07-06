# 08 — Rust Backend Change-Map: `research` + `doc_review` TBS grading

> Historical read-only analysis for adding the two formerly deferred TBS shapes
> (`docs_ankountant/PRD-tbs-shapes-future.md`, features T1–T4) to the shared
> Rust core. Scope: exactly what to add/change in `rslib/` + `proto/`, with
> file:line refs. **No code was modified producing this doc.**
>
> HARD constraints honored throughout: sync-safe (no new SQLite tables/columns —
> only notes, `col` config JSON, `card.custom_data`); proto is **append-only**
> (new RPCs appended after `LoadFarSeed`; existing methods never reordered; iOS
> indices hand-maintained).

> **2026-07-06 audit update:** this change-map has landed. The as-built backend
> validates explicit `mode` values in `rslib/src/ankountant/service.rs`, grades
> research citations in `grading.rs` with citation normalization in `logic.rs`,
> stores latency in `attempt_log.rs`, rolls doc-review into fractional
> Performance in `readiness.rs`, and seeds playable research/doc-review content
> from typed section items in `seed.rs`. `SearchLiterature` was not added; both
> clients search the bundled literature corpus client-side.

## 0. TL;DR — the whole change surface

The MVP already made `SubmitPerformanceAttempt` _shape-agnostic_: `mode` and
`submission_json` are free-form strings, and every downstream step (grade →
Attempt Log write → readiness rollup) is generic. Adding the two modes is
therefore **grading branches only**, and requires **no `.proto` change for
grading** (T4).

| Change                                                          | File                                     | Required?                                         |
| --------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------- |
| `parse_submission` gets a `"research"` arm                      | `rslib/src/ankountant/service.rs:115`    | yes                                               |
| grade branch: research uses citation match, else `grade()`      | `rslib/src/ankountant/service.rs:24`     | yes                                               |
| `grade_research()` (single citation step)                       | `rslib/src/ankountant/grading.rs:53`     | yes (research)                                    |
| `citation_normalize` / `citation_matches`                       | `rslib/src/ankountant/logic.rs:211`      | yes (research)                                    |
| `Outcome.elapsed_ms: Option<u32>` (time in `outcome_json`)      | `rslib/src/ankountant/attempt_log.rs:39` | yes (research, T1 AC2)                            |
| readiness partial-credit bucket accepts `doc_review`            | `rslib/src/ankountant/readiness.rs:86`   | **yes (doc_review)**                              |
| doc_review grading                                              | —                                        | **none** (reuses default `steps` arm + `grade()`) |
| seed real research/doc_review items (replace stored-only stubs) | `rslib/src/ankountant/seed.rs:412`       | yes (playable seed)                               |
| `SearchLiterature` RPC                                          | `proto/anki/scheduler.proto:90` (tail)   | **only if** corpus goes server-side (see §5)      |

Everything else — Attempt Log note write (A8), `confusion_set_id` resolution,
`sealed` detection, Wilson band, CPA transform, coverage/volume — is already
mode-agnostic and picks up both modes for free.

---

## 1. Proto: `SubmitPerformanceAttempt`, DTOs, and the method index list

### 1.1 Request / response messages (fields + numbers)

`SubmitPerformanceAttemptRequest` — `proto/anki/scheduler.proto:587`:

```587:595:proto/anki/scheduler.proto
message SubmitPerformanceAttemptRequest {
  int64 item_note_id = 1;
  // "confusion" | "tbs" | "research" | "doc_review"
  string mode = 2;
  // confusion: {"choice":"..."}; research: {"citation":"..."}; tbs/doc_review:
  // {"steps":[{"id":..,"value":..}]}
  string submission_json = 3;
  string confidence = 4;
  uint32 latency_ms = 5;
}
```

`SubmitPerformanceAttemptResponse` + `StepResult` — `proto/anki/scheduler.proto:596`:

```596:605:proto/anki/scheduler.proto
message SubmitPerformanceAttemptResponse {
  repeated StepResult steps = 1;
  double total_credit = 2;
  int64 attempt_note_id = 3;
}
message StepResult {
  string id = 1;
  bool correct = 2;
  double weight = 3;
}
```

**Key finding — no proto field change was needed for T4.** `mode` (field 2) and
`submission_json` (field 3) are opaque strings; the response already models "N
weighted per-step results + a total". `research` returns one `StepResult`
(`id:"citation"`, `weight:1.0`), `doc_review` returns one per blank. The
field-number contract is untouched, so Rust/Python/TS/iOS all keep working with
zero regen. The field comments now document all four shipped modes; that comment
edit is cosmetic and does **not** shift indices.

### 1.2 Current `mode` values, and the mode-vs-shape distinction

Two different vocabularies are in play — do not conflate them:

- **Attempt `mode`** (the RPC `mode` field, persisted to the Attempt Log `mode`
  field): shipped values are **`"confusion"`**, **`"tbs"`**,
  **`"research"`**, and **`"doc_review"`**.
- **Note shape** (`tbs_type`, TBS field 0 — `notetypes.rs:48`): shipped values
  include `"mcq"`, `"journal_entry"`, `"numeric"`, `"research"`, and
  `"doc_review"`; the playable research/doc-review content now comes from the
  typed seed content instead of stored-only placeholders.

The mapping is **not** 1:1: an `mcq`-shape sealed item is submitted with
`mode="confusion"` (single `"choice"` step), while `journal_entry`/`numeric`
items submit `mode="tbs"`. The shipped mapping for the newer shapes is 1:1:
`research`-shape → `mode="research"`, `doc_review`-shape → `mode="doc_review"`,
so analytics can tell them apart.

### 1.3 `ConfusionItem` / TBS DTOs and `BuildConfusionQueue`

`ConfusionItem` (label-stripped by construction) — `proto/anki/scheduler.proto:537`:

```535:542:proto/anki/scheduler.proto
// The client-facing DTO deliberately omits any topic/category/deck label so the
// learner discriminates on content, not on a printed answer.
message ConfusionItem {
  int64 note_id = 1;
  string prompt = 2;
  repeated string treatments = 3;
  string set_id = 4;
}
```

`BuildConfusionQueue{Request,Response}` — `proto/anki/scheduler.proto:528`:

```528:534:proto/anki/scheduler.proto
message BuildConfusionQueueRequest {
  string section = 1;
  int32 max_items = 2;
}
message BuildConfusionQueueResponse {
  repeated ConfusionItem items = 1;
}
```

`ConfusionItem.treatments` (field 3) is the label-stripped candidate list a
doc_review **blank** re-uses (T3 AC2). For doc_review those candidates come from
the CONFUSABLE map keyed by each blank's `confusion_set_id` (`config.rs:44`
`ConfusionSet.treatments`), and are authored into `steps_json` per blank (§4) or
resolved client-side — no new DTO needed. There is **no TBS list DTO**: the seed
returns sealed TBS note ids directly in `LoadFarSeedResponse.sealed_tbs_note_ids`
(`scheduler.proto:624`) and the client deep-links `?note=<id>`.

### 1.4 `SchedulerService` method index list (for iOS resync)

The service's method order is the index contract. Full
**collection-order** list (`proto/anki/scheduler.proto:17`), 0-indexed:

| idx | method                         | idx | method                                    |
| --- | ------------------------------ | --- | ----------------------------------------- |
| 0   | GetQueuedCards                 | 21  | DescribeNextStates                        |
| 1   | AnswerCard                     | 22  | StateIsLeech                              |
| 2   | SchedTimingToday               | 23  | UpgradeScheduler                          |
| 3   | StudiedToday                   | 24  | CustomStudy                               |
| 4   | StudiedTodayMessage            | 25  | CustomStudyDefaults                       |
| 5   | UpdateStats                    | 26  | RepositionDefaults                        |
| 6   | ExtendLimits                   | 27  | ComputeFsrsParams                         |
| 7   | CountsForDeckToday             | 28  | GetOptimalRetentionParameters             |
| 8   | CongratsInfo                   | 29  | ComputeOptimalRetention                   |
| 9   | RestoreBuriedAndSuspendedCards | 30  | SimulateFsrsReview                        |
| 10  | UnburyDeck                     | 31  | SimulateFsrsWorkload                      |
| 11  | BuryOrSuspendCards             | 32  | EvaluateParams                            |
| 12  | EmptyFilteredDeck              | 33  | EvaluateParamsLegacy                      |
| 13  | RebuildFilteredDeck            | 34  | ComputeMemoryState                        |
| 14  | ScheduleCardsAsNew             | 35  | FuzzDelta                                 |
| 15  | ScheduleCardsAsNewDefaults     | 36  | **ComputeExamSchedule** (Ankountant)      |
| 16  | SetDueDate                     | 37  | **BuildConfusionQueue** (Ankountant)      |
| 17  | GradeNow                       | 38  | **GetReadiness** (Ankountant)             |
| 18  | SortCards                      | 39  | **SubmitPerformanceAttempt** (Ankountant) |
| 19  | SortDeck                       | 40  | **LoadFarSeed** (F016)                    |
| 20  | GetSchedulingStates            |     |                                           |

**iOS dispatch uses the backend (odd) service id 13**, which prepends the 3
`BackendSchedulerService` methods (`ComputeFsrsParamsFromItems`, `FsrsBenchmark`,
`ExportDataset` — `scheduler.proto:95`). So **iOS index = collection index + 3**.
Confirmed against the hand-maintained table (`ios/Sources/AnkiBackend/AnkiBackend.swift:314`):

```329:339:ios/Sources/AnkiBackend/AnkiBackend.swift
// Ankountant (FAR MVP) additions, appended after FuzzDelta (38).
// Re-derived from out/pylib/anki/_backend_generated.py (service 13):
// compute_exam_schedule=39, build_confusion_queue=40, get_readiness=41,
// submit_performance_attempt=42, load_far_seed=43.
package static let computeExamSchedule: UInt32 = 39
package static let buildConfusionQueue: UInt32 = 40
package static let getReadiness: UInt32 = 41
package static let submitPerformanceAttempt: UInt32 = 42
// F016 FAR demo seed loader ...
package static let loadFarSeed: UInt32 = 43
```

**Consequence for this feature:** because T4 grading needs **no** proto change,
the entire index table above is **stable** and iOS needs **no resync** for
`research`/`doc_review`. The only thing that would move iOS is adding
`SearchLiterature` (§5), which appends at collection idx **41** → iOS idx **44**
(nothing before it shifts, since it's the new tail).

---

## 2. Current `grade()` flow and the `outcome_json` shape

### 2.1 End-to-end write path

`Collection::ankountant_submit_performance_attempt` — `service.rs:24`:

1. Load the item note by `item_note_id`; read `steps_json` from TBS field
   `STEPS_JSON` (index 3) — `service.rs:29-37`, field const `notetypes.rs:51`.
2. `grading::parse_steps(&steps_json)` → `Vec<GradableStep>` (`service.rs:38`,
   `grading.rs:39`). `GradableStep = {id, answer_key: Value, weight?, tolerance?}`
   (`grading.rs:19`).
3. `parse_submission(&req.mode, &req.submission_json)` → `HashMap<String, Value>`
   (id → submitted value) — `service.rs:41`, impl `service.rs:115`.
4. `grading::grade(&steps, &submitted)` → `(Vec<StepOutcome>, f64 total_credit)`
   — `service.rs:42`, impl `grading.rs:53`.
5. Resolve `confusion_set_id` from the note's `schema_tag` (TBS field 4) or its
   ordinary tags via the CONFUSABLE map — `service.rs:44-57`
   (`config.rs:66` `ankountant_set_for_tag`).
6. Detect `sealed` via deck search `nid:<id> deck:Ankountant::Sealed::<section>::*`
   — `service.rs:60`, impl `service.rs:106`.
7. Build `Outcome{credit, steps}` and `NewAttempt{...}` — `service.rs:62-83`.
8. `ankountant_write_attempt` inside `transact(Op::AddNote, …)` — one hidden
   Attempt Log note, its card suspended (A8) — `service.rs:88`,
   impl `attempt_log.rs:69`.
9. Return `SubmitPerformanceAttemptResponse{steps, total_credit, attempt_note_id}`
   — `service.rs:91-102`.

Per-step matching (`grading.rs:75` `step_matches` → `grading.rs:93`
`scalar_matches`): a **journal-entry** answer key is a JSON object and every
sub-field (`account`/`side`/`amount`) must match; a **scalar** cell tries numeric
tolerance first (`logic::numeric_matches`, strips `$ , %`), then falls back to
trim+lowercase text (`logic::text_matches`) — `logic.rs:214` / `logic.rs:222`.
Default numeric tolerance `0.01` (`constants.rs:68`). Weights default to `1/N`
(`grading.rs:45`, `logic.rs:242`).

### 2.2 `parse_submission` — the only mode-branching code today

```115:137:rslib/src/ankountant/service.rs
fn parse_submission(mode: &str, json: &str) -> Result<HashMap<String, Value>> {
    let mut out = HashMap::new();
    let root: Value = serde_json::from_str(json).or_invalid("invalid submission_json")?;
    match mode {
        "confusion" => {
            if let Some(choice) = root.get("choice") {
                out.insert("choice".to_string(), choice.clone());
            }
        }
        _ => {
            if let Some(steps) = root.get("steps").and_then(|v| v.as_array()) {
                for step in steps {
                    if let (Some(id), Some(value)) = (step.get("id"), step.get("value")) {
                        if let Some(id) = id.as_str() {
                            out.insert(id.to_string(), value.clone());
                        }
                    }
                }
            }
        }
    }
    Ok(out)
}
```

**Important:** the `_ =>` (default) arm already parses `{"steps":[{"id","value"}]}`
for _any_ non-confusion mode. That means **`doc_review` already parses correctly**
today if it submits in the `steps` format (see §3.2).

### 2.3 `outcome_json` shape

Written by `ankountant_write_attempt` via `serde_json::to_string(&attempt.outcome)`
(`attempt_log.rs:73`); the struct is `attempt_log.rs:39`:

```39:52:rslib/src/ankountant/attempt_log.rs
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(crate) struct Outcome {
    #[serde(default)]
    pub(crate) credit: f64,
    #[serde(default)]
    pub(crate) steps: Vec<OutcomeStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(crate) struct OutcomeStep {
    pub(crate) id: String,
    pub(crate) correct: bool,
    pub(crate) weight: f64,
}
```

Concrete stored value for a 4-line JE at 3/4 correct:

```json
{
    "credit": 0.75,
    "steps": [
        { "id": "l1", "correct": true, "weight": 0.25 },
        { "id": "l2", "correct": true, "weight": 0.25 },
        { "id": "l3", "correct": true, "weight": 0.25 },
        { "id": "l4", "correct": false, "weight": 0.25 }
    ]
}
```

For `confusion`, `credit` is `1.0`/`0.0` and `steps` has one entry `id:"choice"`.
It round-trips on read in `ankountant_attempts` (`attempt_log.rs:110-113`).

**Latency finding:** `latency_ms` is persisted as its own Attempt Log field
(`f::LATENCY_MS = 4`, written at `attempt_log.rs:78`) **but is never read back** —
`AttemptRecord` (`attempt_log.rs:20`) and the reader (`attempt_log.rs:95-128`)
omit it. So today time is write-only. To _surface_ research time (T1 AC2) the
cheapest path is to also put it inside `outcome_json`, which **is** parsed back
(§3.1).

---

## 3. What to ADD for the two modes

### 3.1 `mode = "research"` (citation, correct/incorrect + time)

Research is a **single-answer citation match**, not per-cell grading. Add four
small pieces:

**(a) `parse_submission` arm** — `service.rs:115`. Insert before the `_ =>`:

```rust
"research" => {
    if let Some(c) = root.get("citation") {
        out.insert("citation".to_string(), c.clone());
    }
}
```

**(b) citation normalization** — new pure fns in `logic.rs` (next to the existing
`numeric_matches`/`text_matches`, `logic.rs:211`):

```rust
/// Canonicalize an authoritative citation for comparison: upper-case, drop the
/// optional corpus prefix (ASC/IRC/AU-C/AS), and keep only digits + separators
/// collapsed to single hyphens (so "ASC 842-20-25-1" == "842-20-25-1").
pub(crate) fn citation_normalize(s: &str) -> String { /* ... */ }

pub(crate) fn citation_matches(accepted: &str, submitted: &str) -> bool {
    citation_normalize(accepted) == citation_normalize(submitted)
}
```

Rationale in PRD R2 (`PRD-tbs-shapes-future.md:114`): many valid spellings of one
cite → accepted-list + normalization.

**(c) `grade_research`** — new fn in `grading.rs` (mirrors `grade()`,
`grading.rs:53`, and reuses `StepOutcome`/`effective_weights`):

```rust
/// Research items carry a single gradable step (id "citation") whose answer_key
/// is a string OR an array of accepted citation variants. Correct iff the
/// submitted citation citation-normalizes-equal to ANY accepted variant.
pub(crate) fn grade_research(
    steps: &[GradableStep],
    submitted: &HashMap<String, Value>,
) -> (Vec<StepOutcome>, f64) { /* per-step, credit = weightΣ of correct */ }
```

Accepted variants live in the answer key as an array (`answer_key: ["ASC 842-20-25-1", "842-20-25-1"]`).
`grade_research` iterates `accepted.iter().any(|a| logic::citation_matches(a, sub))`,
handling both a scalar and an array key. (Alternative that avoids a second fn: add
a `Value::Array(accepted) =>` arm to `grading::step_matches` at `grading.rs:79`
and route research through the normal `grade()`; noted, but a dedicated fn keeps
citation semantics from leaking into JE/numeric grading.)

**(d) service branch + time in `outcome_json`** — `service.rs:42` / `service.rs:62`:

```rust
let (outcomes, total_credit) = if req.mode == "research" {
    grading::grade_research(&steps, &submitted)
} else {
    grading::grade(&steps, &submitted)   // tbs + doc_review
};
// ...
let outcome = Outcome {
    credit: total_credit,
    steps: /* map as today */,
    elapsed_ms: (req.mode == "research").then_some(req.latency_ms),
};
```

with `Outcome` extended (backward-compatible — `#[serde(default)]` means old
notes without the key still deserialize) — `attempt_log.rs:39`:

```rust
#[serde(default, skip_serializing_if = "Option::is_none")]
pub(crate) elapsed_ms: Option<u32>,
```

Credit is correctness only (1.0/0.0); **time is a reported secondary signal, not a
credit multiplier** — matches PRD OQ-2 / T1 behavior (`PRD-tbs-shapes-future.md:47`).
Response for research: `steps=[{id:"citation",correct,weight:1.0}]`,
`total_credit ∈ {0.0,1.0}`.

### 3.2 `mode = "doc_review"` (exhibits + N blanks, per-blank partial credit)

**Grading is essentially free** — it reuses per-step grading verbatim:

- `parse_submission` default arm already reads `{"steps":[{"id","value"}]}`
  (`service.rs:124`), so a doc_review submission parses with **no new arm**.
  (Optional: add an explicit `"doc_review" =>` that mirrors the default arm for
  readability; behavior identical.)
- `grade()` matches each blank's submitted treatment string against its
  `answer_key` treatment string via `scalar_matches → text_matches`
  (`grading.rs:104`, trim+case-insensitive), yielding **per-blank partial credit
  = Σ(weight × correct)** with no changes.
- One Attempt Log note per item (A8), `outcome_json.steps` = per-blank results —
  automatic (`service.rs:88`).

What doc_review needs beyond grading:

1. **Per-blank authoring in `steps_json`** — each blank is one step carrying its
   correct treatment (`answer_key`), plus **rendering-only** extras the grader
   ignores: `confusion_set_id` and `options` (the label-stripped treatments), and
   an optional `label` (schema in §4). `GradableStep` only deserializes
   `id/answer_key/weight/tolerance` (`grading.rs:19`); serde silently drops the
   extra keys, so they are safe to store.
2. **readiness partial-credit bucket** — the one required non-grading change, so
   doc_review counts as _fractional_ Performance rather than pass/fail (§6).
3. **Single `confusion_set_id` per attempt** (a limitation to note): the attempt
   resolves ONE `confusion_set_id` from the note's `schema_tag`
   (`service.rs:47-57`). A doc_review item spanning multiple sets credits its
   whole partial score to that one set. This matches how every TBS note carries a
   single `schema_tag` today; per-blank set attribution is out of MVP scope
   (per-blank `confusion_set_id` is still stored in `steps_json` for the UI and
   future analytics).

---

## 4. Proposed `exhibits_json` + `steps_json` schemas

Both shapes reuse the existing `Ankountant TBS` fields (`notetypes.rs:47`):
`tbs_type`(0), `prompt`(1), `exhibits_json`(2), `steps_json`(3), `schema_tag`(4).
`exhibits_json` is a JSON array of `{title, body}` (parsed by the seed's `Exhibit`
`seed.rs:103` and the TS `parseExhibits` `lib.ts:56`).

### 4.1 `research`

```jsonc
// tbs_type = "research"; schema_tag = a ds:: tag (for set attribution)
// exhibits_json — optional scenario/fact pattern (same {title,body} shape)
[
  { "title": "Fact pattern",
    "body": "Lessee signs a 5-year lease with a purchase option reasonably certain to be exercised. Which Codification paragraph governs the lease classification test?" }
]
// steps_json — ONE citation step; answer_key = accepted variants (array).
// `corpus` is an optional client hint for which literature pane to open.
[
  { "id": "citation",
    "answer_key": ["ASC 842-10-25-2", "842-10-25-2"],
    "weight": 1.0,
    "label": "Governing citation",
    "corpus": "asc" }
]
// submission_json (client → RPC)
{ "citation": "ASC 842-10-25-2" }
// outcome_json (stored)
{ "credit": 1.0, "elapsed_ms": 18500,
  "steps": [ { "id": "citation", "correct": true, "weight": 1.0 } ] }
```

### 4.2 `doc_review`

```jsonc
// tbs_type = "doc_review"; schema_tag = the item's dominant ds:: tag
// exhibits_json — the exhibits pane (N documents), same {title,body} shape
[
  { "title": "Lease agreement",   "body": "Term 6 yrs; economic life 7 yrs; no transfer of title; no bargain purchase option..." },
  { "title": "Repairs ledger",    "body": "$40,000 routine servicing; $180,000 to extend the asset's useful life by 4 years..." }
]
// steps_json — ONE step per blank. answer_key = correct treatment (secret).
// confusion_set_id + options + label are render-only; the grader ignores them.
[
  { "id": "b1", "answer_key": "Finance lease",
    "confusion_set_id": "operating_vs_finance_lease",
    "options": ["Operating lease", "Finance lease"],
    "weight": 0.5, "label": "Blank 1 — lease classification" },
  { "id": "b2", "answer_key": "Capitalize",
    "confusion_set_id": "capitalize_vs_expense",
    "options": ["Capitalize", "Expense"],
    "weight": 0.5, "label": "Blank 2 — repair vs improvement" }
]
// submission_json (client → RPC) — reuses the tbs "steps" format
{ "steps": [ { "id": "b1", "value": "Finance lease" },
             { "id": "b2", "value": "Expense" } ] }
// outcome_json (stored)
{ "credit": 0.5, "steps": [ { "id": "b1", "correct": true,  "weight": 0.5 },
                            { "id": "b2", "correct": false, "weight": 0.5 } ] }
```

Notes:

- `options` may be **omitted** and resolved client-side from the CONFUSABLE map
  by `confusion_set_id` (`config.rs:44` `ConfusionSet.treatments`); storing them
  inline is simplest and keeps the note self-contained.
- **Frontend contract:** `lib.ts` `parseSteps` (`lib.ts:81`) currently keeps only
  `{id,label,weight}` and drops `answer_key` (good — the key must never render).
  It must be extended to surface `options` + `confusion_set_id` for doc_review
  blanks, and add `buildResearchSubmission` (`{citation}`) /
  `buildDocReviewSubmission` (`{steps:[…]}`) helpers next to the existing
  `buildJeSubmission`/`buildNumericSubmission` (`lib.ts:118-146`). (Frontend work,
  out of this Rust change-map's scope, listed for completeness.)

### 4.3 Seed (`seed.rs`) — playable typed items

Historical context: the original seed wrote empty, unplayable placeholders
(`exhibits_json="[]"`, `steps_json="[]"`) — `seed.rs:412`:

```415:424:rslib/src/ankountant/seed.rs
for shape in ["research", "doc_review"] {
    let mut note = tbs_nt.new_note();
    note.set_field(tbs_fields::TBS_TYPE, shape)?;
    note.set_field(tbs_fields::PROMPT, format!("Stored-only {shape} task"))?;
    note.set_field(tbs_fields::EXHIBITS_JSON, "[]")?;
    note.set_field(tbs_fields::STEPS_JSON, "[]")?;
    note.set_field(tbs_fields::SCHEMA_TAG, SETS[0].tags[0])?;
    self.add_note_inner(&mut note, misc_deck)?;
    self.suspend_note_cards(note.id)?;
}
```

The as-built seed replaces that loop with section-agnostic `section_items[]`
content. Research items carry accepted citation arrays that must exist in the
bundled literature corpus; document-review items carry a primary document exhibit
with `<blank step="...">` markers plus per-blank options. The seed validates this
typed structure before writing sync-safe JSON into the existing TBS fields.

---

## 5. Corpus search (T2): client-side vs a new `SearchLiterature` RPC

**Recommendation: client-side over a bundled, seed-scoped file — no new RPC.**
The corpus is a curated _excerpt_ set (PRD non-goal: not the full codification —
`PRD-tbs-shapes-future.md:17,60`), so a linear substring/keyword scan over
`{citation,title,body}` in TS/Swift is instant and offline (NFR-2), and it keeps
the append-only proto surface + hand-maintained iOS table **untouched**.

Where the data lives (all sync-safe):

- **Bundled static asset** (preferred): a JSON shipped with each client (TS
  imports it in the research route; iOS bundles a resource). Not synced — it is
  read-only reference data, like app assets. Accepted citations for _grading_
  already travel with the note in `steps_json` (§4.1), so the corpus is purely a
  navigation aid.
- **Or `col` config JSON** if a single authored source of truth is preferred —
  key `ankountant.literature.<section>` (same pattern as the CONFUSABLE map,
  `config.rs:24`), read via the existing config RPCs on both clients
  (`ios/.../AnkiBackend.swift:142` `getConfigJSONValue`). No new table (FR-5).

**Only add a backend RPC if** the corpus outgrows client bundling or must be
ranked/authoritative in Rust. If so — **exact append-only placement** (tail of
`SchedulerService`, after `LoadFarSeed` at `scheduler.proto:90`):

```proto
// T2: keyword search over the bundled scoped literature corpus for a section.
rpc SearchLiterature(SearchLiteratureRequest) returns (SearchLiteratureResponse);
```

New messages appended after `LoadFarSeedResponse` (after `scheduler.proto:625`):

```proto
message SearchLiteratureRequest {
  string section = 1;
  string query = 2;
  int32 max_results = 3;
}
message SearchLiteratureResponse { repeated LiteraturePassage passages = 1; }
message LiteraturePassage {
  string citation = 1;
  string title = 2;
  string body = 3;
}
```

Index impact of that RPC (append-only, so nothing existing shifts):

- Collection-order idx **41**; Backend/iOS idx **44** (= 41 + 3).
- iOS: add `searchLiterature: UInt32 = 44` to `SchedulerMethod`
  (`ios/Sources/AnkiBackend/AnkiBackend.swift:314`), re-derived from the
  regenerated `out/pylib/anki/_backend_generated.py` after `just check`.
- Rust: add `fn search_literature` to the `SchedulerService` impl
  (`rslib/src/scheduler/service/mod.rs:386`, alongside the other Ankountant
  methods) dispatching into a new `ankountant/literature.rs` (corpus from
  `include_str!` or `col` config). Requires a full `just check` (proto contract
  change), per `proto/CLAUDE.md`.

Verdict on OQ-3 (`PRD-tbs-shapes-future.md:121`): **client-side** for the MVP
seed corpus; keep `SearchLiterature` in the back pocket for a larger corpus.

---

## 6. Readiness / Performance already consumes TBS partial credit

Performance is computed in `ankountant_get_readiness` (`readiness.rs:64`). It
loops **sealed** attempts and buckets by mode (`readiness.rs:79`):

```84:101:rslib/src/ankountant/readiness.rs
sealed_attempts += 1;
let acc = perf.entry(a.confusion_set_id.clone()).or_default();
match a.mode.as_str() {
    "tbs" => {
        acc.tbs_credit += a.outcome.credit;
        acc.tbs_total += 1.0;
        sealed_correct += a.outcome.credit;
        sealed_total += 1.0;
    }
    _ => {
        // confusion / MCQ: pass/fail on credit >= 0.5
        let c = if a.outcome.credit >= 0.5 { 1.0 } else { 0.0 };
        acc.mcq_correct += c;
        acc.mcq_total += 1.0;
        sealed_correct += c;
        sealed_total += 1.0;
    }
}
```

There are exactly two buckets: **`"tbs"` = fractional** (partial credit), and
**everything-else = pass/fail** (`credit ≥ 0.5`). `PerfAccum::performance` blends
them 50/50 when both exist (`readiness.rs:32`, weights `constants.rs:39-40`), and
`effective_n` = mcq + tbs counts (`readiness.rs:47`). Everything after that —
per-topic Wilson bands (`readiness.rs:112`), coverage & volume abstain
(`readiness.rs:142-171`), the CPA 0–99 transform (`readiness.rs:175-186`,
`logic.rs:135`) — is mode-agnostic.

How the new modes flow through:

- **`research` → zero change.** It produces binary correctness (1.0/0.0), which is
  exactly the pass/fail semantics of the `_` (MCQ-like) bucket. It correctly lands
  there as a pass/fail Performance signal; time stays a secondary signal, never
  folded into credit (PRD OQ-2). Coverage/volume/band include it automatically
  because it is sealed, has a `confusion_set_id`, and writes one attempt note.

- **`doc_review` → one required line.** Its fractional per-blank credit must be
  treated as **partial** (the `"tbs"` bucket); otherwise the `_` arm would collapse
  it to pass/fail at the 0.5 threshold and lose partial credit. The change
  (`readiness.rs:87`):

```rust
// fractional partial-credit modes
"tbs" | "doc_review" => { /* existing tbs body */ }
```

(Cleaner: a `fn is_partial_credit_mode(mode: &str) -> bool` in `constants.rs`/
`logic.rs` so the set of fractional modes is defined once.) With this,
doc_review's partial credit moves Performance and `gap = memory − performance`
identically to JE/numeric TBS (T3 AC4). This mirrors the existing partial-credit
test pattern (`tests.rs:1024` `a4_tbs_partial_credit_moves_performance`).

No other reader branches on mode except `confusion.rs:85`
(`ankountant_set_accuracy`, `a.mode == "confusion"`), which only orders the
confusion _queue_ by weakness — research/doc_review are not confusion-queue items,
so it needs no change.

---

## 7. Sanity checks against the HARD constraints

- **Sync-safe (FR-5):** no new tables/columns. New data rides in existing note
  fields (`steps_json`/`exhibits_json`), the Attempt Log note (`outcome_json`),
  and — only if a backend corpus is chosen — a `col` config key. `Outcome`'s new
  `elapsed_ms` is `#[serde(default)]`, so old collections round-trip unchanged.
  The schema-stability test (`tests.rs:599` `a8_no_schema_change...`) still holds.
- **Append-only proto (FR-6):** T4 grading needs **no** proto edit (free-form
  `mode`/`submission_json`). The only optional proto addition (`SearchLiterature`)
  is appended at the service tail; no existing method reorders, so iOS indices
  0–43 are stable (new method → iOS 44).
- **Right impl location:** `SubmitPerformanceAttempt` dispatches in
  `rslib/src/scheduler/service/mod.rs:412` into
  `Collection::ankountant_submit_performance_attempt`
  (`rslib/src/ankountant/service.rs:24`). The PRD's mention of
  `rslib/src/backend/scheduler.rs` is **stale** — that path is not where grading
  lives; all edits target `ankountant/{service,grading,logic,attempt_log,
  readiness,seed}.rs`.
- **Testing:** extend `tests.rs` (`submit` helper `tests.rs:482`) with a research
  correct/incorrect + `elapsed_ms` case and a doc_review multi-blank partial-credit
  - readiness case; run `just check` (full regen) since anything touching proto
    needs it, otherwise `just test-rust`.
