# Ankountant — Domain Context (Glossary)

> Ubiquitous language for the Ankountant CPA-study fork. This file is a
> **glossary only** — no implementation detail, no spec, no decisions. Decisions
> live in `docs_ankountant/adr/`; feature intent in `docs_ankountant/`.

## Study content

- **Card** — one studyable item. Three kinds map to the three **modes**.
- **Recall flashcard** — classic front → reveal → self-rate. Atomic facts only.
  The only kind FSRS schedules directly. (Note type: `Ankountant Study`.)
- **Confusion item** — a label-stripped "which treatment applies?" question,
  scored on _discrimination_, not recall. Belongs to a **confusion set**.
- **TBS** (Task-Based Simulation) — a multi-step task graded objectively with
  **partial credit** (journal-entry, numeric, research, document-review). Not
  self-rated. (Note type: `Ankountant TBS`.)
- **Confusion set** — a named pair (or small group) of treatments candidates
  routinely confuse (e.g. _operating vs finance lease_). Identified by a
  `set_id`; its members are tagged with discriminating `ds::` tags.
- **Treatment** — one of the mutually-exclusive answers within a confusion set
  (e.g. "Capitalize" / "Expense").

## TBS (Task-Based Simulations)

- **TBS shape** — one of four structural forms a TBS takes: **journal-entry**,
  **numeric**, **research**, **document-review**. All four are stored in the one
  `Ankountant TBS` note type; each has its own playable surface.
- **TBS exam shell** — the shared split-screen chrome that hosts every TBS,
  mirroring the real exam: an **exhibits** pane, an **authoritative-literature**
  browser, a spreadsheet, and multi-part requirement tabs. All shapes render
  inside it; the literature browser is available on every TBS, not only research.
- **Exhibit** — a supporting document attached to a TBS (financial statements,
  memo, emails, contracts, trial balance) that the candidate consults to answer.
- **Authoritative literature** — the searchable body of standards a research task
  is answered against; **per section**: FAR/BAR → FASB ASC, AUD → AICPA + PCAOB
  standards, REG/TCP → the Internal Revenue Code, ISC → NIST/SOC/COBIT frameworks
  (SEC regs overlay several). Public-domain bodies (IRC, SEC, PCAOB, NIST) may be
  bundled verbatim; FASB ASC is cite-only (ADR 0006).
- **Research sim** — the TBS shape where you navigate the authoritative
  literature and submit the governing **citation**; scored on correctness (with
  time as a secondary signal) — a lookup skill, not recall.
- **Document-review sim** — the TBS shape presenting exhibits plus a document
  whose **blanks** are each a "which treatment applies?" choice; graded per blank
  with partial credit (reuses confusion-set logic).
- **Blank** — one gradable choice-slot in a document-review sim.
- **Citation** — the answer to a research sim (e.g. `ASC 842-20-25-1`), graded by
  normalized match against an accepted-citation list.

## Piles (the firewall)

- **Study pile** — cards the scheduler queues for normal FSRS review. Feeds
  **Memory**. _Not_ used to judge readiness.
- **Sealed bank** (a.k.a. **performance bank**) — items the scheduler **never**
  queues (suspended). A held-out measure. Feeds **Performance**. The separation
  is the firewall: a card you study must never be one you're also graded on.
- **Under-covered topic** — a confusion set with too little sealed/recall
  evidence to score honestly; it triggers the **give-up rule** at the _topic_
  level even while the overall score reports a band.

## Scores

All three scores are shown as **ranges**, never bare points.

- **Memory** — trailing-window recall accuracy on the **study pile** (per topic),
  shown with its **Memory band** (a Wilson confidence range).
- **Performance** — accuracy on the **sealed bank** only (MCQ + TBS partial
  credit). Never moved by study-pile activity. Shown with its **Performance
  band** (a Wilson confidence range).
- **Gap** — Memory − Performance. A positive gap = "you recall it but can't yet
  apply it under test conditions."
- **Readiness** — the exam-day projection, expressed on the **CPA scale** (0-99,
  75 = pass) as a band with a **point estimate**. The accuracy→CPA mapping is a
  documented heuristic (ADR 0005), explicitly labelled a rough projection — not
  the (non-public) official AICPA scaling.
- **Range / band** — the low–high interval a score is expressed as; it _widens_
  when evidence is thin. Never collapse it to a single number. Readiness's band
  is on the CPA scale; Memory/Performance bands are on their 0-100% accuracy.
- **Point estimate** — the centre of the Readiness band on the CPA scale; shown
  alongside the band, never instead of it.
- **Coverage** — the percent of the exam's confusion sets that have any sealed
  evidence yet. Always shown (even while abstaining) so the give-up state is
  legible.
- **Give-up rule** (a.k.a. **abstain**) — Readiness refuses to emit a band when
  evidence is under threshold (too few sealed attempts, or too few topics
  covered), reporting _why_ instead of guessing. "No readiness yet" is a valid,
  honest output.

## Content pipeline (Phase 2a)

- **Demo seed / demo profile** — the hand-authored FAR content **plus fake
  review/attempt history** loaded on demand so the review loop, Memory, and the
  Readiness band/give-up rule are all exercised on a fresh install. Sample data,
  not generated content.
- **Provenance** — the traceable origin of an AI-generated card: the exact
  **source passage** it was grounded in, how it was generated, and its checker
  verdict. A card with no traceable source is invalid.
- **Tier-A source** — public-domain / openly-licensed material we may ingest and
  paraphrase (OpenStax, IRC, IRS pubs, PCAOB/SEC/GAO). The generation corpus.
- **Tier-B source** — copyrighted standards (FASB ASC, GASB, AICPA questions) we
  may **cite but never ingest/redistribute**.
- **Leakage** — a generated study card being a near-copy of a **sealed bank** or
  held-out item; forbidden, because it would corrupt the firewall.

## Apps

- **Shared core** — the Rust engine (`rslib/`) both apps bind; the seed and all
  scoring live here, so both apps behave identically from one code path.
- **Desktop** — the PyQt app (macOS/Windows/Linux).
- **iOS** — the native SwiftUI app; consumes a compiled copy of the shared core.
