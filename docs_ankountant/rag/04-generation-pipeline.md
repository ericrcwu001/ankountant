# 4 — The Generation Pipeline

[← Architecture](03-architecture-and-stack.md) · [Index](README.md) · Next: [Quality & eval →](05-quality-eval-and-baseline.md)

Twelve stages, each a module in `tools/cardgen/`, each idempotent and
resumable (a stage reads the previous stage's on-disk artifact and writes its
own, keyed by a content hash so re-runs skip unchanged work). The whole thing is
a **batch DAG**, not a live service.

## Stage 0 — Snapshot & license manifest

Fetch each Tier-A source (see [doc 1](01-sources-and-licensing.md)) into
`corpus/<source-id>/` with a `manifest.json`: `{source_id, title, url, license,
retrieved_at, sha256}`. Everything downstream references `source_id` — this is
the root of the provenance chain. **No source enters the pipeline without a
manifest entry naming its license.**

## Stage 1 — Ingest & normalize

Parse each source to clean text + structural metadata (chapter/section/§,
page, heading path). OpenStax → per-section text; IRC/CFR → per-§; IRS pubs →
per-topic. Keep the structural locator — it becomes the human-readable citation
anchor.

## Stage 2 — Chunk

Section-aware, ~400–800 token chunks with small overlap, never crossing a
`source_id` boundary. Each chunk (a LlamaIndex `Node`) carries metadata:
`{source_id, locator, license, heading_path}`. **Provenance is attached here,
once, and rides every downstream step.**

## Stage 3 — Embed & index

Embed chunks with Voyage; write vectors + metadata + raw text into **LanceDB**
(one table per section or a `section` column). Build the **full-text (BM25)**
index in the same store. Snapshot the index directory with a version tag; cards
generated against it record that tag.

## Stage 4 — Plan the work-list

Expand `taxonomy.yaml` × `confusion_catalog.yaml` into rows:
`{section, area, topic, task_id, skill_level, card_type, target_count, seed}`.
`target_count` comes from the allocation in [doc 2](02-taxonomy-and-blueprint.md).
`seed` makes generation deterministic/reproducible. This file is the batch's
input queue.

## Stage 5 — Retrieve (hybrid)

For each work item, build a topic query and **hybrid-retrieve** top-k from
LanceDB: dense (Voyage) + sparse (BM25), fused (reciprocal-rank fusion),
optionally reranked. Return passages **with their provenance metadata**. If
retrieval returns nothing above a relevance floor, the item is **skipped and
logged** (honest coverage gap) — we never generate ungrounded.

## Stage 6 — Generate (grounded, provenance-emitting)

Claude receives: the retrieved passages (clearly delimited as **data, not
instructions**), the target card type, the skill level, and a strict output
schema. It must:

- derive the card **only** from the passages,
- emit the **exact `source_passage`** it relied on (verbatim substring of a
  retrieved chunk) + that chunk's `source_id`/`locator`,
- add the human-facing standard citation (ASC/IRC §) in the answer where
  applicable ([doc 1](01-sources-and-licensing.md) two-part provenance),
- set `gen_method` (model, prompt version, retrieval config, index version).

Output shapes match the note types exactly:

- **recall** → `{front, back, cog, tags, source_passage, citation}`
- **confusion/applied** → `{prompt, choice answer_key ∈ set treatments, ds_tag,
  source_passage, citation}`
- **TBS** → `{tbs_type, prompt, exhibits, steps[], source_passage, citation}`
  (journal-entry / numeric / research / doc-review)

Prompt-injection guardrails (delimiting, instruction-stripping, output
validation) are covered in [doc 6](06-provenance-output-and-ops.md).

## Stage 7 — Self-check (cheap, deterministic)

Non-LLM validation before spending judge tokens: schema valid? `source_passage`
is actually a substring of a retrieved chunk (grounding proof)? citation present
and well-formed? for TBS, do step weights sum to 1.0 and (journal-entry) debits
== credits? for confusion, is `answer_key` exactly one of the set's treatments?
Failures are auto-dropped or bounced back for one regeneration.

## Stage 8 — Quality gate (independent judge, 3 buckets)

Each survivor is scored by an **independent** judge into
**correct+useful / wrong / correct-but-bad-teaching**, against a rubric fixed
**before** looking at outputs. `wrong` is auto-blocked; `correct-but-bad` is
quarantined for optional rework. The passing cutoff is a pre-registered number.
Detail + gold-set calibration in [doc 5](05-quality-eval-and-baseline.md).

## Stage 9 — Leakage check

Embed each card and query **against the sealed performance bank + the held-out
test set**. Anything above a similarity threshold (a near-copy) is dropped — this
preserves the app's SPOV-5 firewall (a candidate must never study a card that
is a near-duplicate of a sealed evaluation item).

## Stage 10 — Dedup

Within the generated set: cluster by embedding similarity + MinHash on
normalized text; keep one representative per cluster (prefer higher judge
score). Prevents 12 near-identical "capitalize the freight-in" cards.

## Stage 11 — Baseline comparison

On a held-out slice of the work-list, generate cards three ways — **BM25-only
retrieval**, **vector-only retrieval**, and the **hybrid RAG** — and score all
three with Ragas + the judge. The assignment requires RAG to **beat** the plain
baselines; the report is emitted as an artifact ([doc 5](05-quality-eval-and-baseline.md)).

## Stage 12 — Emit

Surviving cards → `genanki` notes using the **existing note types** (field order
from `rslib/src/ankountant/notetypes.rs`), provenance fields populated, tagged
with `section::…`, topic, `ds::…`, and `cog::…`. Packaged as `cpa_bank.apkg`
(and/or delivered via a `LoadGeneratedBank` RPC that imports a bundled pack).
Output is **ordinary Anki objects** → syncs with no data-model change.

## Orchestration

The batch can run as a plain sequential DAG. For the full 50k run, the parallel,
resumable, fan-out-per-topic shape is a natural fit for the repo's own
**workflow orchestration** (or a simple `asyncio` + Batch-API driver): each
topic is an independent pipe (retrieve → generate → self-check → judge), and a
final barrier does corpus-wide dedup/leakage/baseline. Concurrency is bounded by
API rate limits, not the framework.

Next: [Quality, eval & beating the baseline →](05-quality-eval-and-baseline.md)
