# TBS Surfaces — Locked Decisions (2026-07-02)

> North star for the "finish the deferred TBS surfaces" effort. Read this FIRST
> for the research synthesis, seed authoring, and implementation phases. Source:
> grill-me interview with eric, 2026-07-02.
>
> 2026-07-06 audit update: the effort described here is implemented. Research
> and document-review TBSs are seeded, graded, and rendered on desktop and iOS.
> Use `09-desktop-surface-plan.md`, `10-ios-surface-plan.md`, and
> `12-designsystem-workspace-integration.md` for current file maps.

## Decisions

- **D1 — Scope = full exam-shell fidelity** (ADR 0007). Build a shared
  Prometric-style TBS shell — exhibits pane + authoritative-literature browser +
  lightweight scratch spreadsheet + multi-part requirement tabs — and render ALL
  four shapes (JE, numeric, research, doc-review) inside it. JE/numeric migrate
  into the shell (upgraded). Composes onto the tiling workspace (ADR 0002).
- **D2 — Distribution = personal use, indefinitely.** No public release planned;
  fidelity prioritized over licensing.
- **D3 — Literature corpus = real ASC excerpts, runtime-only, uncommitted**
  (ADR 0006). Real FASB ASC prose loaded at runtime from the gitignored Anki
  media folder for full fidelity; NEVER committed (honors the Tier-B firewall).
  Citations + our paraphrased summaries + manifests ARE committed. Behind a
  swappable loader (the T2 seam).
- **D4 — Research grading = correctness-only; time is a signal, not credit.**
  Normalized citation match; accept the exact paragraph OR its parent section if
  the key lists it. Time-to-cite is recorded in the Attempt Log + trended, but
  never changes the score. (Resolves OQ-2.)
- **D5 — Doc-review blanks = hybrid; equal weight.** Each blank reuses a `ds::`
  confusion set when one exists (so misses feed weakness-tracking), else a custom
  inline option list. Blanks weighted equally (1/N) with an optional per-blank
  override.
- **D6 — Spreadsheet = lightweight formula grid.** Cell refs + basic formulas
  (SUM, + − × ÷, ROUND/AVERAGE); scratchpad only, never graded. (Grill Q6 skipped
  → this default.)
- **D7 — Autonomy = full implementation on an isolated branch.** Background
  pipeline runs research → synthesis → seed → implement on an isolated
  worktree/branch (`tbs-surfaces`), test-gated (`just check` green) before any
  merge. Progress reported; `main` is never disrupted.

- **D8 — Section-agnostic engine, multi-section content** (ADR 0008). The TBS
  shell/surfaces/data-model cover ALL CPA sections (AUD, FAR, REG, BAR, ISC, TCP)
  and all shapes via a `section` dimension; seed content spans sections (lead with
  AUD document-review, REG/IRC research, FAR footnote/numeric). Confusion sets +
  `GetReadiness(section)` go multi-section (config is already per-section).
- **D9 — One union note type + typed schemas** (ADR 0008). Keep the single
  `Ankountant TBS` note type discriminated by `tbs_type` (shape) AND `section`;
  express per-shape structure as first-class versioned/validated typed schemas +
  a typed exhibit model — NOT the "unknown-keys-ignored" trick. No new note type,
  no new SQLite. (Resolves the note-type question in favor of one union type.)
- **D10 — Per-section literature + licensing flip** (ADR 0008; agent 05). ASC
  (FAR/BAR) stays cite-only (ADR 0006); IRC/Treasury/IRS (REG/TCP), SEC (eCFR),
  PCAOB (AUD), NIST (ISC) are public domain → bundle REAL verbatim text there.
  One loader, multiple bodies.

## Hard constraints (inherited from PRD.md)

- **Sync-safe:** NO new SQLite tables/columns — notes, `col` config JSON,
  `card.custom_data`, and media files only.
- **Proto append-only;** iOS `SchedulerMethod` indices hand-resynced (FR-6).
- Grading stays on the existing `SubmitPerformanceAttempt` step-graded path.

## Resolved in synthesis (2026-07-02, from the research fleet)

- **OQ-3 → client-side corpus search** over a bundled file (no `SearchLiterature`
  RPC). Agents 08/09/11.
- **Backend delta is tiny:** `SubmitPerformanceAttempt` is already shape-agnostic
  and ignores unknown `steps_json` keys → NO proto change, NO new note-type field,
  NO SQLite change, NO iOS index churn. Only additions: a `research` grading arm +
  citation normalization + `elapsed_ms`, and a `doc_review` fractional arm in
  `readiness.rs`. doc_review grading is otherwise free.
- **Seed source + caveat:** `60.pdf.pdf` = Wiley CPAexcel **2014** FAR guide (41
  research items + AICPA App B/App C doc-review tables). **2014 vintage** (ASC 840
  not 842, pre-606) → verify every citation/treatment against CURRENT GAAP before
  seeding. `FAR TBS.pdf` = one retired numeric TBS (no research/doc-review).
- **Corpus content:** committed = citation keys + titles + our paraphrases + deep
  links; verbatim ASC prose never committed (Tier-B), optional uncommitted media
  overlay (ADR 0006 + agent 05).
- **iOS parity:** desktop-first (gated), iOS fast-follow (non-gated).

Full spec: **`BUILD-PLAN.md`** (this folder).

## Pipeline / status

- **Complete:** research agents, synthesis, seed content, desktop surfaces, iOS
  surfaces, workspace registration, and shared Rust grading path.
- **Current follow-up:** expand production content coverage, add/refresh e2e and
  XCTest coverage as interactions change, and keep literature corpora aligned
  across Rust/TS/iOS resources.

## References

- PRD: `docs_ankountant/PRD-tbs-shapes-future.md`
- ADRs: `0006` (corpus), `0007` (exam-shell), `0002` (workspace tiling)
- Glossary: `CONTEXT.md` → "TBS (Task-Based Simulations)"
