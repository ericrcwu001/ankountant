# 0009. RAG cardgen — lean provider stack, Cursor-subagent judge, Tier-B ingestion

Status: Accepted
Date: 2026-07-02

## Context

ADR 0003 fixed the _design_ of the Phase-2a card-generation pipeline (the full
plan lives in `docs_ankountant/rag/`). It assumed a premium, generic RAG stack —
**Voyage** embeddings, **Anthropic Claude** (Sonnet/Opus) generation, a hosted
**independent judge**, and a **cite-don't-ingest** copyright firewall around
Tier-B material — sized for a public product and a ~$500–1,200 full run.

Building it now, for a **personal-use** study tool, under a tight budget and with
existing **Cursor + OpenAI** access, changes several of those calls. This ADR
records only the deltas from ADR 0003 that are **hard to reverse** or
**surprising without the rationale**. The 12-stage pipeline shape, the
provenance rule, the 3-bucket gate, leakage/dedup, and the beat-a-baseline
requirement are all **unchanged** from `docs_ankountant/rag/`.

## Decision

1. **Lean provider stack (replaces the premium one).**
   - Generation: **OpenAI `gpt-5-mini`** primary, with **`gpt-4o` fallback**
     (was Claude Sonnet/Opus). Retrieval reranking uses **`gpt-4o-mini`** when
     live rerank is enabled.
   - Embeddings: **OpenAI `text-embedding-3-small`** (was Voyage).
   - Vector + keyword store: **LanceDB** (vector **and** BM25) — _unchanged_; it
     still provides two of the three baseline arms for free.
   - Orchestration: a **thin custom pipeline** (LlamaIndex optional, not
     required).
   - A **pluggable provider interface** (embedder / generator / judge) with a
     **deterministic OFFLINE backend** so `just`/CI run **keyless**. Live keys
     come from a **gitignored** `tools/cardgen/.env` (`OPENAI_API_KEY`), never
     committed, never logged.

2. **Judge = in-session Cursor subagents (not a hosted API, not the generator).**
   Every card is scored by **batched Cursor subagents** the operator drives from
   a Cursor session (≈25 cards per subagent, against the fixed rubric and the
   retrieved passage). Independence — the anti-self-grading rule — is preserved
   by a **different provider _and_ model** (OpenAI generator vs Cursor judge).
   **Consequence:** the judge stage is **not headless**; the full-50k run is
   resumable but its gate step requires a Cursor session.

3. **Tier-B ingestion permitted for this personal-use build (reverses the ADR
   0003 firewall).** Copyrighted CPA material — `CPA Exam For Dummies`, the TBS
   PDFs (`60.pdf.pdf`, `FAR TBS.pdf`), and standards excerpts where needed — **may
   be ingested, chunked, embedded, and used to ground generation**. Provenance is
   unchanged: every card keeps a verbatim `source_passage` + a citation. The
   generated `.apkg` is a **personal artifact and is not publicly
   redistributable.**

4. **Cost posture.** Low-cost OpenAI generation + Cursor judge keeps the bounded
   proof cheap and leaves the full 50k run as a resumable Batch-API-capable
   scale-up; judging rides the Cursor subscription. Executed as a **bounded live
   proof across all six sections now** + a **one-command, resumable scale-up** to
   the full 50k.

## Consequences

- **Cheap and key-light:** reuses existing OpenAI + Cursor access; offline tests
  need no secrets.
- **Reproducibility becomes _semantic_, not bitwise:** `gen_method` pins model +
  prompt version + retrieval config + index version + seed; re-runs reproduce
  equivalent (not byte-identical) cards.
- **Judge independence** is kept via provider+model separation, at the cost of a
  **non-headless** gate step (accepted).
- **Licensing:** this is a **personal-use** posture. ADR 0003's firewall no
  longer constrains _ingestion_, but **redistribution of generated content is off
  the table**. If this ever ships publicly, revert to ADR 0003's Tier-A-only
  ingestion.
- **Runtime stays AI-off:** nothing here runs at study time; cards are static
  data imported as ordinary notes (Option A).

## Addendum — scale-up (ship-rate + 50k throughput)

Implementing the `improve_rag_retrieval_and_generator` plan refined a few stack
choices (no reversal of the above):

- **Generator → `gpt-5-mini`** (a reasoning model) with a **model-aware** chat
  API (omit `temperature`/`seed`; use `max_completion_tokens` + `reasoning_effort`)
  and a **`gpt-4o` fallback** on 404/no-access. A **v2 prompt** adds a _decline
  rule_ (`{"skip": true}` when the passages can't ground a faithful card), bans
  schema placeholders, and requires TBS numbers to come from the passage — "a
  wrong card is worse than no card", enforced at generation, not just judging.
- **Retrieval quality:** a Stage-2 **chunk-quality filter** (drop
  heading/stub/TOC/table/bare-stem chunks) + a **richer query** (confusion-set
  treatments) + a **hybrid-arm reranker** (cheap LLM live; deterministic lexical
  fallback offline).
- **Throughput:** live generation runs under a **bounded-concurrency asyncio
  driver** or the **OpenAI Batch API** (~50% cheaper), with concurrent embeddings.
  The **offline** backend stays sequential + deterministic, and generation is
  **resumable/idempotent** so a 50k run continues after interruption.
- **Judging at scale:** the batched Cursor-subagent queue gains a **wave plan**
  (`queue/plan.json`, N subagents/wave) and an optional **sampled-audit gate**
  (`judge_mode=audit`): judge a deterministic statistical sample + rely on the
  deterministic self-check to gate the remainder, keeping the 50k gate tractable
  while still measuring the wrong-rate.

Cost posture is unchanged in shape; the Batch API path lowers the full-run OpenAI
spend. Judge independence (provider+model separation) and the personal-use
licensing posture are unchanged.

## Addendum — template (Automatic Item Generation) mode

A second generation mode complements RAG: `--mode template` expands curated
templates x source-pinned data rows into cards with **no per-card LLM call**
(`cardgen/templates.py`), then reuses the same gate
(`selfcheck -> gold -> judge -> leakage -> dedup -> emit`).

- **Grounding without retrieval.** Each data row pins a verbatim `source_passage`
  that must be a substring of its source's `00-ingest` text; numeric answers are
  computed from a deterministic formula registry. So cards are traceable to a
  named source (rubric requirement) even though no model wrote them.
- **Same quality bar.** Template cards still pass the independent 3-bucket judge;
  in practice the judge caught real curation bugs (a mis-scoped tax range; research
  exhibits that revealed their own citation), which were fixed before shipping.
- **Licensing per row.** `gen_method.license` is `public` (IRS/NIST/OMB/Treasury —
  redistributable) or `personal_use` (Tier-B grounded); a public pack excludes the
  latter.
- **Scope.** Value tracks curated data, not free generation — best for tax
  thresholds/phase-outs and citation registries. It does not change the RAG stack
  or the licensing posture above.

Supersedes the stack/licensing specifics of ADR 0003 for the personal-use build;
ADR 0003 remains the reference for the public-product posture.
