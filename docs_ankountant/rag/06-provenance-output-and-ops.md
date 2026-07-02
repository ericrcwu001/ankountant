# 6 — Provenance, Output & Ops

[← Quality & eval](05-quality-eval-and-baseline.md) · [Index](README.md)

Where the pipeline meets the app, and what it costs to run.

## Provenance (the assignment's hard rule)

_AI output with no traceable source zeroes that section._ Provenance is
**two-part** (see [doc 1](01-sources-and-licensing.md)):

1. **Audit trail (internal):** the exact **Tier-A `source_passage`** the card was
   grounded in — a verbatim substring of a retrieved chunk — plus its
   `source_id` + `locator` + `index_version`. Self-check (stage 7) _proves_
   grounding by confirming the passage is a real substring of a retrieved chunk.
2. **Candidate-facing citation:** the authoritative standard reference
   (`ASC 606-10-25`, `IRC §168(k)`, `PCAOB AS 2301`) shown in the answer, so a
   studying candidate can go read the source.

The existing note types already reserve the audit fields:

- **`Ankountant TBS`** (`notetypes.rs::tbs_fields`) has
  `source_passage` (5), `gen_method` (6), `checker_status` (7) — populated by
  this pipeline (they are intentionally empty in the hand-authored seed).
- **`Ankountant Study`** currently has only `Front`/`Back`. **Recommendation:**
  extend it with the same three provenance fields for _generated_ recall cards
  (hand-authored seed cards leave them blank). Adding fields to a note type is
  **sync-safe** — note types replicate as ordinary objects; no SQLite schema
  change (the Option-A constraint holds).

`gen_method` encodes reproducibility: `{model, prompt_version, retrieval_config,
index_version, batch_id}`. `checker_status` records the gate verdict
(`pass` / `reworked` / bucket).

## Output → the app

- **Format:** `genanki` builds a `.apkg` using the exact field order from
  `rslib/src/ankountant/notetypes.rs`, tagged with `section::<x>`,
  `far::<topic>` (etc.), `ds::…` for confusion items, and `cog::rote|applied`.
- **Delivery, two options:**
  - **A (recommended): import the `.apkg`.** Standard Anki import; cards become
    ordinary notes; they sync to iOS/desktop through the normal channel with **no
    data-model change** — exactly how the MVP seed already round-trips.
  - **B: a `LoadGeneratedBank` RPC** that imports a bundled pack from disk (a
    shared-core method, reachable from both apps like `LoadFarSeed` — mind the
    hand-maintained iOS method index in `ios/…/AnkiBackend.swift`).
- **The runtime never calls a model.** Cards are static data. This is the whole
  point of the build-time/runtime split — the study loop, scheduler, and scoring
  are AI-off.

## Ops & cost model

Order-of-magnitude for a full 50k run (list prices; real spend lower with
discounts):

| Item                                                                 | Rough volume                   | Est. cost                              |
| -------------------------------------------------------------------- | ------------------------------ | -------------------------------------- |
| Embedding the Tier-A corpus (Voyage)                                 | ~20M tokens                    | **$1–5** (one-time per corpus refresh) |
| Bulk generation (Claude Sonnet, **Batch API −50% + prompt caching**) | ~50k cards, ~150M in / 15M out | **$250–450**                           |
| Hard TBS + judge-flagged regen (Claude Opus)                         | ~5–10k items                   | **$150–500**                           |
| Independent judge (sampled + all flagged)                            | ~15–25k judgments              | **$50–150**                            |
| Ragas + baseline A/B/C eval                                          | held-out slice                 | **$20–80**                             |
| **Total (full 50k)**                                                 |                                | **≈ $500–1,200**                       |

Cost levers, all recommended:

- **Batch API** for generation and judging (~50% off, async, fits an overnight
  job).
- **Prompt caching** — the retrieved passages + rubric for a topic are cached
  across that topic's many cards (cache reads are a fraction of input price);
  this is the biggest single saving.
- **Tiered models** — Sonnet bulk, Opus only where arithmetic/judgment demands.
- **Section-at-a-time** — generate FAR fully, eval, tune, _then_ fan out to the
  other five, so a prompt/retrieval bug costs one section, not six.

Cost is trivial next to the hand-authoring alternative (50k cards × even 5
min/card of human time is ~4,000 hours).

## Reproducibility

Every output is reproducible from three pinned inputs: the **corpus snapshot**
(sha256 per source), the **LanceDB index version**, and the **`gen_method`**
(model + prompt + retrieval config + seed). Re-running with the same three
reproduces the same cards; bumping any one is a versioned regeneration. The
`coverage_report.md` + `baseline_report.md` ([doc 5](05-quality-eval-and-baseline.md))
are checked in per run.

## Prompt-injection guardrails (ingested text is untrusted)

Even public-domain text is an injection surface (a PDF could contain "ignore
prior instructions…"). Defenses:

- **Delimit retrieved passages as data**, never as instructions; the system
  prompt states the passages are reference material and may contain adversarial
  text to be ignored.
- **Instruction-strip / sanitize** obvious injection patterns at ingest.
- **Output validation** (self-check stage 7) rejects anything that doesn't match
  the strict card schema — an injected "card" that tries to exfiltrate or
  misbehave fails schema/grounding checks.
- **No tools in the generation context** — the generator has no file/network
  access; it only transforms passages → card JSON.
- **Least privilege** — the batch job's credentials are scoped to the model API
  and the local corpus; nothing it emits can reach production without passing the
  gates.

## Build order (recommended)

1. Stand up `tools/cardgen/` + LanceDB + Voyage + the FAR `taxonomy.yaml`.
2. Ingest OpenStax + SEC (FAR Tier-A); index; wire retrieve→generate→self-check.
3. Build the FAR gold set; calibrate the judge; run the **baseline A/B/C** —
   prove RAG wins before scaling.
4. Generate FAR to target; eval; tune; **import the `.apkg`** and confirm it
   lights up the same review-loop/readiness surfaces the MVP seed does.
5. Re-point at REG/TCP (public-domain-rich, cheapest), then AUD, BAR, ISC.

[← Back to the index](README.md)
