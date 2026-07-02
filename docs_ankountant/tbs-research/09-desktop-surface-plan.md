# 09 — Desktop Build Plan: Research + Document-Review TBS Surfaces

> Status: Plan (read-only analysis) · Owner: eric · Scope: **desktop Svelte web only**
> Depends on: `docs_ankountant/PRD-tbs-shapes-future.md` (T1–T4). This doc turns
> that PRD into a concrete, file-level desktop build plan grounded in the code as
> it exists today.
>
> This is an analysis artifact. **No code was changed** to produce it. Every
> "today" claim below has a file/line reference; every "proposed" block is new
> code to be written during the build.

---

## 0. TL;DR — what already exists, what to build

**Already true today (no work needed):**

- The `Ankountant TBS` note type already carries all four shapes structurally;
  `tbs_type` legally holds `"research"` and `"doc_review"` — see `tbs_fields`
  (`rslib/src/ankountant/notetypes.rs:47`) and the TS `TbsShape` union
  (`ts/routes/(ankountant)/ankountant-tbs/lib.ts:18`).
- The FAR seed **already inserts one stored-only `research` note and one
  `doc_review` note** (currently empty steps/exhibits) —
  `rslib/src/ankountant/seed.rs:412`.
- `SubmitPerformanceAttempt` grading is **shape-agnostic**: any `mode` other than
  `"confusion"` is parsed through the generic `steps` path
  (`rslib/src/ankountant/service.rs:115`) and graded per-step against the note's
  `steps_json` answer keys (`rslib/src/ankountant/grading.rs:53`). A text answer
  key is matched case/space-insensitively (`rslib/src/ankountant/logic.rs:214`).
- No proto change is required (both shapes reuse `SubmitPerformanceAttempt` with
  new `mode` strings), so the hand-maintained iOS dispatch table is **unaffected**.

**What we build (desktop):**

1. `ResearchSurface.svelte` — prompt + client-side searchable literature pane over
   a bundled corpus + citation input + submit + correct/incorrect + time display.
2. `DocReviewSurface.svelte` — exhibits pane + a document with inline dropdown
   blanks, each blank reusing the confusion "which treatment?" choice, submit →
   per-blank results + partial-credit total.
3. Two self-loading workspace panes (`ResearchPane.svelte`, `DocReviewPane.svelte`)
   - registration in the surface registry, layout union, shell tabs, routes,
     mediasrv allowlist, webview kinds, and Qt route map.
4. A small render-model extension in `ankountant-tbs/lib.ts` (per-blank `options`,
   a `document` template, a citation-submission builder). Answer keys stay
   server-side.

**Backend dependencies (small, localized — flagged in §6):** research needs a
grading tweak to accept a _list_ of accepted citations; doc-review needs a
readiness-weighting decision. Both are optional depending on how "test-accurate"
we want Performance to blend; neither touches the proto contract.

---

## 1. How `TbsSurface.svelte` renders + submits today

File: `ts/routes/(ankountant)/ankountant-tbs/TbsSurface.svelte`.
Model/helpers: `ts/routes/(ankountant)/ankountant-tbs/lib.ts`.
Loaders: `ankountant-tbs/+page.ts` (route) and `panes/TbsPane.svelte` (workspace).

### 1a. The render model (answer keys never reach the client)

`buildTbsModel(fields)` parses the raw note fields into a `TbsModel` of
`{ shape, prompt, exhibits[], steps[] }`. Crucially, `parseSteps` strips
everything except `id/label/weight` — the `answer_key` stays server-side:

```81:107:ts/routes/(ankountant)/ankountant-tbs/lib.ts
export function parseSteps(raw: string | undefined): RenderStep[] {
    const parsed = safeParse<RawStep[]>(raw, []);
    if (!Array.isArray(parsed) || parsed.length === 0) {
        return [];
    }
    const defaultWeight = 1 / parsed.length;
    return parsed.map((s, i) => {
        const id = typeof s.id === "string" ? s.id : `s${i + 1}`;
        const label = typeof s.label === "string" ? s.label : id;
        const weight = typeof s.weight === "number" ? s.weight : defaultWeight;
        return { id, label, weight };
    });
}
```

### 1b. Layout: task card (left) + sticky exhibits (right)

The surface is a two-column flex: a `.task .card` on the left and a sticky
`aside.exhibits` on the right, so exhibits stay co-visible with the active cell:

```200:210:ts/routes/(ankountant)/ankountant-tbs/TbsSurface.svelte
<aside class="exhibits" data-testid="exhibits">
    <h2>Exhibits</h2>
    {#each model.exhibits as exhibit, i (i)}
        <div class="exhibit card" data-testid="exhibit">
            <h3>{exhibit.title}</h3>
            <pre>{exhibit.body}</pre>
        </div>
    {/each}
</aside>
```

- **JE grid** (`data-shape="journal_entry"`): a `<table class="grid je-grid">`
  with, per step, a text `account` input, a `<select>` Debit/Credit, a decimal
  `amount` input, and a result `✓/✗` cell (`TbsSurface.svelte:116`).
- **Numeric grid** (`data-shape="numeric"`): a `<table class="grid numeric-grid">`
  with one decimal `value` input per cell + result cell (`TbsSurface.svelte:70`).
- Inputs bind into parallel arrays `jeLines[]` / `numericCells[]` seeded from
  `model.steps` (`TbsSurface.svelte:17`).
- Results are keyed by step id via `resultById` and shown as a color+icon+aria
  mark (color-never-alone) (`TbsSurface.svelte:32`, `:97`).

### 1c. Submit → `submitPerformanceAttempt` (the exact request/response shape)

```34:56:ts/routes/(ankountant)/ankountant-tbs/TbsSurface.svelte
async function submit(): Promise<void> {
    submitting = true;
    try {
        const submissionJson =
            model.shape === "numeric"
                ? buildNumericSubmission(numericCells)
                : buildJeSubmission(jeLines);
        const resp = await submitPerformanceAttempt({
            itemNoteId: noteId,
            mode: "tbs",
            submissionJson,
            confidence: "Unsure",
            latencyMs: Date.now() - startedAt,
        });
        results = resp.steps;
        total = resp.totalCredit;
    } finally {
        submitting = false;
    }
}
```

- Generated fn: `submitPerformanceAttempt` from `@generated/backend`
  (`TbsSurface.svelte:7`), which POSTs the protobuf `SubmitPerformanceAttemptRequest`.
- Request fields (`proto/anki/scheduler.proto:587`): `item_note_id`, `mode`
  (`"confusion" | "tbs"` per the comment), `submission_json`, `confidence`,
  `latency_ms`.
- Submission JSON shapes (`lib.ts:118`, `:138`):
  - JE: `{"steps":[{"id":"l1","value":{"account","side","amount"}}, …]}`
  - numeric: `{"steps":[{"id":"c1","value":<number|"">}, …]}`
- Response (`scheduler.proto:596`): `repeated StepResult steps` (`{id,correct,weight}`),
  `double total_credit`, `int64 attempt_note_id`. The surface shows
  `Math.round(total*100)%` as "Partial credit" (`TbsSurface.svelte:192`).
- **Standalone TBS defaults `confidence:"Unsure"`** (comment at
  `TbsSurface.svelte:45`); the confusion flow instead captures real confidence
  via the gate (see §2). The surface intentionally exposes **no Again/Hard/Good/Easy**
  (comment `TbsSurface.svelte:59`, asserted by `ts/tests/e2e/tbs.test.ts:59`).

### 1d. Data loading

- Route loader `+page.ts` deep-links `?note=<id>` else falls back to the first
  sealed TBS note via `searchNotes` (`ankountant-tbs/+page.ts:13`), then
  `getNote` → `buildTbsModel`.
- Workspace pane `TbsPane.svelte` mirrors that load in `onMount` and wraps state
  transitions in `PaneState.svelte` (loading/empty/error) (`TbsPane.svelte:28`).

**Server side of the grade** (why it's shape-agnostic): `parse_submission`
special-cases only `"confusion"`; everything else takes the `steps` branch, and
`grade` compares each submitted `value` to the step's `answer_key`
(object → per-subfield JE match; scalar → numeric-or-text match):

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

---

## 2. How the confusion "which treatment?" choice UI works (reuse target)

File: `ts/routes/(ankountant)/ankountant-confusion/ConfusionMode.svelte`.
Gate: `ts/lib/components/ConfidenceGate.svelte`. Helper: `ankountant-confusion/lib.ts`.

The pattern to reuse per doc-review blank has three moving parts:

1. **Confidence gate first (B1).** Treatments are hidden until a confidence level
   is committed. `ConfidenceGate` renders three equal-weight buttons
   (Guess/Unsure/Confident), keyboard-selectable `1/2/3`, and calls back on the
   first commit (`ConfidenceGate.svelte:26`, `:34`). The parent gates reveal:

```92:107:ts/routes/(ankountant)/ankountant-confusion/ConfusionMode.svelte
{#if confidence !== null}
    <div class="treatments" data-testid="treatments">
        {#each current.treatments as treatment (treatment)}
            <button
                type="button"
                class="treatment"
                data-testid="treatment"
                data-value={treatment}
                disabled={submitting || lastCorrect !== null}
                on:click={() => choose(treatment)}
            >
                {treatment}
            </button>
        {/each}
    </div>
{/if}
```

2. **Label-stripped choices.** The prompt slug is stripped (`stem()`,
   `ConfusionMode.svelte:31`) and there is **no** category/topic label element
   (comment `:84`; asserted by `ts/tests/e2e/confusion.test.ts:32`). The candidate
   treatments come from the server DTO `ConfusionItem.treatments`
   (`proto/anki/scheduler.proto:537`), which is label-stripped by construction
   (`rslib/src/ankountant/confusion.rs:64`).

3. **Submit one choice.** `buildChoiceSubmission(treatment)` → `{"choice":"…"}`
   (`ankountant-confusion/lib.ts:10`); submitted via `submitPerformanceAttempt`
   with `mode:"confusion"` and the captured `confidence`; correctness is
   `resp.totalCredit >= 1` (`ConfusionMode.svelte:39`).

Server grading of a choice: the confusion note's `steps_json` is a single step
`{"id":"choice","answer_key":<correct treatment>,"weight":1.0}` (seed:
`rslib/src/ankountant/seed.rs:316`), and `{"choice":…}` maps onto step id
`"choice"` (`service.rs:119`).

**Reuse decision for doc-review:** a doc-review _blank_ is exactly a confusion
choice **without** a per-blank confidence gate (one attempt spans the whole
document, not one gate per blank). So we reuse the _treatment-button/dropdown_
choice UI and the label-stripping discipline, but drive selection with a
`<select>` (inline blank) and submit **all** blanks in one `steps` array (§4).

---

## 3. RESEARCH surface — component design

**Goal (PRD T1/T2):** prompt + searchable literature pane over a **bundled,
offline corpus** + citation input + submit → correct/incorrect + **time**.
Training _navigation_, not recall.

### 3a. Files

```
ts/routes/(ankountant)/ankountant-research/
  +page.ts            # loader: ?note=<id> else first sealed research note
  +page.svelte        # thin wrapper -> ResearchSurface (mirrors ankountant-tbs/+page.svelte)
  ResearchSurface.svelte
  corpus.far.json     # bundled scoped ASC excerpt corpus (T2); imported statically
  lib.ts              # searchCorpus() + buildCitationSubmission() + corpus types (DOM-free, unit-tested)
  lib.test.ts
ts/routes/(ankountant)/ankountant-workspace/panes/ResearchPane.svelte
```

Reuse the existing TBS render model: extend `buildTbsModel` so a `research` note
yields `{ shape:"research", prompt, exhibits, steps }` where `steps[0]` is the
single citation step (id `"citation"`, label e.g. "Governing citation"). The
accepted citation(s) stay in the note's `steps_json.answer_key` (server-only).

### 3b. Corpus + client-side search (T2)

Bundle a curated excerpt set keyed by citation. Keep it a plain JSON asset
imported at build time (SvelteKit bundles it; no network — satisfies T2 AC2):

```ts
// corpus.far.json (shape)
[
    {
        "citation": "ASC 842-20-25-1",
        "title": "Lessee — Recognition",
        "body":
            "At the commencement date, a lessee shall recognize a right-of-use asset and a lease liability…",
    },
    {
        "citation": "ASC 360-10-30-1",
        "title": "PP&E — Initial Measurement",
        "body": "…",
    },
];
```

```ts
// lib.ts (pure; unit-tested via just test-ts)
export interface CorpusEntry {
    citation: string;
    title: string;
    body: string;
}

export function searchCorpus(
    entries: CorpusEntry[],
    query: string,
): CorpusEntry[] {
    const q = query.trim().toLowerCase();
    if (!q) { return []; }
    // Substring/keyword over citation + title + body (PRD T2 AC1).
    return entries.filter(
        (e) =>
            e.citation.toLowerCase().includes(q)
            || e.title.toLowerCase().includes(q)
            || e.body.toLowerCase().includes(q),
    );
}

export function buildCitationSubmission(citation: string): string {
    // Reuses the generic tbs steps path: one step, id "citation".
    return JSON.stringify({
        steps: [{ id: "citation", value: citation.trim() }],
    });
}
```

### 3c. `ResearchSurface.svelte` structure

Mirror `TbsSurface`'s two-column shell + tokens (§5), replacing the grid with a
literature pane and a citation submit:

```svelte
<!-- pseudo-structure; real file uses scoped SCSS with Ledger tokens -->
<div class="research-surface" data-testid="research-surface" data-shape="research">
  <header class="research-head">
    <h1>Research</h1>
    <p class="prompt" data-testid="research-prompt">{model.prompt}</p>
  </header>

  <div class="research-body">
    <section class="literature card">              <!-- left: searchable corpus -->
      <label class="search">
        <span class="sr-only">Search literature</span>
        <input type="search" data-testid="lit-search" bind:value={query}
               placeholder="Search the codification…" />
      </label>
      <ul class="results" data-testid="lit-results">
        {#each results as e (e.citation)}
          <li class="result">
            <button type="button" class="cite-pick" data-testid="lit-result"
                    on:click={() => (citation = e.citation)}>
              <span class="cite">{e.citation}</span>
              <span class="title">{e.title}</span>
            </button>
            <p class="body">{e.body}</p>
          </li>
        {/each}
        {#if query && results.length === 0}
          <li class="empty" data-testid="lit-none">No passages match "{query}".</li>
        {/if}
      </ul>
    </section>

    <aside class="submit-pane card">              <!-- right: cite + submit + result -->
      <label class="cite-field">
        <span class="picker-label">Governing citation</span>
        <input type="text" data-testid="citation-input" bind:value={citation}
               placeholder="e.g. ASC 842-20-25-1" />
      </label>
      <button class="submit" data-testid="research-submit"
              disabled={submitting || citation === ""} on:click={submit}>Submit</button>

      {#if result !== null}
        <p class="verdict" data-testid="research-verdict"
           class:correct={result} class:incorrect={!result}>
          <span aria-hidden="true">{result ? "✓" : "✗"}</span>
          {result ? "Correct citation" : "Incorrect citation"}
        </p>
        <p class="time" data-testid="research-time">
          Found in {(elapsedMs / 1000).toFixed(1)}s
        </p>
      {/if}
    </aside>
  </div>
</div>
```

Script logic:

```ts
const startedAt = Date.now();
let query = "", citation = "";
let result: boolean | null = null, elapsedMs = 0, submitting = false;
$: results = searchCorpus(CORPUS, query);

async function submit() {
    submitting = true;
    elapsedMs = Date.now() - startedAt; // time-to-cite (PRD T1)
    try {
        const resp = await submitPerformanceAttempt({
            itemNoteId: noteId,
            mode: "research", // generic steps path grades it
            submissionJson: buildCitationSubmission(citation),
            confidence: "Unsure",
            latencyMs: elapsedMs, // persisted to Attempt Log latency field
        });
        result = resp.totalCredit >= 1; // correctness is 1/0
    } finally {
        submitting = false;
    }
}
```

**Notes / test-accuracy:**

- Time is displayed from the client clock (`Date.now() - startedAt`) and also
  sent as `latencyMs`, which is already persisted (`attempt_fields::LATENCY_MS`,
  `rslib/src/ankountant/attempt_log.rs:78`). No response field carries it back,
  so the surface uses its own measurement — fine for display (PRD T1 AC2 records
  it server-side already).
- Grading today matches a **single** normalized citation
  (`text_matches` lowercases+trims; `numeric_matches` strips `$ , %` but the
  citation is text). To accept **multiple** citation variants (PRD T1 AC1
  "any normalization variant in the key"), see §6.1 — a small, localized grader
  change (list-valued answer key). The surface itself is agnostic to that choice.

---

## 4. DOC-REVIEW surface — component design

**Goal (PRD T3):** exhibits pane + a document with N inline blanks; each blank is
a confusion "which treatment?" choice (label-stripped candidates); submit → per-blank
results + partial-credit total (same math as A10).

### 4a. Files

```
ts/routes/(ankountant)/ankountant-doc-review/
  +page.ts            # loader (mirror ankountant-tbs/+page.ts)
  +page.svelte        # wrapper -> DocReviewSurface
  DocReviewSurface.svelte
ts/routes/(ankountant)/ankountant-workspace/panes/DocReviewPane.svelte
```

### 4b. Render model extension (client-only; keys stay server-side)

Doc-review needs two things the current model drops: a **document template** with
blank placeholders, and per-blank **options** (the candidate treatments — these
are choices, not answers, so they are safe to render). Extend `ankountant-tbs/lib.ts`:

```ts
// New optional fields on RenderStep (only populated for doc_review):
export interface RenderStep {
    id: string;
    label: string;
    weight: number;
    options?: string[]; // candidate treatments for a doc_review blank (safe: not the key)
}

// New model field: the document text with {{blankId}} placeholders.
export interface TbsModel {
    shape: TbsShape;
    prompt: string;
    exhibits: Exhibit[];
    steps: RenderStep[];
    document?: string; // doc_review only; parsed from a new note field or steps meta
}

export function buildDocReviewSubmission(
    blanks: { id: string; value: string }[],
): string {
    return JSON.stringify({
        steps: blanks.map((b) => ({ id: b.id, value: b.value })),
    });
}
```

Where the document text + options come from is an **authoring decision**
(see §6.3). Two viable encodings, both inside the existing note fields (no proto/
notetype change):

- **Option A (recommended):** store the document template in `exhibits_json` as a
  distinguished exhibit (e.g. `{"title":"__document__","body":"…{{b1}}…"}`) or in
  the unused `prompt`/`schema_tag` space; store each blank's `options` inside its
  `steps_json` step object (alongside the server-only `answer_key`). `parseSteps`
  reads `options` and drops `answer_key`.
- **Option B:** add a dedicated document string to `steps_json` as a header
  pseudo-step. Either way the client never sees answer keys.

### 4c. `DocReviewSurface.svelte` structure

Reuse the TBS shell (task card + sticky exhibits, §5). The task card renders the
document with inline dropdown blanks; each dropdown is the confusion choice UI
adapted to a `<select>` (recognition, not free recall), label-stripped:

```svelte
<div class="docreview-surface" data-testid="docreview-surface" data-shape="doc_review">
  <header class="dr-head">
    <h1>Document Review</h1>
    <p class="prompt" data-testid="docreview-prompt">{model.prompt}</p>
  </header>

  <div class="dr-body">
    <article class="document card" data-testid="dr-document">
      <!-- render document text, swapping {{blankId}} for an inline <select> -->
      {#each segments as seg (seg.key)}
        {#if seg.type === "text"}{seg.text}{:else}
          {@const step = stepById.get(seg.blankId)}
          <span class="blank" data-testid="dr-blank" data-blank-id={seg.blankId}>
            <select data-testid="dr-blank-select" data-blank-id={seg.blankId}
                    bind:value={answers[seg.blankId]}>
              <option value="">Select…</option>
              {#each step.options ?? [] as opt (opt)}
                <option value={opt}>{opt}</option>   <!-- label-stripped candidates -->
              {/each}
            </select>
            {#if resultById.has(seg.blankId)}
              {@const ok = resultById.get(seg.blankId)?.correct}
              <span class="step-mark" class:correct={ok} class:incorrect={!ok}
                    role="img" aria-label={ok ? "Correct" : "Incorrect"}>{ok ? "✓" : "✗"}</span>
            {/if}
          </span>
        {/if}
      {/each}

      <div class="actions">
        <button class="submit" data-testid="docreview-submit"
                disabled={submitting} on:click={submit}>Submit</button>
        {#if total !== null}
          <p class="total" data-testid="docreview-total">
            <span class="total-label">Partial credit</span>
            <span class="total-value">{Math.round(total * 100)}%</span>
          </p>
        {/if}
      </div>
    </article>

    <aside class="exhibits" data-testid="exhibits">…same markup as TbsSurface…</aside>
  </div>
</div>
```

Script logic (submit all blanks in one attempt):

```ts
const startedAt = Date.now();
let answers: Record<string, string> = Object.fromEntries(
    model.steps.map((s) => [s.id, ""]),
);
let results: StepResult[] | null = null,
    total: number | null = null,
    submitting = false;
$: resultById = new Map((results ?? []).map((r) => [r.id, r]));

async function submit() {
    submitting = true;
    try {
        const resp = await submitPerformanceAttempt({
            itemNoteId: noteId,
            mode: "doc_review",
            submissionJson: buildDocReviewSubmission(
                model.steps.map((s) => ({ id: s.id, value: answers[s.id] })),
            ),
            confidence: "Unsure",
            latencyMs: Date.now() - startedAt,
        });
        results = resp.steps; // per-blank {id,correct,weight}
        total = resp.totalCredit; // fraction correct == A10 math
    } finally {
        submitting = false;
    }
}
```

**Notes / test-accuracy:**

- Per-blank grading works **today**: each blank is a scalar step; `grade` matches
  the submitted string to the step's text `answer_key` via `text_matches`
  (`grading.rs:93` → `logic.rs:222`), and `total_credit = Σ(weight×correct)`
  (`grading.rs:53`). This gives PRD T3 AC3 with zero grader change.
- The candidate `options` are the confusion set's treatments; keep them
  label-stripped (no set/category name), matching the confusion discipline
  (`ConfusionMode.svelte:84`) and PRD T3 AC2.
- One Attempt Log note per whole item (the single `submitPerformanceAttempt`
  call writes exactly one attempt — `service.rs:88`), satisfying T3 requirement of
  "one note for the whole item with per-blank results in `outcome_json`"
  (`OutcomeStep[]` is persisted — `attempt_log.rs:47`).

---

## 5. Design tokens/classes + how each surface registers

### 5a. Tokens/classes to reuse (match the Ledger system)

Source of truth: `docs_ankountant/design-tokens.json`; emitted CSS vars live in
`ts/lib/sass/_vars.scss`. Copy the exact patterns already used by `TbsSurface`,
`ConfusionMode`, and `Pane`:

| Purpose                     | Token(s)                                                                                                                                        | Precedent                                                          |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Card container              | `--canvas-elevated`, `1px solid var(--border-subtle)`, `--border-radius-medium`, `box-shadow: var(--elevation-e1)`                              | `TbsSurface.svelte:259` (`.card`)                                  |
| Inputs / selects            | bg `--canvas-inset`, border `--border-control` (clears 3:1), radius `--border-radius`, focus `outline: 2px solid var(--accent); outline-offset` | `TbsSurface.svelte:349`; `AddPane.svelte:212`                      |
| Numeric/mono cells          | `--font-mono` + `font-variant-numeric: tabular-nums lining-nums`, right-aligned                                                                 | `TbsSurface.svelte:382`                                            |
| Primary submit              | `--button-primary-bg` / `--button-primary-hover-bg`, white text                                                                                 | `TbsSurface.svelte:410` (`.submit`)                                |
| Choice rows/blanks          | `--canvas-inset` + `--border-control`, hover `--accent` + `--accent-tint`, `min-height:44px`                                                    | `ConfusionMode.svelte:192` (`.treatment`)                          |
| Verdict (correct/incorrect) | `--fg-success` / `--fg-error` + icon + text label (color-never-alone), tinted bg                                                                | `ConfusionMode.svelte:243`; `TbsSurface.svelte:390` (`.step-mark`) |
| Headings / prompt           | `--type-section-heading-*`, `--type-card-title-*`, `--fg-subtle`                                                                                | `TbsSurface.svelte:237`; `ConfusionMode.svelte:170`                |
| Spacing                     | 4-pt scale `--space-xs … --space-xxl`                                                                                                           | everywhere                                                         |
| Section labels (uppercase)  | `12px/600/0.04em uppercase` + `--fg-subtle`                                                                                                     | `.exhibits h2` `TbsSurface.svelte:281`                             |
| `.sr-only` visually-hidden  | copy the block from `TbsSurface.svelte:214`                                                                                                     | —                                                                  |

Hard constraints to honor (from `design-tokens.json:188` `constraints`):

- `retrievalIntegrity`: answer keys stay server-side (already true — `parseSteps`
  drops `answer_key`); no peek affordance in the DOM.
- `colorNeverAlone`: every verdict pairs color with icon **and** text label.
- `targetSize` web `24px+`; choice/blank controls use `min-height:44px` like the
  confusion treatments.
- Focus ring is always `2px --accent` + offset, never a glow.

### 5b. Registering as a **workspace pane** (BSP tiling)

Four edits + one new pane component per surface (mirror `TbsPane`/`ConfusionPane`):

1. `ts/routes/(ankountant)/ankountant-workspace/layout.ts:13` — add `"research"`
   and `"doc_review"` to the `SurfaceKind` union.
2. `layout.ts:52` — add both to `SURFACE_KINDS` (order = switcher order); this also
   feeds `KNOWN_SURFACES`/`sanitize` so persisted layouts validate
   (`layout.ts:61`, `:217`).
3. `ts/routes/(ankountant)/ankountant-workspace/surfaces.ts:31` — add registry
   entries `{ kind, label, glyph, component }`, e.g.:

```ts
research: { kind: "research", label: "Research", glyph: "🔎", component: ResearchPane },
doc_review: { kind: "doc_review", label: "Doc Review", glyph: "📄", component: DocReviewPane },
```

(Prefer a monochrome text glyph consistent with the existing set `◑ ⇄ ▤ ▦ ＋ ☰`,
e.g. `⌕` for research and `▤`-adjacent for doc-review, to avoid emoji.)

4. New `panes/ResearchPane.svelte` + `panes/DocReviewPane.svelte` — self-loading
   wrappers exactly like `panes/TbsPane.svelte` (`searchNotes` for the first sealed
   note of the shape, `getNote`, `buildTbsModel`, wrap in `PaneState`). The pane
   search must filter by `tbs_type`; since `searchNotes` is field-based, either add
   a shape tag at seed time or filter client-side after `getNote`. **Recommend**
   seeding a `shape::research` / `shape::doc_review` tag (seed change, §7) so the
   pane query is `"note:Ankountant TBS" tag:shape::research deck:Ankountant::Sealed::FAR::*`.

`Pane.svelte` renders `<svelte:component this={def.component} />` (`Pane.svelte:116`)
and the switcher iterates `SURFACE_KINDS` (`Pane.svelte:43`), so no other pane
wiring is needed. `Workspace.svelte` "+ Add pane" uses the same registry
(`Workspace.svelte:124`).

### 5c. Registering as a **shell route + tab** (parity with TBS/Confusion)

The single-window shell lives in `ts/routes/(ankountant)/+layout.svelte`. To make
research/doc-review first-class destinations like TBS:

1. Add tabs in `+layout.svelte:21` (`{ id, label, href }`) → `/ankountant-research`,
   `/ankountant-doc-review`. (Optional if we only want them as workspace panes,
   but the PRD frames them as full surfaces, so add the tabs.)
2. Create the routes (`+page.ts`, `+page.svelte`) under `(ankountant)/` (§3a, §4a).
   SvelteKit static-adapter auto-discovers them; SSR/prerender are off.
3. **mediasrv allowlist** — add both page names to `is_sveltekit_page()`
   (`qt/aqt/mediasrv.py:415`), else the webview 404s.
4. **Qt route map** — add to `_ANKOUNTANT_ROUTES` (`qt/aqt/workspace.py:57`) so
   `open_ankountant("research")` / bridge `ankountant:nav:research` resolve.
5. **Webview kind + API access** (only if a dedicated menu **dialog** is wanted,
   à la `AnkountantTbsDialog`): add `ANKOUNTANT_RESEARCH` / `ANKOUNTANT_DOC_REVIEW`
   to `AnkiWebViewKind` (`qt/aqt/webview.py:62`) and the API-allow list
   (`webview.py:149`), plus dialog classes in `qt/aqt/ankountant.py:60`. If we only
   surface them **inside the shell** (tab/workspace, like Stats), no new kind is
   needed — Stats has a route but no dialog/kind (see `test_ankountant_wiring.py:19`).
6. **Wiring test** — extend `qt/tests/test_ankountant_wiring.py:15` with the two new
   page names (and kinds, if added).

> The `+layout.svelte` header comment notes the route group shares the top bar
> "without changing their flat URLs … so mediasrv's first-segment whitelist needs
> no change" — that refers to the _group folder_, not new pages. New page names
> **do** need the `is_sveltekit_page` entry (the first path segment is
> `ankountant-research`).

---

## 6. Backend / grading dependencies (precise; no proto change)

Both shapes reuse `SubmitPerformanceAttempt`; no `.proto` edit, so iOS dispatch is
untouched. But three server behaviors decide how "test-accurate" the result is:

### 6.1 Research — multiple accepted citations (grader tweak)

Today a scalar `answer_key` is a single value; `scalar_matches` does
`numeric_matches || text_matches` (`grading.rs:93`). To accept a **list** of
citation variants (PRD T1 AC1), extend `step_matches` to handle an **array**
answer key (match if any element matches):

```rust
// rslib/src/ankountant/grading.rs — in step_matches, add before the scalar arm:
(Value::Array(keys), sub) => keys.iter().any(|k| scalar_matches(k, sub, tolerance)),
```

- Localized, sync-safe (no schema change), unit-testable via `test-rust`.
- Alternative with **zero** backend change: author one canonical citation and rely
  on `text_matches` normalization (trim + lowercase). Acceptable for a demo but
  fails variants like `842-20-25-1` vs `ASC 842-20-25-1`. **Recommend the array
  tweak** for test-accuracy.

### 6.2 Doc-review + research — Performance weighting in readiness

`readiness.rs` buckets sealed attempts by mode: `"tbs"` → TBS partial-credit
bucket; **everything else** → MCQ pass/fail on `credit>=0.5`:

```86:101:rslib/src/ankountant/readiness.rs
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

- With `mode:"research"` / `mode:"doc_review"`, both currently land in the **MCQ
  pass/fail** bucket. For **research** (credit is 1/0) that is already correct.
  For **doc-review** (partial credit) it collapses partial credit to pass/fail —
  it still _feeds_ Performance (PRD T3 AC4) but loses nuance.
- **Two clean options:**
  1. Submit doc-review with `mode:"tbs"` (blends into the 50/50 partial-credit
     bucket exactly like JE/numeric) — **zero backend change**; the note's
     `tbs_type="doc_review"` still drives rendering. Downside: the Attempt Log
     `mode` no longer distinguishes doc-review for analytics.
  2. Keep `mode:"doc_review"` for analytics and widen the partial-credit arm to
     `"tbs" | "doc_review"` (one-line match change). **Recommended** for accurate
     partial-credit + clean analytics.
- Either way, `confusion.rs:85` filters `mode=="confusion"` for set-accuracy
  ordering, so research/doc-review never perturb the confusion queue.

### 6.3 Authoring the seed items (make the stored-only notes playable)

`seed.rs:412` currently writes empty research/doc_review notes. To be test-accurate
they need real content:

- **Research:** `steps_json = [{"id":"citation","answer_key":["ASC 842-20-25-1", …],
  "weight":1.0}]`; a prompt; optional exhibits; and every accepted citation must
  exist in `corpus.far.json` (PRD T2 AC3). Add a `shape::research` tag for the pane
  query (§5b).
- **Doc-review:** `steps_json = [{"id":"b1","answer_key":"Capitalize",
  "options":["Capitalize","Expense"],"weight":…}, …]` (2–4 blanks); a `document`
  template with `{{b1}}` placeholders (encoded per §4b Option A); exhibits;
  `shape::doc_review` tag. Options/document are safe to store (not the key).
- Extend `LoadFarSeedResponse` counters? Not required — the e2e can deep-link by
  searching. But adding `sealed_research`/`sealed_doc_review` counts (append-only
  fields at the tail of the message) would let fixtures assert counts. That _is_ a
  proto change (append-only, safe) and would require the iOS index note only if it
  reorders services/methods (it does not — message field add is index-neutral).

---

## 7. Testing plan (test-accurate)

Harness: `ts/tests/e2e/` Playwright specs + `fixtures.ts` auto-loads the FAR seed
(`request.post("/_anki/loadFarSeed")`) and exposes `seed`. Add:

- `ts/tests/e2e/research.test.ts`
  - search returns matching passages with citations (T2 AC1);
  - typing/selecting a correct citation → `research-verdict` correct; wrong → incorrect (T1 AC1);
  - `research-time` visible after submit (T1 AC2 display);
  - no Again/Hard/Good/Easy buttons (parity with `tbs.test.ts:59`).
- `ts/tests/e2e/doc-review.test.ts`
  - renders exhibits + a document with N `dr-blank` selects (T3 AC1);
  - each blank offers the set's candidate treatments; **no** `category-label`
    element (T3 AC2, mirror `confusion.test.ts:32`);
  - fill k of N correct → `docreview-total` shows the expected % (T3 AC3);
  - exhibits co-visible (mirror `tbs.test.ts:67`).
- Unit (`just test-ts`): `ankountant-research/lib.test.ts` (`searchCorpus`,
  `buildCitationSubmission`), doc-review submission builder + document-template
  segmentation in `ankountant-tbs/lib.test.ts`.
- Rust (`just test-rust`): if §6.1 array-key or §6.2 readiness arm is taken, add
  grading tests next to `grading.rs`/`readiness.rs` tests (existing patterns at
  `grading.rs:119`, `logic.rs:250`).
- Seed prerequisite: fixtures need the seed to produce **playable** research/
  doc-review notes (§6.3), else specs must author notes via `add_note`. Simplest is
  to enrich the seed (`seed.rs:412`) and add `shape::*` tags.

Deep-linking: research/doc-review routes should accept `?note=<id>` like TBS
(`ankountant-tbs/+page.ts:18`) so specs can target a specific seeded note; the seed
already returns `sealed_tbs_note_ids` (extendable to include the new shapes).

---

## 8. File-by-file change checklist (desktop)

**New (Svelte):**

- `ts/routes/(ankountant)/ankountant-research/{+page.ts,+page.svelte,ResearchSurface.svelte,lib.ts,lib.test.ts,corpus.far.json}`
- `ts/routes/(ankountant)/ankountant-doc-review/{+page.ts,+page.svelte,DocReviewSurface.svelte}`
- `ts/routes/(ankountant)/ankountant-workspace/panes/{ResearchPane.svelte,DocReviewPane.svelte}`
- `ts/tests/e2e/{research.test.ts,doc-review.test.ts}`

**Edit (Svelte/TS):**

- `ts/routes/(ankountant)/ankountant-tbs/lib.ts` — `RenderStep.options?`, `TbsModel.document?`, `buildDocReviewSubmission`, keep `parseSteps` dropping `answer_key`.
- `ts/routes/(ankountant)/ankountant-workspace/layout.ts` — `SurfaceKind` + `SURFACE_KINDS`.
- `ts/routes/(ankountant)/ankountant-workspace/surfaces.ts` — registry entries + imports.
- `ts/routes/(ankountant)/+layout.svelte` — tabs (optional but recommended).

**Edit (Qt/Python):**

- `qt/aqt/mediasrv.py` — `is_sveltekit_page` allowlist (+2).
- `qt/aqt/workspace.py` — `_ANKOUNTANT_ROUTES` (+2).
- `qt/aqt/webview.py` + `qt/aqt/ankountant.py` — **only if** dedicated dialogs/kinds wanted.
- `qt/tests/test_ankountant_wiring.py` — new page names (+ kinds if added).

**Edit (Rust — optional, per §6 decisions):**

- `rslib/src/ankountant/grading.rs` — array-valued citation answer key (§6.1).
- `rslib/src/ankountant/readiness.rs` — widen partial-credit arm to include `doc_review` (§6.2, if not submitting as `mode:"tbs"`).
- `rslib/src/ankountant/seed.rs` (+ `seed_content.json`) — enrich the stored-only research/doc_review notes + `shape::*` tags (§6.3).

**Build/verify:** `just check` (formats + builds + runs checks across layers),
then `just test-ts` / `just test-rust` / `just test-e2e`. A `.proto` change is only
needed for the optional seed-count fields (§6.3); everything else is codegen-free.

---

## 9. Open decisions (carry from PRD OQs)

- **OQ-2 (time as credit vs signal):** plan keeps time a **reported signal**
  (display + `latency_ms`), credit is correctness only. Matches `research-time`
  display above.
- **OQ-3 (corpus search backend):** plan uses **client-side** search over a bundled
  JSON (`searchCorpus`), no `SearchLiterature` RPC — offline, zero proto change.
  Revisit only if the corpus grows past what ships comfortably in the bundle.
- **Doc-review Performance weighting:** choose §6.2 option 1 (`mode:"tbs"`, zero
  backend) vs option 2 (`mode:"doc_review"` + readiness arm). Recommend option 2
  for analytics + true partial credit.
- **Research citation matching:** choose §6.1 array-key grader (recommended) vs
  single canonical citation (zero backend).
- **Menu surface vs shell-only:** decide whether research/doc-review get dedicated
  Qt dialogs + webview kinds (like TBS) or live only inside the shell/workspace
  (like Stats). Shell-only is lighter and needs no `webview.py` change.
