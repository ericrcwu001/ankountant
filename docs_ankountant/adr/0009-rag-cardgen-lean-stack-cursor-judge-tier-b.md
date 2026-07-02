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
   - Generation: **OpenAI `gpt-4o-mini`** (was Claude Sonnet/Opus).
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

4. **Cost posture.** `gpt-4o-mini` gen + Cursor judge ⇒ OpenAI spend ≈ **$1–2
   (bounded proof)** / **≈ $45 (full 50k, ~$22 with Batch API)**; judging rides
   the Cursor subscription. Executed as a **bounded live proof across all six
   sections now** + a **one-command, resumable scale-up** to the full 50k.

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

Supersedes the stack/licensing specifics of ADR 0003 for the personal-use build;
ADR 0003 remains the reference for the public-product posture.
