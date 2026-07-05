# CPA Question-Bank at Scale — RAG Backlog Plan

> **Status:** Built & live-proven (`proof3`) with an importable template deck
> (`tmpl4`) and a sharded stress-test pack. This is **Phase 2a** from
> [`../brainlift_features.md`](../brainlift_features.md). It is an **offline,
> build-time batch tool** (`tools/cardgen/`) — the study loop never calls a model
> live (the "decouple build-time from runtime" split). The MVP seeds an
> inclusive CPA demo profile (`rslib/src/ankountant/seed.rs` plus the desktop
> CPA-bank loader); this pipeline grows it toward a **50,000-card** CPA question
> bank.
>
> **As-built (read these first):** the shipped stack + licensing deltas are in
> [`../adr/0009-rag-cardgen-lean-stack-cursor-judge-tier-b.md`](../adr/0009-rag-cardgen-lean-stack-cursor-judge-tier-b.md);
> the latest RAG run's numbers + evidence are in [`RAG_RUN_RESULTS.md`](RAG_RUN_RESULTS.md);
> the importable template deck and stress-pack notes are in
> [`TEMPLATE_DECK_RESULTS.md`](TEMPLATE_DECK_RESULTS.md);
> the operational state is in [`HANDOFF.md`](HANDOFF.md). Docs **01–07** below are
> the design reference — **ADR 0009 supersedes their stack/licensing specifics**.

## Why this exists

The MVP seed and one-click CPA-bank loader provide starter coverage across the
visible CPA sections — enough to run the review loop and light up the readiness
dashboard, but not a real product. To be a credible CPA study tool we need
broad, accurate coverage of **all six CPA-Evolution sections** at exam depth.
Hand-authoring 50k cards is
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

A **Python, build-time batch pipeline** (`tools/cardgen/`, not shipped in either
app) ingests source corpora (OpenStax accounting texts, IRS publications & Treasury
regs, the NIST SP 800-series, the AICPA Blueprints as taxonomy, plus personal-use
CPA-review material — see ADR 0009), indexes them in **LanceDB** (embedded vector
**and** BM25) using OpenAI **`text-embedding-3-small`** embeddings, and generates
cards with OpenAI **`gpt-5-mini`** (v2 decline prompt) constrained to retrieved
passages. An **independent judge — batched Cursor subagents**, a different provider
_and_ model from the generator — plus a **human-verified gold set** enforces the
3-bucket quality gate; a chunk-keyed **A/B/C baseline** proves the hybrid-RAG win
over plain keyword/vector retrieval. The judge is itself gated: the `gold` stage
calibrates it against the gold set (positives + planted negatives) and **halts the
run if it can't be trusted**. Surviving cards are emitted as **ordinary Anki notes**
(`Ankountant Study` / `Ankountant TBS`, provenance fields populated), so they sync
with zero data-model change.

The 50k **stress pack** is separate: `just cardgen-stress` duplicates the
current emitted packs into `stress_bank_part*.apkg` shards under
`Ankountant::Stress::`, tagged `stress` and `dup::<n>`. It exists only to test
import, rendering, search, and dashboard scale; it is not unique generated study
content.

## Document map

Read in order; each links onward.

| # | Doc                                                                  | What it settles                                                                                                      |
| - | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 1 | [`01-sources-and-licensing.md`](01-sources-and-licensing.md)         | Which corpora we may ingest vs only cite; the copyright firewall                                                     |
| 2 | [`02-taxonomy-and-blueprint.md`](02-taxonomy-and-blueprint.md)       | The CPA-Evolution section/topic taxonomy and how 50,000 is allocated                                                 |
| 3 | [`03-architecture-and-stack.md`](03-architecture-and-stack.md)       | Original stack choice (Claude + Voyage + LanceDB + Ragas) — **as-built is ADR 0009** (OpenAI + Cursor judge)         |
| 4 | [`04-generation-pipeline.md`](04-generation-pipeline.md)             | The 12-stage ingest → retrieve → generate → gate → emit pipeline                                                     |
| 5 | [`05-quality-eval-and-baseline.md`](05-quality-eval-and-baseline.md) | Gold set, 3-bucket gate + judge calibration, beat-the-baseline protocol, leakage & dedup                             |
| 6 | [`06-provenance-output-and-ops.md`](06-provenance-output-and-ops.md) | Provenance fields, note-type mapping, delivery (.apkg/RPC), cost model, reproducibility, prompt-injection guardrails |
| 7 | [`07-implementation-contract.md`](07-implementation-contract.md)     | The build contract the implementation follows (stages, artifacts, interfaces)                                        |

## Decisions (resolved in ADR 0009)

The open calls from the original design are now settled for this personal-use build
(full rationale in [`../adr/0009-rag-cardgen-lean-stack-cursor-judge-tier-b.md`](../adr/0009-rag-cardgen-lean-stack-cursor-judge-tier-b.md)):

- **Generation + judge** — OpenAI `gpt-5-mini` generates; **batched Cursor
  subagents** judge (independent provider + model). The offline path uses a
  deterministic keyless judge so CI/tests reproduce; the `gold` stage calibrates
  the judge before the gate is trusted.
- **Embeddings + store** — OpenAI `text-embedding-3-small` in **LanceDB**
  (embedded, reproducible; vector + BM25 supply two of the three baseline arms).
- **Licensing posture** — Tier-B CPA material **may be ingested** for this
  personal-use build; generated cards are **not redistributable**. If this ever
  ships publicly, revert to the Tier-A-only firewall (ADR 0003).

## Relationship to the rest of the repo

- **Runtime is untouched.** No app code calls a model. Cards are data.
- **Sync-safe by construction.** Output is ordinary notes/decks/tags/config —
  the same Option-A constraint the MVP already honors (see
  `../brainlift_features.md`). No new SQLite tables or columns.
- **Feeds the sealed bank & three modes.** Generated recall cards → study pile;
  applied/confusion items → sealed bank; TBS items → the TBS surface. The
  taxonomy (doc 2) maps blueprint skill levels to card types.
