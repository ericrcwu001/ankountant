# TBS Surfaces — Consolidated Build Plan (2026-07-02)

> Synthesis of the 12-agent research fleet + the locked decisions
> (`00-DECISIONS.md`). This is the implementation spec for the `tbs-surfaces`
> branch. Read alongside the per-topic research (`01`–`12`) in this folder.

> **2026-07-06 audit update:** the `tbs-surfaces` work has landed. Keep this file
> as historical implementation context; use `09-desktop-surface-plan.md`,
> `10-ios-surface-plan.md`, and `12-designsystem-workspace-integration.md` for the
> current as-built maps.

## SCOPE UPDATE (2026-07-02): section-agnostic, ALL sections

> This plan was drafted FAR-first; per the grill-me follow-up it is now
> **section-agnostic across all CPA sections** (AUD, FAR, REG, BAR, ISC, TCP) —
> see **ADR 0008** + `00-DECISIONS.md` D8–D10. Net changes to everything below:
> (1) add a `section` dimension to the one `Ankountant TBS` union note type and use
> **first-class typed/validated schemas** per shape (+ typed exhibits), NOT the
> unknown-keys trick; (2) the literature corpus is **per-section/per-body** — FASB
> ASC cite-only (ADR 0006), but IRC/SEC/PCAOB/NIST are public-domain and **bundled
> verbatim**; (3) seed **across sections** (lead with AUD doc-review, REG/IRC
> research, FAR footnote/numeric); (4) confusion sets + readiness are multi-section
> (config keys already are `ankountant.<key>.<section>`). Read the FAR-worded
> sections below as the _template_, applied per section.

## The load-bearing finding

`SubmitPerformanceAttempt` is **shape-agnostic**: `mode` (field 2) and
`submission_json` (field 3) are free-form strings; the grader routes any
non-`"confusion"` mode through the generic per-step path; and `GradableStep` /
`Outcome` ignore unknown JSON keys (no `deny_unknown_fields`). ⇒ **research +
doc_review required NO proto field change, NO new note-type field, NO SQLite
change, and NO iOS index churn.** The landed work is explicit mode validation,
real typed seed content, bundled literature, and desktop/iOS rendering for all
four TBS shapes.

## Resolved open questions / reconciliations

- **OQ-3 (corpus search) → client-side** over a bundled file (agents 08/09/11).
  No `SearchLiterature` RPC.
- **Doc-review readiness (agent 08):** in `readiness.rs`, bucket
  `"tbs" | "doc_review" => fractional` and `"confusion" | "research" => binary`.
  Attempts log `mode="doc_review"` / `mode="research"`; everything after (Wilson
  band, CPA transform, coverage) is already mode-agnostic.
- **doc_review grading is FREE** — the existing default `steps` arm + `grade()`
  already do per-blank partial credit. Only **research** needs a new grading arm.
- **Corpus content (reconciles ADR 0006 + agent 05 licensing):** the COMMITTED
  corpus (`seed_literature.json`) = citation keys + short titles + OUR paraphrased
  summaries + deep links to `asc.fasb.org`. **Verbatim ASC prose is NEVER
  committed** (Tier-B); a loader optionally overlays real excerpts from the
  uncommitted Anki media folder if the user drops them in (personal use).

## Workstream A — Rust backend + seed · gate: `just test-rust` + `just test-py`

- **A1** `readiness.rs:~86` — add the `doc_review` fractional arm + `research`
  binary arm (see reconciliations).
- **A2** `logic.rs` — `citation_normalize()` + `citation_matches()` (strip
  `FASB ASC`/`ASC` prefix, unify hyphen/space/dash separators, leading-zero-
  insensitive sections; accept the exact paragraph OR its parent section when the
  key lists it). `grading.rs`/`service.rs` — add a `"research"` arm in
  `parse_submission` → `grade_research()` (single `citation` step, **multi-valued
  accepted-citation list**, all-or-nothing). Add `Outcome.elapsed_ms: Option<u32>`
  (`#[serde(default)]`, backward-compatible) and write time-to-cite into
  `outcome_json` (T1 AC2). **doc_review reuses the existing per-step path.**
- **A3** Seed — implemented with section-agnostic typed `section_items[]` in
  `seed_content.json`, sealed-bank placement, `sec::<section>` tags, and `ds::`
  schema tags so research/doc-review items feed Performance rather than the study
  schedule.
  * ⚠️ **CRITICAL GAAP-vintage check:** `60.pdf` is 2014 (ASC 840 not 842, pre-606,
    "extraordinary items"). **Verify every citation + treatment against CURRENT US
    GAAP** (ASC 842 leases, ASC 606 revenue, no extraordinary items) before
    seeding; prefer current-GAAP items, fix or drop stale ones, and add a short
    provenance note per seeded item.
- **A4** Corpus — build-embedded `seed_literature.json` via `include_str!`
  (citation key → `{title, paraphrase, deep_link}`; committed = titles +
  paraphrases + links ONLY). Loader interface + optional media-overlay for
  verbatim excerpts (uncommitted). Client-side searchable.
- **A5** Tests — research grading (normalization; section-vs-paragraph; multi-
  valued key; all-or-nothing); doc_review per-blank partial credit feeding the
  fractional readiness bucket; seed counts; a `PRAGMA table_info` round-trip
  proving no new table/column.

## Workstream B — Desktop exam shell + surfaces · gate: `just test-ts` + `just check`

- **B1 Exam shell** (`ts/routes/(ankountant)/ankountant-tbs/`): a **composite
  surface with an internal split** (exhibits/tools right, requirement/response
  left) — exhibit co-visibility is a hard rule, so it is ONE surface, not separate
  panes (agent 12). Add: tabbed exhibits pane, lightweight formula-grid
  spreadsheet (SUM / + − × ÷ / ROUND / AVERAGE; **ungraded** scratchpad),
  requirement tabs, and the existing confidence gate.
- **B2 Research surface:** prompt + client-side `searchCorpus()` over the bundled
  corpus + citation input + submit (`mode:"research"`, one `citation` step) +
  correct/incorrect + time-to-cite. The literature browser is ALSO exposed as a
  standalone read-only tileable pane (agent 12).
- **B3 Doc-review surface:** exhibits pane + document body with inline blank
  markers → label-stripped `<select>` dropdowns (reuse confusion-set treatments
  where a `ds::` set exists, else item-local options) → submit all blanks
  (`mode:"doc_review"`) → per-blank ✓/✗ + partial-credit total. Never emit
  `correct_option` to the client.
- **B4 JE upgrade** (competitor gap, agent 07): controlled account-picker dropdown
  (not free text) + "no entry required" + spare rows.
- **B5 Results layer** (differentiator, agent 07): per-blank reveal + correct value
  - rationale + citation/Blueprint tag.
- **B6 Register surfaces:** `workspace-layout.ts` `SurfaceKind` union +
  `SURFACE_KINDS`;
  `surfaces.ts` registry; `panes/*Pane.svelte` (filter by `tbsType` — `TbsPane`
  currently grabs the first TBS note regardless of shape); shell routes/tabs;
  `mediasrv.py` allowlist; `workspace.py` route map. Tokens: tabular `--font-mono`
  cells, `--fg-success`/`--fg-error` + icon + label, `--border-control`.
- **B7** e2e specs mirroring `tbs.test.ts` / `confusion.test.ts`.

## Workstream C — iOS parity · non-gated (fast-follow)

- **C1** iOS simulation surfaces — implemented with `ResearchTaskView` (search +
  citation input) and `DocReviewTaskView` (exhibits + `Picker` blanks), sharing
  the confidence gate and common simulation models.
- **C2** `TbsParsing`/`TbsModels` — add `RenderStep.options`/`placeholder`, input
  structs, a generic `buildStepsSubmission` (mirror desktop `lib.ts`); extend
  `TbsParsingTests`. No index resync (no new RPC). New files auto-included via
  xcodegen.

## Non-negotiables

Sync-safe (NO new SQLite tables/columns — only notes, `col` config JSON,
`card.custom_data`, media, and `include_str!` data). Proto append-only (nothing
needed here). Never leak `answer_key` / `correct_option` into client DTOs. Grading
stays on the existing `SubmitPerformanceAttempt` step-graded path.

## Delivery

Historical delivery order was A (gated) → B (gated) → C → final `just check`.
Future edits should use the current as-built docs listed at the top of this file.
