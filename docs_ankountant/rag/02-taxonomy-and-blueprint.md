# 2 — Taxonomy & Blueprint Allocation

[← Sources](01-sources-and-licensing.md) · [Index](README.md) · Next: [Architecture →](03-architecture-and-stack.md)

50,000 is a number, not a plan. This doc turns it into a **work-list**: a
concrete `(section, area, topic, skill-level, card-type, target-count)` table
the pipeline iterates over. The taxonomy is the **AICPA Uniform CPA Examination
Blueprints** (public), which are already organized exactly the way we need.

## The exam model (CPA Evolution, 2024→)

Every candidate takes **3 Core** sections + **1 of 3 Discipline** sections.

| Kind       | Section                                    | Focus                                            |
| ---------- | ------------------------------------------ | ------------------------------------------------ |
| Core       | **AUD** — Auditing & Attestation           | audit process, evidence, reports, ethics         |
| Core       | **FAR** — Financial Accounting & Reporting | US GAAP, financial statements, gov/NFP           |
| Core       | **REG** — Taxation & Regulation            | federal tax (indiv/entity), business law, ethics |
| Discipline | **BAR** — Business Analysis & Reporting    | advanced FAR, financial analysis, managerial     |
| Discipline | **ISC** — Information Systems & Controls   | IT audit, SOC, security, data                    |
| Discipline | **TCP** — Tax Compliance & Planning        | advanced individual & entity tax, planning       |

We build **all six** so any candidate is served. The MVP seed already exists for
**FAR** and is the proving ground; FAR is generated first end-to-end, then the
pipeline is re-pointed at the other five.

## Blueprint structure → our taxonomy

Each blueprint is a tree:

```
Section → Area (weighted %) → Group → Topic → Representative Task (skill level)
```

The AICPA assigns each area a **score weight** and each representative task a
**skill level** on a 4-level scale:

1. **Remembering & Understanding** (R&U)
2. **Application**
3. **Analysis**
4. **Evaluation** (AUD only, at the top)

We ingest the blueprint into a machine-readable `taxonomy.yaml` (one row per
representative task, with `section, area, area_weight, group, topic, task_id,
skill_level`). This file is the pipeline's spine and the audit record of _what
we tried to cover_.

## Card-type mapping (skill level → app mode)

The app has exactly three study modes; the blueprint skill level chooses which
one a card becomes:

| Skill level                 | Card type                                              | App surface                  | Note type                      |
| --------------------------- | ------------------------------------------------------ | ---------------------------- | ------------------------------ |
| Remembering & Understanding | **Recall flashcard** (atomic fact)                     | study loop                   | `Ankountant Study`             |
| Application                 | **Confusion / "which treatment?"** or applied MCQ      | sealed bank / confusion mode | `Ankountant TBS` (choice step) |
| Analysis / Evaluation       | **TBS** (research, journal-entry, numeric, doc-review) | TBS surface                  | `Ankountant TBS` (multi-step)  |

This is why the app's data model already carries everything the pipeline emits —
no new note types needed (see [doc 6](06-provenance-output-and-ops.md)).

## Allocating 50,000

Two-level allocation: **across sections**, then **within a section by area
weight and skill mix**.

### Across sections (target ≈ 50,000)

Weighted by exam breadth and how much _legitimately-licensed_ source material
exists (tax sections are public-domain-rich; ISC is thinner). Illustrative:

| Section   | Target cards | Rationale                                       |
| --------- | -----------: | ----------------------------------------------- |
| FAR       |       11,000 | broadest Core; strong OpenStax + SEC coverage   |
| REG       |        9,000 | public-domain IRC/regs → cheap, high-confidence |
| AUD       |        8,000 | PCAOB/GAO public standards                      |
| TCP       |        8,000 | public-domain tax; overlaps REG corpus          |
| BAR       |        8,000 | advanced FAR + finance (OpenStax Finance)       |
| ISC       |        6,000 | thinnest open corpus; cap honestly              |
| **Total** |   **50,000** |                                                 |

### Within a section (per topic)

```
cards_for_topic = round( SECTION_TARGET
                         × area_weight
                         × topic_share_within_area )
```

then split across skill levels using the blueprint's own skill distribution for
that topic (e.g. a topic that is 60% R&U / 40% Application yields ~60% recall
cards, ~40% confusion/applied items). TBS items are generated only for
Analysis/Evaluation tasks and are intentionally **rarer and higher-effort**
(they cost more to generate and verify — see [doc 6](06-provenance-output-and-ops.md)).

### Reaching a count without repetition

A single representative task can legitimately yield many cards by **varying the
grounded fact pattern** (different numbers, entities, edge conditions) drawn from
different retrieved passages — but each variation must still be _grounded_ and
must survive the **dedup / leakage** checks ([doc 5](05-quality-eval-and-baseline.md)).
`target_count` is a ceiling, not a quota: if a topic's Tier-A corpus can't
support N distinct grounded cards, we emit fewer and **log the shortfall**. We do
not hallucinate to hit 50,000.

## The confusion-set catalog

Confusion sets (the app's "which treatment applies?" mode) are a curated
sub-taxonomy: pairs/among-N treatments that candidates routinely confuse. The
MVP seeds four FAR sets (`capitalize_vs_expense`, `operating_vs_finance_lease`,
`revrec_step_selection`, `trading_afs_htm`). The pipeline extends this into a
`confusion_catalog.yaml` per section (e.g. AUD: _qualified vs adverse opinion_;
REG: _§1231 vs capital vs ordinary_; FAR: _change-in-estimate vs error
correction_). Each entry defines the `set_id`, the discriminating `ds::` tags,
and the treatment strings — exactly the shape `seed.rs`/`config.rs` already
consume, so generated confusion items drop straight into the existing machinery.

Next: [Architecture & stack →](03-architecture-and-stack.md)
