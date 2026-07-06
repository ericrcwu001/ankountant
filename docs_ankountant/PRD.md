# Ankountant — Phase 1 MVP PRD (loop-facing)

> Status: Draft v4 · Owner: eric · Last updated: 2026-07-06
> Scope: **Phase 1 of `brainlift_features.md` only.** Grounded in `brainlift.md` + a codebase survey.
> **This file is the `agentic-loop`-facing spec** — kept lean so Plan/scope-guard stay cheap. Each feature carries a quotable requirement, objective acceptance bullets (the Contract phase reads these), and a **Detail:** pointer. **Implementers: open the referenced `prd/*.md` file before building a feature** — it holds the full acceptance criteria, proto contracts, data model, and integration file paths.
> Launch parameters (clarifications + config) and the seed spec are in **`prd/build-spec.md`**.

## 1. Overview

Ankountant is a fork of Anki (shared Rust core + PyQt desktop + native iOS SwiftUI) retargeted at the **CPA exam**. Where Anki optimizes open-ended recall, Ankountant measures and trains three things a candidate needs to pass: **Memory** (recall a taught fact), **Performance** (answer a _new_ exam-style item that uses it), and **Readiness** (what you'd _score today_, as a range, abstaining when evidence is thin). The MVP proves this with inclusive CPA starter content, no runtime AI generation, local-first.

## 2. Problem & Goals

- **Problem:** Candidates who fail a section (FAR ~42% pass, the hardest) drilled flashcards, _felt_ ready, and still failed. Anki/FSRS reward comfortable review at a fixed retention target with **no exam date**, **no discrimination training** (topic decks hand you the category free), and **no honest readiness signal** (self-rated confidence is inflated). Incumbents bolt a TBS bank onto a flashcard app; none separate "feels ready" from "is ready."
- **Goals:** (1) scheduling anchored to an exam date; (2) discrimination training via a label-stripped "which treatment applies?" gate; (3) TBS as a first-class step-graded mode (partial credit); (4) an honest 3-score readout (Memory / Performance / Readiness) that surfaces the Memory−Performance gap and abstains on thin data.

## 3. Target User Persona

**Primary — the Retaker.** Failed FAR once with an employer's Becker license; technically comfortable, self-funding the retake; has already consumed the incumbent course. **Pain:** no honest diagnosis — fluency masquerades as mastery; topic decks let her pattern-match the category; TBSs (≈half the score) get under-practiced. **Win:** "here's the gap between what you _recognize_ and what you can _do_ on a fresh item, and your projected readiness for your exam date — or 'not enough data yet.'" Secondary: self-funded international / career-changer (same core need; no distinct requirements).

## 4. MVP scope & phasing

**Build order (hard):** **Phase A — shared Rust/proto/data-model** must be complete (`just check` + `test-rust` green) before **Phase B — frontends**, which then run as parallel tracks (desktop `qt/`+`ts/` ∥ iOS `ios/`). Every B feature declares `dependsOn` on its Phase-A features.

**In scope:** A1–A10 (§5 Phase A) + B1–B5 (§5 Phase B) + inclusive CPA starter content (`prd/build-spec.md`).

### Non-goals (pass this block verbatim as `clarifications.nonGoals` at launch)

- **AI/RAG card generation, quality checker, leakage/baseline eval → Phase 2a (out).**
- **Cloud sync, accounts, sync server → Phase 2b (out).** MVP is local-first, single-device, but built sync-safe (no new tables/columns) so Phase 2b needs no rework.
- **Populating provenance fields → Phase 2a (out).** The fields are **stored** on the TBS note type (in-scope, forward-compat); only their **population** is out.
- **Real IRT/CAT psychometrics (out)** — Readiness is the ADR 0005 Wilson-to-CPA-scale band heuristic; adaptive CAT item selection and faithful AICPA score reproduction remain out.
- **Populating a full production-scale unique CPA bank → Phase 2a+ (out).** The current app renders and grades all four TBS shapes; expanding coverage to a full unique 50k grounded bank remains out.
- **BAR-first specialization; ablation study; full course library; head-on B2B/Becker — all out.**

## 5. Feature specs

> Format: quotable requirement + **Acceptance (objective)** bullets (Contract-phase substance) + **Detail:** pointer (Build opens it). Full ACs: `prd/rubrics-core.md` (A) / `prd/rubrics-frontend.md` (B). Proto + data model + integration paths + build/test commands: `prd/contracts-and-data.md`. Constants, seed, cut order, risks: `prd/build-spec.md`.

### Phase A — shared core

#### A1 — Deadline-anchored scheduler · P0 · depends: none

Intervals are computed backward from the exam date so recall peaks on exam day, not indefinitely. `desired_retention(days_to_exam)` ramps from 0.80 (≥60d out) to 0.95 (exam day), linear between; no exam date → the deck/preset configured retention (open-horizon). `ComputeExamSchedule` previews the ramp; `SetExamDate`/`GetExamDate` persist the date as a sync-safe hidden `Ankountant Settings` note keyed by `(section, exam.date)`, with a read-only legacy `col`-config fallback. Plugs into the existing FSRS `next_states` — no new scheduling math.

- **Acceptance (objective):** ramp exact at 90d→0.80, 30d→0.875, 0d→0.95, no-date→configured value (test-rust); a nearer exam date yields a shorter next interval than a farther one for the same card (test-rust); exam-date set/read round-trips through the settings-note RPC path and legacy config remains a read-only fallback (test-rust/test-py).
- **Detail:** `prd/rubrics-core.md` (A1) · `prd/contracts-and-data.md`.

#### A2 — Latency-aware "too-easy" defunding, rote cards only · P1 · _cut early_ · depends: A6

Fast, correct, confident answers on **rote/fluency** cards get their interval pushed out; **critical-thinking (`cog::applied`) cards are never latency-defunded** (that would reward the fluency illusion the app exists to expose). Fires only on `cog::rote` cards. Confidence is read from `card.custom_data` (written at answer time; Phase-A tests seed it) — **no Phase-B dependency.** Effect is a pre-FSRS desired-retention reduction, not a post-hoc multiplier.

- **Acceptance (objective):** on a stable rote card with a baseline, fast+correct+Confident → longer interval + `custom_data.te=1` (test-rust); an applied card is untouched (test-rust); new/learning cards untouched (test-rust); cold-start uses the rote cohort median (test-rust).
- **Detail:** `prd/rubrics-core.md` (A2). _If the night runs short this is cut first and marked `parked` so it does not gate the contract._

#### A3 — Confusion-set queue builder · P0 · depends: A6, A8

New RPC `BuildConfusionQueue(section)` returns a label-stripped, interleaved queue that mixes confusable standards and orders confusion sets by the user's discrimination weakness (lowest accuracy first, from the Attempt Log grouped by `confusion_set_id`). The client-facing payload omits topic/category labels.

- **Acceptance (objective):** never 3+ consecutive same-tag items (test-rust); a weaker set (40%) ranks before a stronger one (80%) (test-rust); the item DTO has no populated category-label field (test-rust). _(Timing is a non-gating perf note, not an assertion.)_
- **Detail:** `prd/rubrics-core.md` (A3) · `prd/contracts-and-data.md`.

#### A4 — Mastery + gap query · P0 · depends: A6, A7, A8

New RPC `GetReadiness(section)` returns, per topic, `memory` (trailing-30d recall accuracy on the study pile), `performance` (accuracy on the sealed bank, MCQ+TBS weighted 50/50), and `gap = memory − performance` — the "feels ready, isn't" signal.

- **Acceptance (objective):** returns memory, performance, and gap==memory−performance (test-rust); performance computed only from sealed-bank attempts, no study-pile leakage (test-rust); TBS attempts contribute their partial-credit fraction (test-rust). _(Timing non-gating.)_
- **Detail:** `prd/rubrics-core.md` (A4) · `prd/contracts-and-data.md`.

#### A5 — Abstain rule · P0 · depends: A4

`GetReadiness` returns "not enough data yet" instead of a fabricated number when evidence is thin. Abstain when sealed attempts < 20 or confusion-set coverage < 60%. Otherwise readiness is a Wilson sealed-Performance band projected through the ADR 0005 CPA scaled-score transform (0–99, pass line 75), with `band_low`, `band_high`, `point_estimate`, `coverage`, `generated_at`, and factual `reasons`. The UI may show the center only alongside the band; never render a bare point.

- **Acceptance (objective):** <20 attempts → abstain "insufficient volume" with coverage still populated (test-rust); ≥20 but coverage <60% → abstain "insufficient coverage" (test-rust); sufficient data → CPA-scale band low<high + point estimate + coverage/reasons, never a bare point (test-rust); halving volume at fixed accuracy widens the band (test-rust).
- **Detail:** `prd/rubrics-core.md` (A5).

#### A6 — Deep-structure + cognitive-demand tags · P0 · depends: none

Notes/cards carry `ds::…` deep-structure tags (grouped into confusion sets via the CONFUSABLE map in `col` config) and `cog::rote`/`cog::applied` cognitive-demand tags (which gate A2). Both sync natively as Anki tags.

- **Acceptance (objective):** query returns all notes for a `ds::` tag (test-rust); the CONFUSABLE map resolves each tag to exactly one set_id (test-rust); cards filterable by `cog::` tag (test-rust); tags round-trip through save/reopen (test-rust).
- **Detail:** `prd/rubrics-core.md` (A6) · `prd/contracts-and-data.md`.

#### A7 — Sealed performance bank (firewall) · P0 · depends: none

A dedicated deck of same-topic, new-surface items held permanently suspended (`queue = -1`) so the study scheduler never serves them — the firewall that makes Performance measure transfer, not re-recall. Enforced by the existing scheduler, verified empirically.

- **Acceptance (objective):** sealed cards never appear in `GetQueuedCards` for study (test-rust); sealed and study items on a topic are distinct notes (test-rust); attempts feed Performance but not the FSRS schedule (test-rust).
- **Detail:** `prd/rubrics-core.md` (A7).

#### A8 — Attempt Log note type (sync-safe data path) · P0 · depends: none

Each gated Performance attempt is stored as one hidden "Attempt Log" note (item ref, confusion_set_id, mode, pre-reveal confidence, latency, per-step partial credit) — replacing the sync-breaking "confidence column on revlog." This is the single source for the 3 scores + calibration. Reuses the Reader's proven notes-as-storage pattern; no new SQLite table/column.

- **Acceptance (objective):** a confusion answer writes one note with confidence/latency/set_id/outcome (test-rust); a TBS attempt writes one note with per-step credit (test-rust); Attempt Log notes never appear in the study queue (test-rust); `PRAGMA table_info` for notes/cards/revlog is identical before/after + save/reopen (test-rust).
- **Detail:** `prd/rubrics-core.md` (A8) · `prd/contracts-and-data.md`.

#### A9 — TBS note type, all 4 shapes · P0 · depends: none

One `Ankountant TBS` note type structurally holds all four shapes (research / journal-entry / numeric / document-review) plus exhibits and ordered weighted gradable steps. Journal-entry + numeric are fully playable (B4); research + document-review are **storable** but their surfaces are deferred. Provenance fields are **stored** (unpopulated — population is Phase 2a).

- **Acceptance (objective):** validates + stores a JE and a numeric TBS (test-rust/test-py); `steps_json` supports N steps each with answer key + weight (test-rust); a doc_review and a research TBS store without schema change (test-rust); provenance fields exist and default empty (test-rust).
- **Detail:** `prd/rubrics-core.md` (A9) · `prd/contracts-and-data.md`.

#### A10 — TBS step-grading backend · P0 · depends: A8, A9

New RPC `SubmitPerformanceAttempt` grades a TBS/confusion submission line-by-line with partial credit (method vs slip, not one binary lapse), returns per-step results + total, and persists the Attempt Log note in the same transaction. The "real Rust change" alongside the scheduler.

- **Acceptance (objective):** 4-line JE, equal weights, 3 correct → per_step [ok,ok,ok,wrong], total 0.75 (test-rust); one wrong amount marks only that line wrong (test-rust); numeric graded per cell with tolerance (test-rust); every call writes exactly one Attempt Log note (test-rust); callable from Python (test-py).
- **Detail:** `prd/rubrics-core.md` (A10) · `prd/contracts-and-data.md`.

### Phase B — frontends (desktop ∥ iOS)

> Each B feature depends on Phase A. **Desktop ACs are the objective contract (Playwright specs); iOS ACs are a non-gated demo checklist** (no Playwright-equivalent) — do NOT enter iOS ACs as contract assertions. Full ACs + the desktop/iOS split: `prd/rubrics-frontend.md`.

#### B1 — Attempt-before-reveal + confidence capture · P0 · depends: A8

The reveal is blocked until the user commits a discrete Guess/Unsure/Confident confidence pre-reveal; it flows to `SubmitPerformanceAttempt` (Performance modes) and mirrors to `card.custom_data` (recall — the scalar A2 reads).

- **Acceptance (objective, desktop):** back cannot show until confidence committed (test-e2e); confidence persists and is visible to `GetReadiness` (test-e2e + test-rust); three levels keyboard-selectable (test-e2e).
- **Detail:** `prd/rubrics-frontend.md` (B1).

#### B2 — "Which treatment applies?" gate · P0 · depends: A3, A10, B1

A label-stripped pre-computation step: pick the governing standard/method before any numeric entry; graded on discrimination and logged.

- **Acceptance (objective, desktop):** item DTO has no category label + no `data-testid="category-label"` element (test-rust + test-e2e); selecting a treatment scores it (test-e2e); the attempt moves the topic's Performance/gap (test-e2e + test-rust).
- **Detail:** `prd/rubrics-frontend.md` (B2).

#### B3 — Confusion-set review mode · P0 · depends: A3, B1, B2

A study mode that serves the interleaved, label-stripped confusion queue and runs the confidence capture + which-treatment gate per item.

- **Acceptance (objective, desktop):** the mode plays the interleaved queue, not-all-same-treatment consecutive (test-e2e); each item runs B1+B2 (test-e2e); completing the queue updates the dashboard Performance (test-e2e).
- **Detail:** `prd/rubrics-frontend.md` (B3).

#### B4 — TBS review surface: journal-entry + numeric · P0 · depends: A9, A10

A new screen (not the card reviewer) that renders TBS notes with an exhibits pane and step-graded partial credit — a JE grid and numeric cells, submitted via `SubmitPerformanceAttempt`.

- **Acceptance (objective, desktop):** JE grid renders; a partially-correct submission shows per-line results + partial-credit total matching A10 (test-e2e); numeric graded per cell (test-e2e); NO Again/Hard/Good/Easy buttons present (test-e2e); exhibits visible (test-e2e).
- **Detail:** `prd/rubrics-frontend.md` (B4).

#### B5 — Three-score dashboard · P0 · depends: A4, A5

One screen showing Memory, Performance, the gap, and exam-day Readiness as a band + confidence — or the honest abstain message when data is thin.

- **Acceptance (objective, desktop):** with data → Memory/Performance/gap + Readiness band (low–high) + confidence, never a point (test-e2e); thin data → abstain message + reason, no number (test-e2e); gap ≥ 0.25 renders with a `gap-warning` class (test-e2e); Readiness labeled exam-day (test-e2e).
- **Detail:** `prd/rubrics-frontend.md` (B5).

## 6. Key flows

1. **Set exam date → schedule reshapes** (`SetExamDate` writes a sync-safe settings note; near date ⇒ shorter intervals). 2. **Confusion-set session** (fetch queue → per item: confidence → label-stripped treatment pick → graded + logged). 3. **TBS session** (open the exam shell → complete journal-entry, numeric, research, or document-review task → submit → per-step or citation credit). 4. **Readiness check** (dashboard → abstain on thin data, else a CPA-scale band + center + the gap). Each flow has empty/loading/error states (see `prd/rubrics-*.md`).

## 7. Success metrics

Demo proof-points (each maps to an acceptance test): exam-date change reschedules; fast-correct on a rote card defunds it; the which-treatment gate produces a Performance signal distinct from recall; the Memory−Performance gap computes and displays; Readiness abstains on thin data and narrows as attempts accrue.

## 8. Functional requirements (one-liners; detail in `prd/`)

- **FR-1** FAR weights MCQ/TBS 50/50; TBS contributes partial-credit fractions.
- **FR-2** Firewall (hard): no note is both a study item and a sealed item; the scheduler never queues sealed / Attempt-Log / TBS-log notes.
- **FR-3** Abstain if sealed attempts < 20 (strict) or coverage < 60% (coverage = sets-with-≥1-attempt / sets-defined).
- **FR-4** Tunable constants in one module: ramp 0.80/0.95/60d; too-easy floor 21d, fast factor 0.5×, retention reduction −0.05 (floor 0.70), trailing-5, min-own-reps 3.
- **FR-5** Sync-safe (hard): no new SQLite tables/columns; hidden notes + `col` config + `custom_data` only.
- **FR-6** Proto append-only + iOS resync: append new RPCs without reordering existing service/method IDs; re-derive iOS indices from `_backend_generated.py` after `just check` + a dispatch smoke test.
- **FR-7** Readiness is never a bare point — a CPA-scale band + center + confidence/coverage, labeled exam-day.

## 9. Non-functional requirements

- **NFR-1** _Blocking:_ `GetReadiness`/`BuildConfusionQueue` <100 ms on the FAR seed. _Evidence artifact:_ `just ankountant-bench` reports the release-mode shared Rust engine floor for answer, next-card, and dashboard operations. _Non-blocking (post-MVP):_ full UI/platform latency on 50k notes remains separately measured.
- **NFR-2** Local-first / offline; no account. **NFR-3** Data round-trips through standard Anki sync unchanged (Phase 2b needs no rework). **NFR-4** AGPL-3.0. **NFR-5** Desktop (macOS/Win/Linux) + iOS, one shared core. **NFR-6** Core grading, scheduling, readiness, and generated card content are deterministic/offline. Optional Learning Feedback may call OpenAI during review/simulation when configured with a user API key; it is tutoring feedback only and must not affect correctness or scheduling.

## 10. Companion docs

- `prd/rubrics-core.md` — full A1–A10 acceptance criteria + worked examples.
- `prd/rubrics-frontend.md` — full B1–B5 criteria, desktop-objective vs iOS-demo split.
- `prd/contracts-and-data.md` — proto message contracts, data model, integration file paths, build/test/lint commands, sync-safety.
- `prd/build-spec.md` — seed content, phase ordering, cut order, **agentic-loop launch clarifications + config**, risks, open questions.
- `evidence/README.md` — self-contained rubric evidence artifacts (`determinism`, `ablation`, `paraphrase`, `undo`, `latency`).
- `PRD-tbs-shapes-future.md` — historical rationale for research-sim + document-review TBS surfaces; current implementation is in the shared core, desktop Svelte routes, and iOS Simulations views.

## Changelog

- v1 — 2026-06-30 — Initial draft (persona, Phase-1 scope, FAR seed, JE+numeric TBS, sync-safe Option A, per-feature rubrics).
- Cycle 1 — 2026-06-30 — 4-expert refine: proto contracts; A1 ramp; A2 rewritten rote-only pre-FSRS; A8 precedent+PRAGMA; pinned storage/abstain/AC inputs; 50k demoted; FR-6 hardened; OQ-4 resolved; OQ-5 added.
- v2 — 2026-06-30 — Restructured for `agentic-loop` (3 phase-simulations): split into lean loop-facing PRD + `prd/` companions; per-feature objective-acceptance bullets so the Contract phase (which never sees companions) has substance; fixed A2↔B1 phase-order bug (confidence via custom_data, tests seed it); iOS ACs made a non-gated demo checklist (objective contract = Rust + desktop-e2e); provenance stored-vs-populated disambiguated for the scope-guard; Phase-A-before-B encoded as `dependsOn`; timing ACs made non-gating; non-goals block prepared for `clarifications.nonGoals`.
- v3 — 2026-07-04 — Refreshed for shipped evidence/features: exam dates now persist through `SetExamDate`/`GetExamDate` settings notes; Readiness emits a CPA-scale band/center/coverage/reasons; evidence artifacts include undo integrity and release latency benchmark.
- v4 — 2026-07-06 — Refreshed for implemented research/document-review TBS surfaces, optional Learning Feedback runtime tutoring, and expanded iOS companion surfaces.
