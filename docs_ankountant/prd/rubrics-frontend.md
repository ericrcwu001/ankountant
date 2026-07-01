# Phase B — Frontend rubrics (B1–B5)

> Full acceptance criteria for the Phase-B features listed in `../PRD.md`. **Every B feature depends on Phase A being complete** (shared core + the 4 new RPCs), so each carries `dependsOn` pointing at the Phase-A features it consumes. Desktop and iOS are built as **parallel tracks on disjoint files** (`qt/`+`ts/` ∥ `ios/`).
>
> **Objective-gate split (important for the agentic-loop ship gate).** The loop's ship condition is objective-only; assertions that can't be run mechanically are dropped. So:
>
> - **Desktop ACs are the objective contract** — each carries a specific Playwright spec as its verify command (`just test-e2e` / a named spec), plus `test-ts` where a DTO/unit check applies.
> - **iOS ACs are a non-gated demo checklist** — there is no Playwright-equivalent for iOS and SwiftUI XCTest for these flows isn't wired, so iOS is verified by XCTest-at-the-client-layer where feasible + manual demo. **iOS ACs must NOT be entered as objective contract assertions** (they'd be dropped and could let the loop "PASS" with iOS unbuilt). Track iOS completion here and in `progress.md`, not in `contract.md`.
>
> Desktop reviewer seams: `ts/reviewer/index.ts` (`_showQuestion`/`_showAnswer`), `ts/reviewer/answering.ts`, `qt/aqt/reviewer.py`, new Svelte routes under `ts/`. e2e loads the FAR seed (see `build-spec.md` for seed-load in the Playwright fixture). iOS seams: SwiftUI Review/Stats views in `ios/AnkountantApp/`, backend via `ios/Sources/AnkiBackend/AnkiBackend.swift` (hand-maintained indices — resync after Phase-A proto changes, see `contracts-and-data.md`).

---

## B1 — Attempt-before-reveal + confidence capture (SPOV 2) · P0 · depends: A8 (+A10 for Performance modes)

**Behavior (pinned):** the reveal is blocked until the user commits a discrete 3-level confidence — **Guess / Unsure / Confident** — pre-reveal. Confidence flows into `SubmitPerformanceAttempt` (Performance modes) and mirrors to `card.custom_data` (recall mode — this is the scalar A2 reads).
**Desktop (objective contract):**

- [ ] B1-D1 — the answer/back cannot be shown until a confidence is committed. _(test-e2e)_
- [ ] B1-D2 — committed confidence is persisted (Attempt Log for Performance modes; `custom_data` for recall) and visible to `GetReadiness`. _(test-e2e + test-rust)_
- [ ] B1-D3 — the three levels render and are keyboard-selectable. _(test-e2e)_
      **iOS (demo checklist, non-gated):** pre-reveal confidence step blocks reveal; three levels tappable; confidence persists. _(XCTest at client layer where feasible + manual demo)_
      **Done when:** no reveal without a committed pre-reveal confidence — desktop gated by e2e; iOS by demo.

---

## B2 — "Which treatment applies?" gate (SPOV 4) · P0 · depends: A3, A10, B1

**Behavior (pinned):** a pre-computation choice step in the confusion-set flow. The item is shown label-stripped (no topic/deck name); the user picks among the confusion set's candidate treatments before any numeric entry; the choice is graded (A10) and logged (A8).
**Desktop (objective contract):**

- [ ] B2-D1 — the `BuildConfusionQueue` item DTO has no populated topic/category/deck-label field, and the gate renders no element with `data-testid="category-label"`. _(test-rust on DTO + test-e2e asserting the element is absent)_
- [ ] B2-D2 — selecting a treatment submits it and shows correct/incorrect scored on discrimination. _(test-e2e)_
- [ ] B2-D3 — the attempt appears in the Attempt Log and moves the topic's Performance/gap. _(test-e2e + test-rust)_
      **iOS (demo checklist, non-gated):** label-stripped treatment picker before computation; grades + logs. _(manual demo)_
      **Done when:** discrimination is gated and scored before computation, label-free — desktop gated by e2e.

---

## B3 — Confusion-set review mode (SPOV 4) · P0 · depends: A3, B1, B2

**Behavior (pinned):** a mode entry point that calls `BuildConfusionQueue` (A3) and drives B1+B2 per item.
**Desktop (objective contract):**

- [ ] B3-D1 — entering the mode fetches and plays the interleaved queue; consecutive items are not all the same treatment. _(test-e2e)_
- [ ] B3-D2 — each item runs confidence capture (B1) + which-treatment gate (B2). _(test-e2e)_
- [ ] B3-D3 — completing the queue updates the topic Performance shown on the dashboard (B5). _(test-e2e)_
      **iOS (demo checklist, non-gated):** full confusion-set session runs end-to-end. _(manual demo)_
      **Done when:** a full confusion-set session runs end-to-end — desktop gated by e2e.

---

## B4 — TBS review surface: journal-entry + numeric (SPOV 6) · P0 · depends: A9, A10

**Behavior (pinned):** a NEW screen distinct from the card reviewer (desktop: new Svelte route under `ts/`; iOS: new SwiftUI view). Renders `Ankountant TBS` notes (A9), shows an exhibits pane, submits via `SubmitPerformanceAttempt(mode=tbs)` (A10). JE = editable grid (account / debit / credit rows); numeric = input cells / dropdowns. On submit, per-step correctness + partial-credit total shown. Basic exhibits pane in scope; full split-screen "interface-fluency sim" is a stretch (see `build-spec.md`).
**Desktop (objective contract):**

- [ ] B4-D1 — a JE TBS renders an editable multi-row grid; a partially-correct submission shows per-line right/wrong and a partial-credit total matching A10. _(test-e2e, reconciled with A10 test-rust)_
- [ ] B4-D2 — a numeric TBS renders input cells graded per cell with tolerance. _(test-e2e)_
- [ ] B4-D3 — the surface is NOT the flashcard reviewer and exposes NO Again/Hard/Good/Easy buttons. _(test-e2e asserting those controls are absent)_
- [ ] B4-D4 — exhibits referenced by the TBS are visible alongside the task. _(test-e2e)_
      **iOS (demo checklist, non-gated):** JE grid + numeric cells playable, step-graded, exhibits visible. _(manual demo)_
      **Done when:** JE + numeric TBS are playable and step-graded — desktop gated by e2e.

---

## B5 — Three-score dashboard (SPOV 5 + 3) · P0 · depends: A4, A5

**Behavior (pinned):** a dashboard reading `GetReadiness` (A4/A5). Shows per-topic Memory vs Performance with the gap highlighted; Readiness as a band + confidence, labeled the exam-day projection (not "today"); when `abstain==true`, shows the abstain message + reason instead of any number.
**Desktop (objective contract):**

- [ ] B5-D1 — with sufficient data, shows Memory, Performance, gap, and a Readiness band (low–high) + confidence — never a single number. _(test-e2e)_
- [ ] B5-D2 — with thin data (A5 thresholds unmet), shows the abstain message + reason and NO readiness number. _(test-e2e)_
- [ ] B5-D3 — gap ≥ 0.25 (e.g., memory 0.90, performance 0.65) → the gap row renders with the `gap-warning` style class. _(test-e2e asserting the class is present)_
- [ ] B5-D4 — Readiness is labeled the exam-day projection tied to the set exam date. _(test-e2e)_
      **iOS (demo checklist, non-gated):** same three scores + gap + abstain + exam-day band render. _(manual demo)_
      **Done when:** the honest 3-score readout — including abstain — renders on desktop (gated) and iOS (demo).
