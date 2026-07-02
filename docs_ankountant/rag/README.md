# CPA Question-Bank at Scale — RAG Backlog Plan

> **Status:** Plan / not-yet-built. This is **Phase 2a** from
> [`../brainlift_features.md`](../brainlift_features.md) fully specified.
> It is an **offline, build-time batch tool** — the study loop never calls a
> model live (the "decouple build-time from runtime" split). The MVP ships on
> the hand-authored FAR demo seed (`rslib/src/ankountant/seed.rs`); this plan is
> how that seed grows into a **50,000-card** CPA question bank.

## Why this exists

The MVP seed is ~130 hand-authored FAR cards + a sealed bank + a handful of TBS
— enough to run the review loop and light up the readiness dashboard, but not a
real product. To be a credible CPA study tool we need broad, accurate coverage
of **all six CPA-Evolution sections** at exam depth. Hand-authoring 50k cards is
infeasible and error-prone; a **retrieval-augmented generation (RAG)** pipeline,
grounded in public-domain / openly-licensed source material and gated by an
independent quality checker, is the path.

Two hard rules from the assignment carry through every document here:

1. **Provenance or it doesn't count.** Every generated card stores the exact
   source passage it was grounded in + how it was generated + whether it passed
   the checker. _AI output with no traceable source zeroes that section._
2. **A wrong fact is worse than no card.** The quality gate is set **before**
   looking at results and auto-blocks anything that fails; RAG must **beat a
   plain keyword/vector baseline** on the eval.

## The decision, in one paragraph

Build a **Python, build-time batch pipeline** (`tools/cardgen/`, not shipped in
either app) that ingests **public-domain + Creative-Commons source corpora**
(OpenStax accounting texts, the Internal Revenue Code, Treasury regs & IRS
publications, PCAOB/SEC/GAO public standards, the AICPA Blueprints as taxonomy),
indexes them in **LanceDB** (embedded vector + full-text store) using **Voyage AI
embeddings**, and generates cards with **Anthropic Claude** constrained to
retrieved passages. An **independent LLM judge (different model)** plus a
human-verified gold set enforces the 3-bucket quality gate; **Ragas** measures
faithfulness/relevancy and proves the RAG-vs-baseline win. Copyrighted standards
(FASB ASC, GASB, AICPA questions) are **cited, never ingested/redistributed**.
Surviving cards are emitted as **ordinary Anki notes** (the existing
`Ankountant Study` / `Ankountant TBS` note types, provenance fields populated),
so they sync with zero data-model change.

## Document map

Read in order; each links onward.

| # | Doc                                                                  | What it settles                                                                                                      |
| - | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 1 | [`01-sources-and-licensing.md`](01-sources-and-licensing.md)         | Which corpora we may ingest vs only cite; the copyright firewall                                                     |
| 2 | [`02-taxonomy-and-blueprint.md`](02-taxonomy-and-blueprint.md)       | The CPA-Evolution section/topic taxonomy and how 50,000 is allocated                                                 |
| 3 | [`03-architecture-and-stack.md`](03-architecture-and-stack.md)       | The RAG service choice: Claude + Voyage + LanceDB + LlamaIndex + Ragas, and why                                      |
| 4 | [`04-generation-pipeline.md`](04-generation-pipeline.md)             | The 12-stage ingest → retrieve → generate → gate → emit pipeline                                                     |
| 5 | [`05-quality-eval-and-baseline.md`](05-quality-eval-and-baseline.md) | Gold set, 3-bucket gate, Ragas metrics, beat-the-baseline protocol, leakage & dedup                                  |
| 6 | [`06-provenance-output-and-ops.md`](06-provenance-output-and-ops.md) | Provenance fields, note-type mapping, delivery (.apkg/RPC), cost model, reproducibility, prompt-injection guardrails |

## Decisions still worth a human sign-off

These are recommended with rationale in the linked docs, but are the ones most
worth confirming before any build spend:

- **Generation model tier** — Sonnet for bulk generation + Opus/independent
  judge on flagged & sampled cards (cost vs accuracy). See doc 3 & 6.
- **Vector store** — LanceDB (embedded, reproducible, zero-ops) vs Postgres +
  pgvector (if we want to reuse a shared server later). See doc 3.
- **Licensing posture** — the "cite-don't-ingest" firewall around FASB ASC is a
  legal call, not just an engineering one. See doc 1.

## Relationship to the rest of the repo

- **Runtime is untouched.** No app code calls a model. Cards are data.
- **Sync-safe by construction.** Output is ordinary notes/decks/tags/config —
  the same Option-A constraint the MVP already honors (see
  `../brainlift_features.md`). No new SQLite tables or columns.
- **Feeds the sealed bank & three modes.** Generated recall cards → study pile;
  applied/confusion items → sealed bank; TBS items → the TBS surface. The
  taxonomy (doc 2) maps blueprint skill levels to card types.
