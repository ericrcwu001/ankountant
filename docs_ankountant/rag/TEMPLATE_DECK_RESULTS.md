# Template (Automatic Item Generation) deck — results (`tmpl2`)

> A second, complementary generation mode: expand curated templates x
> source-pinned data rows into cards with **no per-card LLM call**, then reuse the
> same quality pipeline (self-check -> gold -> judge -> leakage -> dedup -> emit).
> See the plan `template_card_generation` and `templates.py`.

## What it is

`--mode template` turns the recurring shapes of the vetted RAG cards into reusable
templates with typed `{slots}`, filled from hand-curated data rows. Each row is
pinned to a **named public source** (a verbatim `source_passage` that must be a
substring of that source's `00-ingest` text), so every card is grounded without
retrieval. Numeric answers are computed by a deterministic formula registry; MCQ
distractors are curated.

DAG: `ingest -> templates -> selfcheck -> gold -> judge -> leakage -> dedup -> emit`
(no chunk/index/retrieve/generate/baseline).

## Result

- **14 cards shipped** -> `tools/cardgen/out/tmpl2/cpa_bank.apkg` (12 decks).
- Funnel: 14 expanded (0 dropped by grounding) -> 14 self-check -> gold
  calibration **PASS** -> judged **14 / 14 correct_useful** (0 wrong, 0
  bad-teaching) by an independent Cursor subagent -> leakage 0 -> dedup 0.
- Cost: ~$0 (no generation LLM; only a few embedding calls for leakage/dedup).

### Families (v1)

- `citation_research` (tbs_research) x 9 — "identify the governing citation for
  {topic}": AU-C 265 / 320 / 705 (AUD), NIST SP 800-53 CA-3 / IR-6 / SA-9, NIST SP
  800-12, OMB Circular A-130 App III (ISC), Treasury Circular 230 Sec. 10.71 (REG).
- `tax_threshold_recall` (recall) x 3 — student-loan max $2,500 (Pub 970),
  self-employment filing $400 (Pub 334), senior enhanced deduction $6,000 (Pub 17).
- `tax_phaseout_mcq` (mcq) x 2 — student-loan MAGI phase-out $85k-$100k (single);
  IRA deduction phase-out $236k-$246k (MFJ, spouse-covered).

## The quality gate caught real curation bugs (then passed)

The first judge pass (`tmpl1`) returned **1 wrong + 4 bad_teaching**, both genuine:

1. **Wrong** — the IRA phase-out row labeled $236k-$246k as the "covered by a
   workplace plan" MFJ range; that range is actually the "spouse-covered, you not
   covered" case (covered MFJ is $126k-$146k). Fixed the row's scenario.
2. **Bad teaching** — the research exhibits echoed the source sentence *including
   the citation*, making the "research" self-answering. Fixed by using a
   scenario-only exhibit and redacting the citation from any exhibit body
   (`templates._redact_tokens`).

After the fixes, `tmpl2` judged **14 / 14 correct_useful**. This is the 3-bucket
gate doing exactly its job on template cards.

## Provenance & licensing

Template cards carry the same provenance fields as RAG cards, with a
template-specific `gen_method`:

```json
"gen_method": {"method": "template", "template_id": "citation_research",
  "template_version": "v1", "variant_key": "nist80053_ir6_incident_reporting",
  "license": "public"}
```

Each row records a `license`: **public** (IRS / NIST / OMB / Treasury — public
domain, redistributable) or **personal_use** (grounded in the Tier-B AUD review
PDF — not redistributable). A redistributable pack must exclude the
personal-use-licensed cards.

## Honest scope / next steps

- Only the tax-threshold and citation families are true "plug-and-play": each new
  card needs a real, source-pinned value/citation, so volume tracks curated data,
  not free generation. Realistic near-term ceiling is a few hundred cards as the
  data files grow.
- **compute-numeric** (`tbs_numeric`) is engine-complete and unit-tested
  (`tests/test_templates.py::test_numeric_formula_and_money_render`), but no data
  family ships yet: computed answers use hypothetical exhibit numbers that a strict
  answer-vs-source judge won't find in the source, and the natural source
  (OpenStax) is CC BY-NC-SA (personal-use). Shipping it needs either a
  method-grounded judge relaxation for computed cards or public-domain worked
  examples.
- To scale: grow `templates/` + data rows (harvest verbatim threshold sentences
  from the ingested IRS pubs), run `just cardgen all --mode template`, fan out
  judge subagents (or `--judge-mode audit`), then `resume`. Merge the template
  `.apkg` with the RAG deck for import.
