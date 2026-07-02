# 0003. RAG stack & licensing posture for the 50k CPA question bank

Status: Accepted (plan; not yet built)
Date: 2026-07-01

## Context

Phase 2a (`docs_ankountant/brainlift_features.md`) is a build-time batch tool
that must grow the hand-authored demo seed into a **50,000-card** CPA question
bank across all six CPA-Evolution sections. Two assignment rules bind every
choice: **provenance-or-it-doesn't-count** (a card with no traceable source
zeroes the section) and **a wrong fact is worse than no card** (the quality gate
is pre-registered and RAG must beat a plain keyword/vector baseline).

The tool's shape is unusual: **offline, run-once-per-corpus-refresh, must be
reproducible and auditable** — not a low-latency online RAG service. That flips
the usual defaults (no always-on hosted vector DB, no serving cluster). The full
design lives in `docs_ankountant/rag/` (7 docs); this ADR records the two
choices that are **hard to reverse** and **surprising without the rationale**.

Genuine alternatives existed for each, so they are recorded as trade-offs rather
than defaults.

## Decision

**1. Stack — a Python batch pipeline (`tools/cardgen/`, not shipped in either
app):** ingest → chunk → **Voyage AI** embeddings → **LanceDB** (embedded
vector **+** BM25 full-text, versioned on disk) → retrieve (hybrid) → generate
with **Anthropic Claude** (Sonnet bulk / Opus for hard TBS + judge-flagged) →
**independent LLM judge + human gold set** (3-bucket gate) → **Ragas**
faithfulness + a **BM25 / vector / RAG baseline A/B/C** → emit **ordinary Anki
notes** (`genanki` → `.apkg`), provenance fields populated. Orchestration via
**LlamaIndex**.

The two hard-to-reverse calls:

- **LanceDB (embedded), not a hosted vector DB or pgvector.** The pipeline is a
  reproducible batch job; the index is a directory we version and snapshot next
  to the source corpus, and it ships vector **and** BM25 search in one store —
  so the two baselines the assignment requires and the hybrid retriever live in
  the same place. A hosted DB adds ops, cost, and reproducibility friction for no
  batch-time benefit. pgvector is kept as the escape hatch if the corpus later
  becomes a shared, collaboratively-edited asset.

- **Cite-don't-ingest licensing firewall.** Only **Tier-A** (public-domain / CC)
  material is ingested and paraphrased (OpenStax, IRC, IRS pubs, PCAOB/SEC/GAO,
  AICPA Blueprints as taxonomy). **Tier-B** copyrighted standards (FASB ASC,
  GASB, AICPA released questions) are **cited but never ingested or
  redistributed**. Provenance is therefore two-part: a verbatim Tier-A
  `source_passage` (internal audit) plus the standard citation (ASC/IRC §) shown
  to the candidate.

## Consequences

- **Reproducible & auditable by construction:** every card is reproducible from
  three pinned inputs (corpus snapshot sha256, LanceDB index version,
  `gen_method`), satisfying the provenance rule with a real audit chain.
- **The baseline A/B/C is cheap** because all three retrieval arms share one
  store — the only variable is the retrieval strategy.
- **Output is sync-safe:** cards are ordinary notes/decks/tags using the existing
  note types; no SQLite schema change (the Option-A constraint holds). The
  `Ankountant Study` note type gains provenance fields (a sync-safe note-type
  edit) so generated recall cards can carry provenance too.
- **Honest coverage, not a quota:** topics whose Tier-A corpus can't support N
  distinct grounded cards get fewer, logged as a shortfall — we never hallucinate
  to hit 50,000. Some standard-only niches will be thin; that is accepted.
- **Legal posture is a standing decision, not an engineering one.** If eval shows
  FAR/BAR grounding is materially capped by not ingesting ASC text, licensing the
  FAF ASC feed is the (paid) reversal path — revisit then, not now.
- **Runtime stays AI-off:** nothing here runs at study time; the study loop,
  scheduler, and scoring never call a model.

See `docs_ankountant/rag/README.md` and its linked docs for the full design.
