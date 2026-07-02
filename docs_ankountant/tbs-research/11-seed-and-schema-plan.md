# 11 — Seeding real Research & Document-Review TBS: current shapes, proposed schemas, and a sync-safe seed plan

> **Status:** analysis + plan (no code changed) · Owner: eric · Date: 2026-07-02
> **Scope:** how the FAR seed authors TBS today (`rslib/src/ankountant/seed.rs`),
> how attempts/grading flow (`attempt_log.rs`, `grading.rs`, `service.rs`,
> `readiness.rs`), and a concrete plan to seed ~6–10 **real** research +
> document-review items **without any new SQLite table/column or note-type field**
> (FR-5 sync-safety).
> **Related:** `docs_ankountant/PRD-tbs-shapes-future.md` (T1–T4 for these two
> shapes), `docs_ankountant/rag/01-sources-and-licensing.md` (Tier-A/Tier-B
> firewall), `docs_ankountant/adr/0004-far-demo-profile-seed.md`.

---

## 0. The one invariant everything hangs on

**"Sync-safe / no new fields" means:** the `Ankountant TBS` note type keeps its
**8 fixed fields** and the `Ankountant Attempt Log` note type keeps its **9
fixed fields**. All new structure for research/doc-review is **nested JSON inside
the existing `exhibits_json` and `steps_json` TEXT fields**. No new proto message
fields are strictly required (see §4.5). This is possible because of one fact:

> **`grading::GradableStep` (and `attempt_log::Outcome`/`OutcomeStep`) derive
> `Deserialize` WITHOUT `#[serde(deny_unknown_fields)]`, so any extra keys in a
> step object are silently ignored by the grader.**
> — `rslib/src/ankountant/grading.rs:18-28`

That is the whole trick: `options[]`, `confusion_set_id`, `accepted_citations[]`,
`corpus_refs[]`, `label`, `weight`, `tolerance` can all ride inside a
`steps_json` step; the Rust grader only ever reads `id`, `answer_key`, `weight`,
`tolerance`, and ignores the rest. The frontend and the (future) T4 grading arm
read the rest.

### Source map (what I read)

| File                                           | Role                                                                                                                          |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `rslib/src/ankountant/seed.rs`                 | Authors all seed notes; `SeedSummary`; `LoadFarSeed` response; sealed-deck placement + suspend; `content_tbs_steps` transform |
| `rslib/src/ankountant/seed_content.json`       | Embedded (`include_str!`) content: `recall[]`, `mcqs{}`, `tbs[]`                                                              |
| `rslib/src/ankountant/notetypes.rs`            | Field order for TBS (`tbs_fields`) + Attempt Log (`attempt_fields`)                                                           |
| `rslib/src/ankountant/grading.rs`              | `GradableStep`, `parse_steps`, `grade`, `step_matches` (the step schema)                                                      |
| `rslib/src/ankountant/attempt_log.rs`          | `Outcome`/`OutcomeStep` (`outcome_json`), `ankountant_write_attempt`                                                          |
| `rslib/src/ankountant/service.rs`              | `SubmitPerformanceAttempt`: parse submission → grade → resolve set → detect sealed → write attempt                            |
| `rslib/src/ankountant/readiness.rs`            | Performance rollup (sealed-only, mode buckets) + Memory (study-pile only)                                                     |
| `rslib/src/ankountant/confusion.rs`            | Confusion queue gathers **sealed** notes by `ds::` tag                                                                        |
| `rslib/src/ankountant/config.rs`               | `ankountant.confusable.<section>` map: `ds::` tag → set_id                                                                    |
| `ts/routes/(ankountant)/ankountant-tbs/lib.ts` | Frontend parse of `exhibits_json`/`steps_json` + submission builders                                                          |

---

## 1. The concrete current JSON shapes

### 1.1 `exhibits_json` — a JSON array of `{title, body}`

Authoring struct (`seed.rs:103-107`):

```rust
struct Exhibit { title: String, body: String }
```

Field index 2 of the TBS note type (`notetypes.rs:47-72`,
`tbs_fields::EXHIBITS_JSON = 2`). Frontend mirror `parseExhibits`
(`ts/.../ankountant-tbs/lib.ts:56-68`) coerces each entry to `{title, body}`.

**Real values written by the seed today:**

- Pinned anchor JE (`seed.rs:776-779`):

```json
[{ "title": "Lease schedule", "body": "See amortization table." }]
```

- A content numeric item (`seed_content.json:1372-1377`):

```json
[
    {
        "title": "Cost classification",
        "body": "Capitalize only costs necessary to bring the asset to its condition and location for intended use: invoice net of the 2% discount ($196,000) + freight-in ($5,000) + installation ($8,000) + testing ($2,000). First-year insurance and operator training are period costs (expensed)."
    }
]
```

- MCQ items, the pinned numeric, and the stored-only research/doc_review stubs
  all write the empty array `"[]"` (`seed.rs:320`, `801`, `419`).

### 1.2 `steps_json` — the graded step schema (`grading::GradableStep`)

Field index 3 (`tbs_fields::STEPS_JSON = 3`). Parsed into
(`grading.rs:18-42`):

```rust
struct GradableStep {
    id: String,                 // required
    answer_key: Value,          // required; scalar OR object
    #[serde(default)] weight: Option<f64>,     // default 1/N (default_weight)
    #[serde(default)] tolerance: Option<f64>,  // default 0.01 (DEFAULT_NUMERIC_TOLERANCE)
}
```

Grading is line-by-line: `grade()` sums `Σ(weight × correct)`
(`grading.rs:53-73`). `step_matches` (`grading.rs:75-107`) has two branches:

- **`answer_key` is an object** (JE line): every keyed sub-field must match
  (`{account, side, amount}`), each via `scalar_matches` (numeric-first, else
  trim+lowercase text) (`grading.rs:80-91`, `logic.rs:214-228`).
- **`answer_key` is a scalar** (numeric cell / string): `scalar_matches` with
  per-step `tolerance` (`grading.rs:88-90`).

**Two concrete graded shapes as written today.**

Pinned anchor **journal-entry** (`seed.rs:764-769`) — note `answer_key` is an
object per line:

```json
[
    {
        "id": "l1",
        "answer_key": { "account": "ROU Asset", "side": "dr", "amount": 10000 },
        "weight": 0.25
    },
    {
        "id": "l2",
        "answer_key": {
            "account": "Lease Liability",
            "side": "cr",
            "amount": 10000
        },
        "weight": 0.25
    },
    {
        "id": "l3",
        "answer_key": {
            "account": "Interest Expense",
            "side": "dr",
            "amount": 500
        },
        "weight": 0.25
    },
    {
        "id": "l4",
        "answer_key": { "account": "Cash", "side": "cr", "amount": 500 },
        "weight": 0.25
    }
]
```

Pinned anchor **numeric** (`seed.rs:791-794`) — scalar `answer_key` + `tolerance`:

```json
[
    { "id": "c1", "answer_key": 250000, "weight": 0.5, "tolerance": 1.0 },
    { "id": "c2", "answer_key": 12500, "weight": 0.5, "tolerance": 1.0 }
]
```

MCQ / confusion items use a single `choice` step (`seed.rs:316`):

```json
[{ "id": "choice", "answer_key": "Operating lease", "weight": 1.0 }]
```

### 1.3 Authoring shape vs graded shape (the `content_tbs_steps` transform)

`seed_content.json`'s `tbs[]` entries author steps in a **flatter** shape than
what is stored; `content_tbs_steps` (`seed.rs:821-852`) transforms them at load:

- **JE authoring** (`seed_content.json:1407-1428`): flat
  `{id, weight, account, side, amount}` → wrapped into
  `{id, answer_key:{account,side,amount}, weight}`.
- **numeric authoring** (`seed_content.json:1378-1392`): flat
  `{id, weight, label, answer_key, tolerance}` → `{id, answer_key, weight, tolerance}`.

**Caveats worth knowing (not blockers):**

1. `content_tbs_steps` **drops `label`** from the stored `steps_json`, yet the
   frontend `parseSteps` reads `label` (`lib.ts:88-90`) and falls back to `id`.
   So content-derived JE/numeric steps currently render with `id` as the label.
   Because the grader ignores unknown keys, the fix (when wanted) is to _keep_
   `label` in the emitted object — no schema change.
2. The authoring struct `TbsItem` (`seed.rs:92-101`) has **no `ds_tag` field**,
   so the `"ds_tag"` present on every `seed_content.json` tbs entry is parsed and
   **ignored**; the seed stamps `schema_tag`/tag from `SETS[set].tags[0]`
   (`seed.rs:371-399`). Set attribution still resolves correctly because
   `ankountant_set_for_tag` matches _either_ of a set's two tags to the same
   `set_id` (`config.rs:65-70`).

### 1.4 How a step becomes Performance (the full pipeline)

1. **Submit** — `SubmitPerformanceAttempt` (`service.rs:24-103`): reads the
   note's `steps_json`, parses submission via `parse_submission`
   (`service.rs:115-137`):
   - `mode == "confusion"` → `{ "choice": <val> }`
   - **any other mode** (`_`, incl. `tbs`) → `{ "steps": [ { "id", "value" } ] }`
2. **Grade** — `grading::grade` → per-step outcomes + `total_credit`.
3. **Resolve set** — `confusion_set_id` from `schema_tag` (field 4) via the
   CONFUSABLE map, else from the note's tags (`service.rs:44-57`).
4. **Detect sealed** — `ankountant_note_is_sealed`: true iff the note's card is in
   `deck:Ankountant::Sealed::<section>::*` (`service.rs:105-109`). **This is what
   routes an attempt into Performance.**
5. **Persist** — `ankountant_write_attempt` writes one hidden Attempt Log note
   and suspends its card (`attempt_log.rs:69-92`). Fields (`notetypes.rs:22-43`):
   `item_ref, confusion_set_id, mode, confidence, latency_ms, outcome_json, ts,
   section, sealed`.
   - `outcome_json` = `Outcome { credit, steps:[{id,correct,weight}] }`
     (`attempt_log.rs:39-52`). **`latency_ms` is a first-class field** — research
     "time-to-cite" needs no schema change.
6. **Roll up** — `ankountant_get_readiness` (`readiness.rs:62-194`):
   - **Performance = sealed attempts only** (`readiness.rs:79-102`); study-pile
     attempts are skipped.
   - Mode bucketing: **`mode == "tbs"` → partial-credit average**; **everything
     else → pass/fail thresholded at `credit >= 0.5`** (`readiness.rs:86-101`).
   - **Memory = trailing-30d recall reps on the study pile only**
     (`readiness.rs:199-241`); sealed items never contribute to Memory.

### 1.5 `SeedSummary` + `LoadFarSeed` response

`SeedSummary` (`seed.rs:114-126`) and the proto response
(`seed.rs:196-210`) carry: `confusion_sets`, `sealed_items`, `sealed_je_tbs`,
`sealed_numeric_tbs`, `study_recall_cards`, `rote_cards`, `sealed_tbs_note_ids[]`.
There is **no research/doc_review count** — new items simply increment
`sealed_items` (see §4.5), so the response/proto is unchanged and iOS index
re-derivation is not triggered.

**Today's stored-only stubs** (the thing we are replacing) — `seed.rs:412-424`:
one `research` + one `doc_review` note, `exhibits_json="[]"`, `steps_json="[]"`,
placed in `Ankountant::Sealed::FAR::misc`, tagged `ds::cost::capitalize`,
suspended. They prove A9 storage but are unplayable (0 steps → 0 credit).

---

## 2. Proposed schema — **research** items

**Mapping onto existing fields (no new note-type field):**

| Research concept                                         | Where it lives                                                                  |
| -------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `tbs_type`                                               | TBS field 0 = `"research"`                                                      |
| `prompt`                                                 | TBS field 1 (the research question)                                             |
| `exhibits[]`                                             | `exhibits_json` (scenario facts; optional inline copy of the governing passage) |
| accepted `answer_key` (canonical citation)               | `steps_json[0].answer_key` (string)                                             |
| `accepted_citations[]` (normalization variants)          | `steps_json[0].accepted_citations` (ignored by grader; read by client + T4)     |
| `corpus_refs[]` (which bundled passages hold the answer) | `steps_json[0].corpus_refs` (ids into the bundled corpus, §4.3)                 |
| time-to-cite                                             | Attempt Log `latency_ms` field (already exists)                                 |
| topic attribution                                        | `schema_tag` (field 4) = a `ds::` tag → set_id                                  |

**Full example (authoring shape in `seed_content.json`; one citation step):**

```json
{
    "kind": "research",
    "set_id": "operating_vs_finance_lease",
    "prompt": "Kestrel Co. needs to know at what date it first recognizes the right-of-use asset and lease liability for a new equipment lease. Find and cite the paragraph that establishes recognition at the commencement date.",
    "exhibits": [
        {
            "title": "Scenario",
            "body": "Kestrel Co. signs a 5-year equipment lease commencing January 1, Year 1, with payments due each December 31."
        }
    ],
    "steps": [
        {
            "id": "cite",
            "weight": 1.0,
            "label": "Governing citation",
            "answer_key": "ASC 842-20-25-1",
            "accepted_citations": [
                "ASC 842-20-25-1",
                "842-20-25-1",
                "ASC 842-20-25-01"
            ],
            "corpus_refs": ["asc-842-20-25-1"]
        }
    ],
    "source": "ASC 842-20-25-1 (commencement-date recognition), grounded in an OpenStax Financial Accounting lease passage (Tier-A)"
}
```

**Stored `steps_json` (what the loader writes) is the same array** — for
research/doc_review the authoring shape already carries `answer_key`, so the
loader passes steps through verbatim (contrast JE/numeric which need wrapping).

**How it grades today (zero code change):**

- Submission `mode="research"` → `{ "steps": [ { "id": "cite", "value": "asc 842-20-25-1" } ] }`
  (routes through the `_` arm of `parse_submission`).
- `step_matches` → scalar string → `scalar_matches` → numeric parse fails →
  `text_matches` = trim + lowercase compare (`logic.rs:222-228`). So the
  **canonical** citation grades correct today.
- Performance: `mode="research"` hits the `_` bucket → **pass/fail at 0.5**,
  which is exactly the intended correctness-only (1/0) semantics for research
  (`readiness.rs:93-100`). Coverage/topic attribution work via `schema_tag`.

**What needs the T4 grading arm (future, out of scope here):** matching
`accepted_citations[]` **variants** server-side. Two honest options:

1. **Client-normalizes** the typed citation to canonical form before submit →
   the existing single-`answer_key` text match suffices (no Rust change). The
   variants list documents the accepted forms.
2. **T4 grader arm** reads `accepted_citations[]` and matches any variant (PRD
   T1 AC1). Preferred long-term; but it is a grading-branch change, not a
   data-shape change.
   Time-to-cite already lands in `latency_ms` (PRD T1 AC2 satisfied by the
   existing field).

---

## 3. Proposed schema — **doc_review** items

**Mapping onto existing fields:**

| Doc-review concept                                                    | Where it lives                                                                                                                |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `tbs_type`                                                            | TBS field 0 = `"doc_review"`                                                                                                  |
| `exhibits[]`                                                          | `exhibits_json` (the exhibits pane)                                                                                           |
| document body with N inline blank markers                             | an `exhibits_json` entry titled `"Document — …"` whose body contains `[[b1]] … [[b2]]` markers referencing step ids           |
| per-blank `{id, options[], correct_option, confusion_set_id, weight}` | one `steps_json` step per blank: `id`, `answer_key`=correct_option, `weight`, plus extra keys `options[]`, `confusion_set_id` |
| per-blank result                                                      | Attempt Log `outcome_json.steps[]` (`{id,correct,weight}`)                                                                    |

**Full example (3 blanks, all in one confusion set):**

```json
{
    "kind": "doc_review",
    "set_id": "capitalize_vs_expense",
    "prompt": "Review the acquisition memo. For each highlighted item, select whether it is capitalized into the asset or expensed as a period cost.",
    "exhibits": [
        {
            "title": "Exhibit 1 — Invoice detail",
            "body": "Packaging machine invoice $200,000; freight-in $5,000; pre-production test runs $2,000; first-year insurance $3,000; operator training $1,500."
        },
        {
            "title": "Document — Capitalization memo",
            "body": "Freight-in incurred to bring the machine to its location is [[b1]]. The first-year insurance premium is [[b2]]. Pre-production test-run costs incurred before normal operation are [[b3]]."
        }
    ],
    "steps": [
        {
            "id": "b1",
            "weight": 0.34,
            "label": "Freight-in",
            "answer_key": "Capitalize",
            "options": ["Capitalize", "Expense"],
            "confusion_set_id": "capitalize_vs_expense"
        },
        {
            "id": "b2",
            "weight": 0.33,
            "label": "First-year insurance",
            "answer_key": "Expense",
            "options": ["Capitalize", "Expense"],
            "confusion_set_id": "capitalize_vs_expense"
        },
        {
            "id": "b3",
            "weight": 0.33,
            "label": "Test-run costs",
            "answer_key": "Capitalize",
            "options": ["Capitalize", "Expense"],
            "confusion_set_id": "capitalize_vs_expense"
        }
    ],
    "source": "ASC 360-10-30-1 (capitalizable cost of equipment), grounded in an OpenStax PP&E passage (Tier-A)"
}
```

**Conventions:**

- **Blank marker** `[[<stepId>]]` inside the `"Document — …"` exhibit body ties a
  position in the prose to a `steps_json` step. (Any delimiter works; `[[id]]` is
  a proposal — the important part is that it lives in `exhibits_json`, no new
  field.)
- **`options[]`** is stored per blank so a blank can use a subset of the set's
  treatments. If omitted, the client can fall back to the set's `treatments` from
  the CONFUSABLE map (`config.rs:44-49`) — options are effectively denormalized
  convenience, label-stripped per SPOV 4 (PRD T3 AC2).

**How it grades today:**

- Submission `mode="doc_review"` → `{ "steps": [ {"id":"b1","value":"Capitalize"}, {"id":"b2","value":"Expense"}, {"id":"b3","value":"Capitalize"} ] }`
  (the `_` arm). `grade()` does per-blank text match → `total_credit` = fraction
  correct; per-blank `{id,correct,weight}` land in `outcome_json` (PRD T3 AC3
  grading math is already there). Weights sum to 1.0.

**Two constraints to respect in the seed (so no code change is needed):**

1. **Partial credit into Performance.** The rollup only treats `mode=="tbs"` as
   partial credit; `doc_review` currently falls into the pass/fail bucket
   (`readiness.rs:86-101`). To get **true per-blank partial credit** into
   Performance with zero code, **the seeded doc_review attempts can be logged
   with `mode="tbs"`** (grading is identical; only the rollup bucket differs).
   The cleaner long-term fix is the T4 arm: `"tbs" | "doc_review" => partial`.
2. **One confusion set per item.** The Attempt Log stores a single note-level
   `confusion_set_id` (resolved from `schema_tag`). Keep all blanks of a seeded
   item in **one** set so topic attribution is exact. Per-blank
   `confusion_set_id` is still recorded in `steps_json` for a future
   multi-set-attribution T4 (which would fan per-blank results out by set).

---

## 4. The seed-pack plan (~6–10 real items), sync-safe

### 4.1 Where it plugs into `seed.rs`

Replace the **stored-only stub loop** (`seed.rs:412-424`) with a real
content-driven loop modeled on the existing **section 3** worked-TBS loop
(`seed.rs:369-410`). Concretely:

1. Extend the embedded content struct `SeedContent` (`seed.rs:67-72`) with two
   new arrays: `research: Vec<TbsItem>` and `doc_review: Vec<TbsItem>` (both
   `#[serde(default)]` so older JSON still parses). `TbsItem` already holds
   `kind, prompt, set_id, exhibits, steps, source` — it needs **no change** for
   these shapes.
2. Add a `content_research_doc_steps(t)` sibling to `content_tbs_steps`
   (`seed.rs:821-852`) that **passes the authored steps through** (they are
   already in graded shape: `id`, `answer_key`, `weight`, optional `tolerance`,
   plus ignored extras). Effectively `Value::Array(t.steps.clone())`.
3. For each item: create/get deck `Ankountant::Sealed::FAR::<set_id>`, new TBS
   note, set fields `tbs_type=<kind>`, `prompt`, `exhibits_json =
   to_string(exhibits)`, `steps_json = passthrough steps`, `schema_tag =
   SETS[set].tags[0]`, provenance fields (`source_passage`, `gen_method`,
   `checker_status="pass"`) exactly like section 3, tag with the `ds::` tag,
   `add_note_inner`, then **`suspend_note_cards`** (§5). Increment `sealed_items`.

All of this is authored offline in `seed_content.json` (+ the corpus file in
§4.3) — the same "author + independent verify" provenance the module docstring
describes (`seed.rs:4-16`, `GEN_METHOD_SEED`).

### 4.2 Proposed item list (8 items: 4 research + 4 doc-review)

One of each per confusion set keeps Performance coverage balanced across all
four `SETS` (`seed.rs:135-159`).

| # | Shape      | set_id                       | Prompt gist                                                                          | Answer key / blanks                        |
| - | ---------- | ---------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------ |
| 1 | research   | `operating_vs_finance_lease` | When is the ROU asset/lease liability first recognized?                              | `ASC 842-20-25-1`                          |
| 2 | research   | `revrec_step_selection`      | Which paragraph governs allocating the transaction price to performance obligations? | `ASC 606-10-32-31`                         |
| 3 | research   | `capitalize_vs_expense`      | Which paragraph defines the capitalizable cost of equipment?                         | `ASC 360-10-30-1`                          |
| 4 | research   | `trading_afs_htm`            | Where are trading securities measured at FV through net income?                      | `ASC 320-10-35-1`                          |
| 5 | doc_review | `capitalize_vs_expense`      | Acquisition memo: capitalize vs expense (freight, insurance, test runs)              | b1 Capitalize / b2 Expense / b3 Capitalize |
| 6 | doc_review | `operating_vs_finance_lease` | Lease classification memo: operating vs finance across 3 clauses                     | 3 blanks over the two treatments           |
| 7 | doc_review | `revrec_step_selection`      | Contract memo: is each action Step 4 (allocate) or Step 5 (recognize)?               | 3 blanks                                   |
| 8 | doc_review | `trading_afs_htm`            | Portfolio footnote: trading vs HTM classification for 3 holdings                     | 3 blanks                                   |

(Trim to 6 or extend to 10 by dropping/adding a set's pair; all citations must
exist in the corpus per PRD T2 AC3.)

### 4.3 How the literature corpus ships (recommended: embedded data file)

The research surface needs a **searchable, offline, scoped** corpus (PRD T2).
Three candidates, judged against sync-safety and licensing:

| Option                                                                                                       | Sync cost                                                           | Verdict                                                        |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------- | -------------------------------------------------------------- |
| **A. Embedded data file** `seed_literature.json` via `include_str!` (like `SEED_CONTENT_JSON`, `seed.rs:45`) | **Zero** — compiled into the binary; never stored in the collection | **Recommended**                                                |
| B. `col` config key `ankountant.literature.<section>` (config.rs pattern)                                    | Non-zero — config **is** synced; a corpus bloats every sync payload | Technically sync-safe (no schema change) but wasteful; avoid   |
| C. No shared corpus — inline each passage as an item exhibit                                                 | Zero extra file                                                     | Fine as a fallback, but no cross-item search pane (defeats T2) |

**Recommendation: Option A.** Ship `rslib/src/ankountant/seed_literature.json`,
embedded at build time, keyed by citation id. Research items reference passages
by `corpus_refs[]`; the (client-side) search pane does substring match over
`citation + title + body` (PRD T2 AC1), fully offline (T2 AC2). Because it is
compiled in, it is **strictly more** sync-safe than anything in the collection.

**Corpus shape:**

```json
{
    "FAR": [
        {
            "id": "asc-842-20-25-1",
            "citation": "ASC 842-20-25-1",
            "title": "Lease commencement — initial recognition",
            "body": "At the commencement date, a lessee recognizes a right-of-use asset and a lease liability measured at the present value of the lease payments. (Paraphrase of an OpenStax Financial Accounting lease passage; points to ASC 842-20-25-1.)",
            "tags": ["lease", "recognition", "commencement"]
        },
        {
            "id": "asc-606-10-32-31",
            "citation": "ASC 606-10-32-31",
            "title": "Allocating the transaction price to performance obligations",
            "body": "The transaction price is allocated to each performance obligation in proportion to its standalone selling price. (Paraphrase of an OpenStax revenue-recognition passage; points to ASC 606-10-32-31.)",
            "tags": ["revenue", "allocation", "SSP"]
        }
    ]
}
```

**Licensing guardrail (from `rag/01-sources-and-licensing.md`):** FASB ASC is
**Tier-B cite-only**. Corpus `body` text must be a **Tier-A paraphrase**
(OpenStax etc.) that _points to_ the ASC number — never verbatim FASB prose. The
`citation` field is the cite; the `body` is the openly-licensed explanation.
Mark each body as a paraphrase (as above) and keep `source` on the item pointing
to the Tier-A origin. This is PRD **R1/OQ-1**.

### 4.4 A test hook to keep the corpus honest

PRD T2 AC3 ("every seed research item's accepted citation exists in the
corpus") maps to a cheap Rust unit test: load `seed_literature.json`, collect the
`corpus_refs`/`answer_key` of each `research` item, assert each id/citation is
present. Mirrors the existing `seed_content_parses` assertion pattern
(`seed.rs:44`).

### 4.5 Counts / proto: keep the response unchanged

Research/doc_review notes are sealed TBS notes, so they already increment
`summary.sealed_items` (`seed.rs:408`). **Do not add new proto fields** — the
`LoadFarSeedResponse` stays byte-identical, so the hand-maintained iOS
service/method indices (CLAUDE.md ⚠️) need **no** re-derivation. If a future UI
wants explicit counts, `SeedSummary` is an internal struct (free to extend); only
_surfacing_ them on the proto response would be an append-only field (FR-6) — a
separate, opt-in decision.

### 4.6 Idempotency is already handled

`wipe_prior_far_seed` (`seed.rs:490-514`) deletes **all** notes of the TBS note
type before re-seeding, so the new research/doc_review notes are wiped + replaced
on every re-seed just like the rest. The embedded `seed_literature.json` is not
in the collection, so it is never wiped and never duplicated.

---

## 5. How these items feed Performance, not the study schedule

A seeded item lands in the **sealed performance bank** (Performance) rather than
the **study pile** (schedule) via three coordinated moves — all already used by
the existing sealed MCQ/TBS bank:

1. **Deck placement = the sealed firewall.** Create the note under
   `Ankountant::Sealed::FAR::<set_id>` (or `::misc`). `ankountant_note_is_sealed`
   keys **only** on this deck prefix (`service.rs:105-109`); the readiness rollup
   counts an attempt toward Performance **iff `sealed`**
   (`readiness.rs:79-83`). The confusion queue likewise gathers candidate items
   by `deck:Ankountant::Sealed::<section>::*` (`confusion.rs:106-108`).
2. **Suspend the card = out of the scheduler.** Call `suspend_note_cards`
   (`seed.rs:810-815`) immediately after `add_note_inner` (as sections 2/2b/3
   do). Suspended cards are never queued (A7 firewall), and Memory is measured
   only over `deck:Ankountant::Study::<section>::*` recall revlog
   (`readiness.rs:213`), so a sealed item can **never** leak into Memory or the
   study queue.
3. **`ds::` tag + `schema_tag` = topic attribution.** Set `schema_tag` (field 4)
   and a note tag to a `ds::` tag belonging to the target set. At submit time,
   `confusion_set_id` resolves from `schema_tag` via the CONFUSABLE map
   (`service.rs:44-57`, `config.rs:65-70`), so the attempt is credited to the
   right topic's Performance and to overall coverage
   (`readiness.rs:142-151`).

**Net effect:** a research/doc_review attempt is graded (`service.rs`), written
as a sealed Attempt Log note (`attempt_log.rs`), and rolled into **Performance**

- the abstain-aware readiness band (`readiness.rs`) — while being invisible to
  FSRS study. Memory stays driven by the real recall pile only, preserving the
  memory-minus-performance **gap** signal.

**Optional demo history.** To make the seeded items show evidence in a
`with_history` profile, `seed_performance_history` (`seed.rs:712-757`) can be
extended to emit a few `mode="research"` (correctness) and `mode="tbs"` (or
`doc_review`) attempts against the new note ids, exactly as it does for the MCQ
bank today.

---

## 6. Risks / open items (all deferrable; none block the seed shape)

- **Citation variant matching** — canonical grades today; `accepted_citations[]`
  variants need client-side normalization now, or the T4 grader arm later
  (PRD T1 AC1 / OQ-2).
- **doc_review partial credit in the rollup** — seed attempts as `mode="tbs"` for
  true partial credit now, or add `doc_review` to the partial-credit arm in
  `readiness.rs:86-101` (T4).
- **Per-blank multi-set attribution** — one set per item for now (note-level
  `confusion_set_id`); per-blank `confusion_set_id` is pre-stored for a future
  T4 fan-out.
- **Frontend rendering** — the doc-review surface must read `options[]` and the
  `[[id]]` markers; the research surface needs the search pane over the corpus.
  Both are **client-only** additions (`lib.ts` `RenderStep`/`parseSteps` extend to
  carry `options`; no data-shape change).
- **`label` dropped by `content_tbs_steps`** — pre-existing; keep `label` in the
  emitted step for nicer rendering (grader ignores it).
- **Licensing** — corpus bodies must be Tier-A paraphrase citing Tier-B ASC
  numbers; never verbatim FASB text (R1/OQ-1).

---

## 7. Bottom line

Everything needed to seed real research + doc-review items is expressible in the
**existing** `exhibits_json` + `steps_json` TEXT fields because the grader
ignores unknown JSON keys. Author the items in `seed_content.json` (new
`research[]` / `doc_review[]` arrays), ship the searchable literature as a
build-embedded `seed_literature.json` (zero sync bytes), place each note in
`Ankountant::Sealed::FAR::<set_id>`, suspend it, and tag it with a `ds::` tag.
No new SQLite tables/columns, no new note-type fields, and (by folding counts
into `sealed_items`) no proto change and no iOS re-derivation.
