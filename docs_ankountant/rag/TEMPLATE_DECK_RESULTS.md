# Template (Automatic Item Generation) deck — results (`tmpl4`, 325 cards)

> A second, complementary generation mode: expand curated templates x
> source-pinned data rows into cards with **no per-card LLM call**, then reuse the
> same quality pipeline (self-check -> gold -> judge -> leakage -> dedup -> emit).
> See the plan `template_card_generation` and `templates.py`.
>
> **Current best deck:** `tools/cardgen/out/tmpl4/cpa_bank.apkg` — **325 shipped,
> 1 wrong blocked, 0 leakage** (see "Scaling via corpus harvest" below). The
> section immediately below documents the original hand-curated `tmpl2` proof (14
> cards) that established the pipeline.
>
> **Online-sourced supplement:** `tools/cardgen/out/tmpl4/online_bank.apkg` — **191
> cards curated from AnkiWeb community CPA decks** (parsed from third-party `.apkg`s,
> cleaned, categorized into a CPA section — FAR 138 / AUD 33 / REG 20 — deduped
> against the 325, then passed through an independent-subagent usefulness triage:
> **223 harvested → 191 kept**). Provenance stays on every card (`src::ankiweb`,
> deck `Ankountant::Community::<section>`). The desktop **"CPA Bank"** button imports
> both packs (**516 total**) in one click. Pipeline: `scripts/fetch_ankiweb.mjs` →
> `harvest_online.py` → `triage_online.py` → `emit_online.py`.

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

## Scaling via corpus harvest — precision-tuned (`tmpl4`)

`scripts/harvest_templates.py` extracts grounded fill rows straight from the
ingested corpus (each `source_passage` is a verbatim single-page substring). The
`tmpl3` pass proved the seams but exposed a precision problem in the auto-cloze
family (only 29% shipped); `tmpl4` fixes the harvester and grows the sources,
lifting the deck from 113 to **325 shipped cards** (2.9x).

What changed in the harvester:

- **Cloze precision filter, tuned against the judge's own `tmpl3` labels.** Keep a
  fill-in-the-blank only when the sentence is a *rule/threshold tied to a named
  provision* (e.g. "section 179", "adoption credit", "self-employment tax") and
  reject worked-example figures (proper-name / narrative transactions, calendar
  dates, worksheet line refs, `$a ± $b` formulas, anaphoric "This limit …"). On the
  213 `tmpl3`-graded cloze cards this filter keeps **87% of the judge's "good" and
  drops 89% of its "bad"** (76% pool precision) — the judge remains the final gate.
- **De-hyphenation** of the displayed cloze (OCR column breaks like "sepa- rately"),
  with `source_passage` kept verbatim so grounding still matches.
- **NIST controls: block-aware regex.** The catalog wraps each control across line
  breaks (`AC-2\nACCOUNT MANAGEMENT\nControl:\na. …`); the old single-line regex
  caught only 18. The block regex captures **77 base controls** (skipping the
  near-duplicate "-1 Policy and Procedures" boilerplate).
- **AU-C references** broadened (parenthesized *or* bare cite) -> 37, cap 4/section.
- **All 13 ingested IRS pubs** iterated (Pub 17/334/501/505/535/541/542/544/550/551/
  946/970 + Circular 230) -> **379 grounded cloze rows** after filtering + dedup.

Funnel: **501 expanded** (0 grounding failures) -> 501 self-check -> gold
calibration **PASS** -> **13 batches** fully judged by independent Cursor subagents
(2 waves) -> **325 correct_useful, 175 bad_teaching, 1 wrong** -> leakage 0 (vs 84
sealed refs) -> dedup 0 -> **325 shipped** (`out/tmpl4/cpa_bank.apkg`, 120 decks).

| Cut               | tmpl3 |     tmpl4 |
| ----------------- | ----: | --------: |
| Candidate pool    |   271 |       501 |
| Shipped           |   113 |   **325** |
| Cloze ship-rate   |   29% | **~54%**  |
| Wrong (blocked)   |     0 |         1 |

- **Shipped by section:** REG 151, ISC 82, TCP 56, AUD 36.
- **By template:** `irs_cloze_recall` 201, `nist_control_research` 77,
  `auc_research` 34, `citation_research` 8, `tax_threshold_recall` 3,
  `tax_phaseout_mcq` 2.
- **By license:** public 289 (redistributable), personal_use 36 (AU-C, Tier-B PDF).

Two honest takeaways:

- **1 wrong across 501 cards, caught by the gate.** An AU-C exhibit inverted "the
  auditor is *not* obligated to search for significant deficiencies"; the
  independent judge flagged it and it did not ship. Grounding + verbatim extraction
  otherwise produced no factual errors — the safety property templates buy.
- **The corpus, not the filter, is now the binding constraint.** Raising the
  per-source cap does *not* add cloze cards (the precision filter is the limit), and
  the ~231 genuinely-good threshold sentences in these IRS pubs are ~87% shipped.
  The remaining `bad_teaching` are semantic worked-examples ("Dean's partnership
  figures", "$178 SL 2nd-year depreciation") that no regex can separate — which is
  exactly what an independent judge is for. Materially more cards means *more
  corpus/seams* (e.g. FAR via OpenStax, NIST control enhancements), not more cloze
  squeezing.

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
