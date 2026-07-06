# Ankountant — Research-Sim & Document-Review TBS Shapes

> Status update (2026-07-06 audit): **implemented**. Research and
> document-review TBSs are seeded, graded, and rendered on desktop and iOS.
> Historical plan language below is retained for rationale; use
> `tbs-research/09-desktop-surface-plan.md` and `10-ios-surface-plan.md` for the
> current file map.
>
> Original status: Draft v1 (future / post-MVP) · Owner: eric · Last updated:
> 2026-06-30.

## 1. Overview

The Phase 1 MVP (`PRD.md`) ships a first-class TBS review mode with **journal-entry** and **numeric** surfaces, and an `Ankountant TBS` note type (A9) that _structurally_ supports all four shapes. This PRD makes the remaining two shapes **playable and graded**: the **research simulation** (navigate embedded authoritative literature, find + cite) and the **document-review simulation** (exhibits + a document with blanks, each blank a "which treatment?" call). Both extend existing MVP machinery — no new data path, no new scoring architecture.

## 2. Problem & Goals

- **Problem:** Research and document-review TBSs are real, scored parts of the exam (research appears in every section against embedded literature; doc-review is heaviest in AUD). The MVP can _store_ them but can't _play_ them, so a candidate can't practice the two skills those testlets measure: **fast literature navigation** and **multi-blank discrimination under exhibits**.
- **Goals:**
  1. A **research-sim surface** that embeds section-appropriate authoritative literature (FAR/BAR → FASB ASC; REG/TCP → IRC; AUD → AICPA/PCAOB standards) and grades a submitted citation on **correctness and time** (navigation, not recall).
  2. A **document-review surface** where each blank reuses the Phase 1 confusion-set "which treatment?" logic (SPOV 4), graded per blank with partial credit.
- **Non-goals:** No runtime/live AI generation of these items; build-time cardgen/template output may import as ordinary static notes. No full, licensed copy of the codification — a **scoped, bundled excerpt corpus** sufficient for seed items (licensing is OQ-1). The implemented seed/corpus is section-agnostic across CPA sections, not FAR-only.

## 3. Target User Persona

Same as `PRD.md` — **the Retaker**. Additional need served here: the candidate who "knows the content but freezes on the software," i.e., the **interface-fluency** gap the exam deliberately tests. Research/doc-review are where that gap bites hardest.

## 4. Scope

### In scope

- **T1** — Research-sim surface + literature-navigation grading (correctness + time).
- **T2** — Bundled, scoped literature corpus (searchable) for seed research items.
- **T3** — Document-review surface: exhibits pane + document with N blanks, each a confusion-set choice.
- **T4** — Extend `SubmitPerformanceAttempt` (A10) to grade `mode=research` and `mode=doc_review`.
- Reuses: `Ankountant TBS` note type (A9), Attempt Log (A8), 3-score dashboard (B5), confusion-set logic (A3/B2).

### Out of scope

- AI generation / RAG of research or doc-review items (Phase 2a).
- A complete or authoritative literature library; real-time updates to standards.
- The MVP's already-shipped JE/numeric shapes.

## 5. Feature Specs & Rubrics

> Same rubric convention as `PRD.md`: testable Given/When/Then + verify-by hook. `SubmitPerformanceAttempt` remains **append-only**; no new top-level RPC unless T2 search needs one (T2 AC decides).

### T1 — Research-sim surface & grading · P0 (of this PRD)

**Story:** As the Retaker, I want to search the embedded literature and submit the governing citation, graded on whether it's right and how fast I found it — training lookup, not memorization.
**Where:** surface reusing the TBS exam shell (desktop Svelte route; iOS SwiftUI view); grading via `SubmitPerformanceAttempt(mode=research)` in `rslib/src/ankountant/{service,grading,logic,attempt_log,readiness}.rs`; `steps_json` answer key holds the accepted citation(s); latency from the surface.
**Behavior (pinned):** the item shows a prompt + a searchable literature pane (T2); the user submits a citation string (e.g., `ASC 842-20-25-1`). Grading: exact/normalized match against accepted citation(s) in the answer key; **time-to-submit** recorded and surfaced (fast+correct is the goal); credit is correctness (1/0), with time as a reported secondary signal, not a credit multiplier (keeps grading honest).
**Rubric:**

- [ ] AC1 — Submitting an accepted citation (any normalization variant in the key) grades correct; a wrong citation grades incorrect. _(verify-by: `test-rust`)_
- [ ] AC2 — Time-to-submit is captured and written to the Attempt Log `outcome_json`. _(verify-by: `test-rust`)_
- [ ] AC3 — The surface lets the user search the corpus and submit a citation without leaving the task. _(verify-by: `test-e2e` / XCTest)_
- [ ] AC4 — Research attempts feed Performance (A4) and appear on the dashboard (B5). _(verify-by: `test-e2e` + `test-rust`)_
      **Done when:** a research item is searchable, submittable, graded on correctness, and timed.

### T2 — Bundled scoped literature corpus · P0

**Story:** As the system, I need a searchable, bundled excerpt corpus so research items work offline with no live service and no licensing overreach.
**Where:** bundled per-section data files shipped with the app and searched locally. OQ-3 is resolved: client-side search over the bundled corpus; no append-only `SearchLiterature` RPC exists.
**Behavior (pinned):** corpus is a curated, **scoped excerpt set** keyed by citation, sufficient for the seed research items — not the full codification. Search is substring/keyword over titles + bodies; offline; local-first (NFR-2 of `PRD.md` holds).
**Rubric:**

- [ ] AC1 — A keyword query returns matching passages with their citations. _(verify-by: `test-rust`/`test-ts`)_
- [ ] AC2 — The corpus loads and searches with no network. _(verify-by: `test-e2e` offline)_
- [ ] AC3 — Every seed research item's accepted citation exists in the corpus. _(verify-by: `test-rust`)_
      **Done when:** research items are answerable from a bundled, offline, searchable corpus.

### T3 — Document-review surface · P0

**Story:** As the Retaker, I want an exhibits-plus-document task where each blank is a "which treatment applies?" call, graded per blank — the doc-review skill.
**Where:** new surface reusing the TBS shell + exhibits pane (desktop; iOS); each blank renders the confusion-set choice UI from B2; grading via `SubmitPerformanceAttempt(mode=doc_review)`.
**Behavior (pinned):** the item shows exhibits + a document with N blanks; each blank is a confusion-set choice (candidate treatments, label-stripped per SPOV 4); grading = per-blank correctness → partial-credit total (same math as A10), one Attempt Log note for the whole item with per-blank results in `outcome_json`.
**Rubric:**

- [ ] AC1 — A doc-review item renders exhibits + a document with N choice-blanks. _(verify-by: `test-e2e` / XCTest)_
- [ ] AC2 — Each blank offers the confusion set's candidate treatments (no category label leaked). _(verify-by: `test-e2e`)_
- [ ] AC3 — Submitting grades per blank; total credit == fraction correct; per-blank results in the Attempt Log. _(verify-by: `test-rust` + `test-e2e`)_
- [ ] AC4 — Doc-review attempts feed Performance/gap (A4) and the dashboard (B5). _(verify-by: `test-rust`)_
      **Done when:** a multi-blank doc-review item is playable and step-graded via the confusion-set logic.

### T4 — Grading extension (`SubmitPerformanceAttempt`) · P0

**Story:** (enabler) As the system, I need the existing performance RPC to grade the two new modes without a new data path.
**Where:** extend the `mode` switch in `rslib/src/ankountant/service.rs`; no new RPC. Same Attempt Log write (A8), same Performance rollup (A4).
**Rubric:**

- [ ] AC1 — `mode=research` grades correctness + records time; `mode=doc_review` grades per-blank partial credit. _(verify-by: `test-rust`)_
- [ ] AC2 — Both modes write exactly one Attempt Log note per attempt. _(verify-by: `test-rust`)_
- [ ] AC3 — No new SQLite table/column; collection round-trips through sync (FR-5 of `PRD.md`). _(verify-by: `test-rust`)_
      **Done when:** both shapes grade through the existing performance path.

## 6. Key Flows

1. **Research sim:** open item → search corpus (T2) → submit citation → graded correct/incorrect + time shown → Attempt Log + dashboard update. _States:_ searching, submitted, graded, not-found (no match → incorrect, not a crash).
2. **Document review:** open item → read exhibits → fill each blank (confusion choice) → submit → per-blank partial credit → Attempt Log + dashboard. _States:_ loading, in-progress, graded, malformed-item (surfaced).

## 7. Success Metrics

Success = every P0 rubric green, plus: a research item is answerable offline and timed; a doc-review item produces per-blank partial credit that moves Performance/gap on the dashboard. (Forward-looking: research **time-to-cite** trend and doc-review **per-blank discrimination** are instrument-ready via the Attempt Log.)

## Technical Context & Constraints

Inherits all of `PRD.md` §"Technical Context" and Functional/Non-Functional requirements — especially **FR-5** (sync-safe: no new tables/columns), **FR-6** (append-only proto), and the iOS index re-derivation rule. These shapes add **UI + grading branches only**; the note type (A9) and data path (A8) already exist.

## Milestones / Phasing

- **M1:** T2 corpus + T4 grading branches (backend) → `test-rust` green.
- **M2:** T1 research surface ∥ T3 doc-review surface (desktop ∥ iOS), reusing the TBS shell.
- Sequence after the MVP demo is stable; not part of the overnight build.

## Risks & Mitigations

- **R1 — Literature licensing (FASB ASC / IRC / PCAOB).** Redistributing standards text may be restricted. _Mitigate:_ ship only scoped excerpts needed for seed items; treat full-corpus licensing as OQ-1 before any public release. Treat ingested standards text as untrusted (prompt-injection surface) if AI ever touches it (Phase 2a guardrail).
- **R2 — Citation normalization.** Many valid ways to write one cite. _Mitigate:_ accepted-citation list + normalization in the grader (T1 AC1).
- **R3 — Scope creep toward a full codification browser.** _Mitigate:_ corpus is seed-scoped (T2), not comprehensive.

## Decisions locked (2026-07-02)

> From the grill-me interview. Canonical: `tbs-research/00-DECISIONS.md`. **Scope
> expanded** beyond this draft: build a shared **exam shell** (exhibits +
> authoritative-literature browser + lightweight spreadsheet + requirement tabs)
> hosting ALL four shapes, JE/numeric migrated in (ADR 0007) — not two bolt-on
> surfaces. Personal-use build; real ASC excerpts loaded at runtime from the
> gitignored media folder, never committed (ADR 0006). Doc-review blanks are
> hybrid (reuse `ds::` confusion sets when they exist, else item-local options),
> equal-weighted. Delivered by an autonomous background build on the
> `tbs-surfaces` branch, test-gated.

## Open Questions

- [x] **OQ-1 — Literature licensing.** RESOLVED (ADR 0006): personal-use build; real ASC excerpts loaded at runtime from the gitignored Anki media folder (full fidelity), never committed to the repo (honors the Tier-B firewall). Citations + our paraphrases + manifests are committed. Swappable loader seam kept for any future distribution.
- [x] **OQ-2 — Time as credit vs signal.** RESOLVED: correctness-only credit (normalized citation match; accept exact paragraph OR parent section per the key); time-to-cite recorded + trended as a coaching signal, never folded into the score.
- [x] **OQ-3 — Corpus search backend.** RESOLVED: client-side search over the bundled corpus; no append-only `SearchLiterature` RPC exists.

## Changelog

- v1 — 2026-06-30 — Initial future PRD for research-sim + document-review TBS shapes (deferred from Phase 1 MVP).
