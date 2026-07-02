# 0007. TBS as a shared exam-shell hosting all four shapes

Status: Accepted
Date: 2026-07-02

## Context

The MVP shipped journal-entry + numeric TBS as standalone surfaces and deferred
research + document-review (`PRD-tbs-shapes-future.md`). Finishing the deferred
shapes forced a scope question: bolt on two more standalone surfaces, or build
the shared chrome the real exam uses.

On the Prometric CPA exam every TBS runs inside **one shell** — a split-screen
with an **exhibits** pane, an **authoritative-literature** browser, a scratch
**spreadsheet**, and multi-part **requirement tabs** — and the literature browser
is available on ALL TBS, not just research items. Ankountant already has a
single-window **tiling workspace** (ADR 0002) onto which such a split-screen maps
naturally. A stated product differentiator is **interface-fluency** (candidates
"who know the content but freeze on the software"), so shell fidelity is a
product goal, not gold-plating.

Options:

1. **Bolt-on surfaces** — two more standalone screens; least effort; JE/numeric
   stay basic; no shared exhibits/literature/spreadsheet; low interface-fluency
   fidelity.
2. **Full exam-shell** — one shared shell hosting all four shapes; highest
   fidelity; larger build; upgrades JE/numeric for free.

## Decision

**Build a shared TBS exam shell and render all four shapes inside it.**

- Shell chrome: exhibits pane, authoritative-literature browser (corpus per
  ADR 0006), lightweight scratch spreadsheet (ungraded), multi-part requirement
  tabs, and the pre-reveal confidence gate.
- Composes onto the tiling workspace (ADR 0002): exhibits/literature can be their
  own tileable panes beside the work pane.
- All shapes (JE, numeric, research, doc-review) become **surfaces** inside the
  shell; the existing JE/numeric surfaces are migrated into it.
- Grading stays on the existing step-graded path (`SubmitPerformanceAttempt`);
  the sync-safe (no new tables/columns) and append-only-proto constraints are
  unchanged.

## Consequences

- Larger initial build (shell + two new surfaces + spreadsheet + corpus), but one
  coherent architecture and a real interface-fluency win.
- JE/numeric gain exhibits + literature + spreadsheet for free.
- The literature browser is **shell-level** (available on every TBS), matching
  the real exam rather than being research-only.
- Implementation proceeds on an isolated branch (`tbs-surfaces`) / git worktree,
  test-gated (`just check` green) before any merge, so it does not disrupt
  parallel work on `main`.
