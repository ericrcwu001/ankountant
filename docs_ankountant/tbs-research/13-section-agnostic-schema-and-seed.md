# 13 — Section-agnostic TBS: data model, typed schemas, cross-section seed

> Implements ADR 0008 (section-agnostic) + D9 (one union note type + typed
> schemas) + D10 (per-section literature). Read after `BUILD-PLAN.md`. This is the
> concrete target for Workstream A (and B/C).

> **2026-07-06 audit update:** this target is now the implemented shape. The live
> source of truth is `section_items[]` in
> `rslib/src/ankountant/seed_content.json`, the typed/validated seed loader in
> `rslib/src/ankountant/seed.rs`, and bundled per-section literature consumed by
> the desktop and iOS research surfaces.

## 1. Section dimension (minimal, sync-safe)

- `section ∈ {AUD, FAR, REG, BAR, ISC, TCP}`.
- Already encoded by the sealed-deck prefix
  `Ankountant::Sealed::<section>::<set_id>` (sealed detection in `service.rs`) and
  by per-section config keys (`ankountant.confusable.<section>`,
  `GetReadiness(section)`). So most of the "section" plumbing exists.
- Native note tags `sec::<section>` and the `ds::` confusion tag keep direct
  query support without a new field/table.
- The seed, CONFUSABLE map, and readiness path are section-aware across
  `Ankountant::Sealed::<section>::*`, `ankountant.confusable.<section>`, and
  `GetReadiness(section)`.

## 2. Typed schemas (D9) — replace "unknown-keys-ignored" with validated structs

Stored as JSON in the existing `exhibits_json` / `steps_json` fields, but parsed
via explicit serde structs carrying a `schema_version`, **validated at seed
load** and surfaced to clients **with answer keys stripped**.

### 2.1 Exhibit (typed) — shared by all shapes

```
Exhibit {
  id?, title,
  kind: "text"|"email"|"invoice"|"table"|"statement"|"memo"|"document"|"stamp",
  role?: "document",            // the doc-review primary document
  body?: string,                // text/markdown/HTML (blank markers live here)
  columns?: [string], rows?: [[string]]   // for kind:"table"
}
```

Closes the `01` fidelity gap (email/invoice/table/posting-stamp) and carries the
doc-review document (`role:"document"`, body with `<blank step="id">…</blank>`).

### 2.2 Step (typed) — union by shape

- **research:** `{ id, kind:"citation", answer_key, accepted:[…], corpus_refs:[…], granularity:"section"|"paragraph", weight }`
- **doc_review blank:** `{ id, kind:"blank", answer_key /*=correct option id*/, options:[{id,text,kind:"keep"|"delete"|"replace"}], confusion_set_id, weight, original_text?, exhibit_refs?:[…] }`
- **je line:** `{ id, kind:"je", account, side, amount, weight }`
- **numeric cell:** `{ id, kind:"numeric", answer_key, tolerance, weight, label }`
- **options_list:** `{ id, kind:"option", answer_key, options:[…], weight }`

The Rust grader still reads only `id`/`answer_key`/`weight`/`tolerance`
(unchanged); the typed layer validates the rest and drives the clients.

## 3. Per-section literature corpus (D10)

`seed_literature.json` → `{ "<SECTION>": [ { id, citation, title, body, tags[], verbatim: bool, source } ] }`.

- **FAR/BAR** (FASB ASC) + GASB: `verbatim:false`, `body` = OUR paraphrase +
  `deep_link`. Cite-only (ADR 0006) — never commit ASC prose.
- **REG/TCP** (IRC/Treasury/IRS), **AUD** (PCAOB, SEC eCFR), **ISC** (NIST):
  `verbatim:true`, `body` = REAL public-domain text — bundle it.
- One loader; client-side search scoped by section (OQ-3 = client-side).

## 4. Cross-section seed (lead items) — verify every authority vs CURRENT standards

| #  | Section | Shape      | Item                                                    | Answer / blanks   | Corpus / license |
| -- | ------- | ---------- | ------------------------------------------------------- | ----------------- | ---------------- |
| 1  | AUD     | doc_review | KCN audit-request-list (verbatim, `06` §5A; 8 callouts) | reasoned key      | audit standards  |
| 2  | AUD     | research   | governing standard for sufficient audit evidence        | AU-C/AS cite      | PCAOB verbatim   |
| 3  | REG     | research   | deductibility of ordinary & necessary business expense  | IRC §162(a)       | IRC verbatim     |
| 4  | REG     | doc_review | tax memo with erroneous positions                       | per-blank         | IRC verbatim     |
| 5  | FAR     | research   | lease commencement recognition                          | `ASC 842-20-25-1` | ASC cite-only    |
| 6  | FAR     | doc_review | revenue-recognition footnote (`06` §5C; 5 blanks)       | per-blank         | ASC cite-only    |
| 7  | FAR     | numeric    | Blear Co. adjusting entries (`01`; 7 signed cells)      | signed integers   | ASC cite-only    |
| 8  | BAR     | research   | e.g. segment / EPS disclosure                           | ASC cite          | ASC cite-only    |
| 9  | TCP     | research   | individual/entity tax-planning item                     | IRC cite          | IRC verbatim     |
| 10 | ISC     | doc_review | SOC/NIST control-mapping memo                           | per-blank         | NIST verbatim    |

Add ≥1 CONFUSABLE set per section (e.g. AUD `evidence_sufficiency`,
REG `capitalize_vs_deduct`, ISC `control_type`). Trim to a realistic first batch
(≈ 2 per section) but keep the schema + corpus multi-section from day one.

## 5. What stays unchanged

Grading path (`SubmitPerformanceAttempt`), Attempt Log, sync-safety, and the proto
(append-only; nothing needed). The BUILD-PLAN A1/A2 backend deltas (research
grading arm, `doc_review` readiness bucket, citation normalization, `elapsed_ms`)
are already section-agnostic and stand.
