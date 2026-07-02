# 3 — Architecture & Stack (the "what service" decision)

[← Taxonomy](02-taxonomy-and-blueprint.md) · [Index](README.md) · Next: [Pipeline →](04-generation-pipeline.md)

This doc answers the explicit question — **what do we build the RAG with** — and
justifies each choice against this project's unusual shape: an **offline,
build-time, run-once-per-corpus-refresh batch job** that must be **reproducible,
auditable, and provenance-first**, not a low-latency online service.

That shape flips several defaults. We do **not** want an always-on hosted vector
DB, a serving cluster, or a streaming RAG chain. We want a deterministic Python
job that reads a source snapshot + a taxonomy and writes a versioned card set.

## Stack at a glance

| Layer                  | Choice                                                                                                                | Why (short)                                                                                           |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Language / runner      | **Python 3.12 batch tool** in `tools/cardgen/`                                                                        | Not shipped in either app; matches existing pylib tooling; best RAG ecosystem                         |
| Orchestration          | **LlamaIndex**                                                                                                        | Ingestion + node/metadata (provenance) model + retrievers + eval, all first-class                     |
| Embeddings             | **Voyage AI** (`voyage-3-large`, `voyage-3` for bulk)                                                                 | Anthropic-recommended; strong retrieval; cheap; 32k context                                           |
| Vector + keyword store | **LanceDB** (embedded)                                                                                                | File-based, versioned, zero-ops; vector **and** BM25/full-text in one store → both baselines for free |
| Generation LLM         | **Anthropic Claude** — Sonnet (bulk) / Opus (hard TBS + flagged)                                                      | Accuracy-critical accounting; repo is Claude-first; Batch API + prompt caching                        |
| Quality judge          | **Independent model** (Claude Opus with a distinct rubric prompt; optionally a cross-provider judge) + human gold set | Avoid self-grading bias on the gate                                                                   |
| Eval                   | **Ragas** (faithfulness, answer/context relevancy, context precision/recall) + custom retrieval metrics               | Quantifies quality and the RAG-vs-baseline win                                                        |
| Dedup / leakage        | **LanceDB ANN** + MinHash/SimHash                                                                                     | Embedding-similarity + near-duplicate text                                                            |
| Output                 | **`genanki`** → `.apkg`, or a `LoadGeneratedBank` RPC                                                                 | Ordinary Anki notes; sync-safe                                                                        |

## Why these, specifically

### Vector store — LanceDB (recommended) vs pgvector

The decisive property is **reproducibility + zero ops** for a batch job.

- **LanceDB** is an embedded, columnar, on-disk store (like "SQLite for
  vectors"). The index is a _directory you can version and snapshot_ alongside
  the source corpus — so a card's provenance can point at an exact index
  version. It stores arbitrary metadata columns next to vectors (our provenance),
  scales to tens of millions of rows on a laptop, and ships **native full-text
  (Tantivy) search** — meaning the **BM25 baseline** and the **vector baseline**
  needed by the assignment live in the _same_ store as the hybrid retriever. No
  server, no container, no per-hour cost.
- **Postgres + pgvector** is the alternative _if_ we later want a shared,
  queryable, multi-writer corpus (e.g. a team curating sources). It's heavier to
  stand up and snapshot for a reproducible build. **Recommendation:** LanceDB
  now; keep pgvector as the escape hatch if the corpus becomes a shared,
  long-lived, collaboratively-edited asset.

> Not recommended here: Pinecone / Weaviate / Qdrant-cloud (managed, always-on,
> monthly cost, harder to snapshot for reproducibility). Great for online RAG;
> wrong tool for a reproducible offline batch.

### Embeddings — Voyage AI

Voyage is Anthropic's recommended embedding provider and consistently strong on
retrieval benchmarks, with long context (good for whole-section OpenStax
passages) and low cost. **Fallback:** OpenAI `text-embedding-3-large`. A
domain-tuned embedding (fine-tune on accounting pairs) is a _later_ optimization,
justified only if eval shows retrieval is the bottleneck.

### Generation — Claude, tiered

- **Bulk generation: Claude Sonnet.** Capable on CPA content, and with the
  **Batch API (≈50% off)** + **prompt caching** (the retrieved passages and the
  rubric are cached across a topic's many cards) the 50k run is affordable
  (see cost model in [doc 6](06-provenance-output-and-ops.md)).
- **Hard items + escalation: Claude Opus.** TBS numeric/journal-entry items
  (where arithmetic must be exact) and any card the judge flags get regenerated
  or checked at Opus. This is the "delegate easy to the cheaper tier, hard
  judgment to the stronger one" split.

### Orchestration — LlamaIndex (vs LangChain / custom)

LlamaIndex's ingestion pipeline, **node metadata** (our provenance rides on every
chunk automatically), retriever abstractions, and built-in **RAG evaluation**
packs map directly onto our stages. LangChain would also work; LlamaIndex wins
on retrieval-eval ergonomics and a lighter mental model for a batch job. A thin
custom pipeline is viable but re-implements chunking/eval we'd get for free.

### Quality judge — independence matters

Using the _generator_ to grade its own output inflates pass rates. The gate uses
(a) a **human-verified gold set** and (b) an **independent judge** — a different
model or at least a different model tier with a distinct rubric — plus Ragas
faithfulness scored against the _retrieved_ context. Detail in
[doc 5](05-quality-eval-and-baseline.md).

## Data-flow diagram

```
              ┌─────────────────────── build-time, offline ───────────────────────┐
Tier-A corpus │  ingest → chunk → embed(Voyage) → LanceDB (vectors + FTS + meta)   │
(OpenStax,    │                                        │                            │
 IRC, IRS,    │   taxonomy.yaml ─► work-list ─► retrieve(hybrid top-k) ─► Claude    │
 PCAOB, SEC)  │        confusion_catalog.yaml           │        (grounded gen)     │
              │                                         ▼                            │
              │   self-check ─► independent judge (3-bucket gate) ─► Ragas eval     │
              │        │                    │                          │             │
              │   leakage vs sealed bank ─► dedup ─► baseline compare (BM25/vector) │
              │                                         │                            │
              │                              genanki → cpa_bank.apkg  (ordinary     │
              │                              notes, provenance fields populated)     │
              └─────────────────────────────────────────┼────────────────────────────┘
                                                         ▼
                        app imports .apkg  →  syncs as normal notes (Option A)
                        (runtime NEVER calls a model — study loop is AI-off)
```

## Repo placement

```
tools/cardgen/                 # new; NOT part of the shipped wheels/xcframework
  pyproject.toml
  taxonomy/                    # taxonomy.yaml, confusion_catalog.yaml per section
  corpus/                      # source snapshots + license manifest
  cardgen/
    ingest.py  chunk.py  index.py  retrieve.py  generate.py
    judge.py   evaluate.py  leakage.py  dedup.py  emit.py
  gold/                        # human-verified gold sets per section
  out/                         # versioned LanceDB index + generated .apkg
```

It reuses the repo's proto/note-type definitions only as an **output contract**
(the field order in `notetypes.rs`), never as a runtime dependency.

Next: [The generation pipeline →](04-generation-pipeline.md)
