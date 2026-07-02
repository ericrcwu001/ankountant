# 01 — `FAR TBS.pdf`: Full Extraction & Transcription

Primary-source extraction of `~/Downloads/FAR TBS.pdf`. This is the richest
real-world artifact we have for what an _actual, test-accurate_ FAR Task-Based
Simulation looks like. Everything below is transcribed from the file itself
(ground-truth by rendering each page to an image; see [Appendix A](#appendix-a--extraction-method--reproducibility)).

---

## 0. Headline finding (read this first)

**The PDF is ONE single TBS, not a set.** It is an _official AICPA retired
sample_ of a single **analysis-level, numeric spreadsheet ("adjusting entries")
TBS** — the candidate reconciles seven exhibits against a draft balance sheet
and types dollar adjustments into a grid.

- **Shape:** `numeric` (multi-cell numeric grid). This is a shape we **already
  support**. There are **no `research` and no `document-review` items in this
  file.**
- It is still highly decision-relevant for the deferred shapes because it shows,
  from the real exam, (a) the exact **exhibit vocabulary** (email thread,
  vendor invoices with _posting stamps_, subledgers, financial summaries),
  (b) the exact **authoritative-literature citation format** the AICPA uses in
  answer keys (`ASC 860-10-05-14`, `FASB Concepts Statement No. 8`), and
  (c) how **step/partial-credit grading** and the **official TBS UI** actually
  work.
- **Watch-out:** our current `exhibits_json` model is `[{title, body}]` with
  `body` as a _plain-text blob_. This item's exhibits are **tables, an email
  thread, and stamped invoices** — text-representable but with real fidelity
  loss (grid layout, the diagonal "Posted to…" stamp overlay). This is the same
  fidelity gap the `document-review` shape will have to solve. See
  [§8](#8-encoding-into-our-model) and [§9](#9-what-this-teaches-us-for-research--document-review).

---

## 1. Overall stats

| Metric                                                | Value                                                                                                                                                                                                                                                                             |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File                                                  | `~/Downloads/FAR TBS.pdf`, 875 KB, 20 pages                                                                                                                                                                                                                                       |
| Distinct TBS items                                    | **1**                                                                                                                                                                                                                                                                             |
| Shape breakdown                                       | `numeric` ×1 · `journal_entry` ×0 · `research` ×0 · `document-review` ×0 · `options-list` ×0                                                                                                                                                                                      |
| Response cells                                        | 13 editable numeric cells (column D); 7 require a non-zero value, 6 are "leave blank" distractor rows; 6 subtotal cells auto-calculate                                                                                                                                            |
| Exhibits                                              | **7** (1 email thread, 2 vendor invoices, 3 subledger/summary tables, 1 inventory-analysis table)                                                                                                                                                                                 |
| FAR Blueprint                                         | Area I (Financial reporting), Group A, Topic 1; Skill = **Analysis**; est. 20–30 min                                                                                                                                                                                              |
| Provenance                                            | © 2025 AICPA; doc id `2508-369595`; "Retired task-based simulation from the FAR Section of the Uniform CPA Examination"                                                                                                                                                           |
| FAR topics exercised (sub-issues within the one item) | Transfers/derecognition of financial assets — factoring (ASC 860); Inventory lower-of-cost-and-NRV + count cutoff (ASC 330); PP&E capitalizable cost + reclass (ASC 360); R&D vs. intangible capitalization (ASC 350 / 730); Accrual/period-cutoff + Conceptual Framework (CON 8) |

**Document layout:** p1 cover · p2 intro + blueprint + task prompt · p3 the work
grid · p4–p7 the seven exhibits (full-page) · p8–p18 the official worked
solution (one adjustment per section, each with a repeated exhibit thumbnail,
journal entries, the cell to fill, and ASC references) · p19 the completed grid ·
p20 AICPA copyright.

---

## 2. The item at a glance

| Field               | Value (verbatim)                                                                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Entity              | **Blear Co.** — consolidated FS as of / for the year ended **December 31, year 3**; expected issuance **February 25, year 4**                    |
| Blueprint reference | **FAR Area I, Group A, Topic 1**                                                                                                                 |
| Representative task | "Detect, investigate and correct discrepancies while agreeing the balance sheet amounts to supporting documentation, including the source data." |
| Skill               | **Analysis**                                                                                                                                     |
| Estimated time      | 20 to 30 minutes                                                                                                                                 |

### 2.1 Task prompt (verbatim, from the EXHIBITS panel on p2)

> **Scroll down to complete all parts of this task.**
>
> Blear Co. is preparing its consolidated financial statements as of and for the
> year ended December 31, year 3. The consolidated financial statements are
> expected to be issued on February 25, year 4. Review the exhibits above to
> identify the adjustments, if any, to the draft consolidated statement of
> financial position as of December 31, year 3.
>
> To adjust the draft consolidated statement of financial position:
>
> - Enter the amount associated with each adjustment in column D.
> - Adjustments might not be required in some rows within the draft consolidated
>   statement of financial position.
> - Enter increases as positive whole values and decreases as negative whole
>   values. If no adjustment is needed, then leave column D blank.
> - If multiple adjustments affect a single financial statement line item, then
>   enter the net amount of the adjustments in column D.
> - Amounts in column E and subtotals will calculate automatically.

---

## 3. Response surface — the work grid

A spreadsheet with **columns A–E** and **numbered rows 1–30**. Only **column D
("Adjustment")** is editable; each editable cell shows a small **`123`
numeric-input icon**. Column E ("Year 3 Adjusted Balance") and the **bold
subtotal rows** auto-calculate. Columns B/C are read-only given data.

- **Editable numeric cells (13):** `D4, D5, D6, D7, D11, D12, D16, D17, D21, D25, D26, D27, D28`
- **Auto-calc subtotal cells:** `D8, D13, D18, D22, D29, D30` (+ all of column E)

Full grid (col A label · B = Year 2 Balance · C = Year 3 Unadjusted · **D =
Adjustment (answer)** · E = Year 3 Adjusted). Blank D = "leave blank" (no
adjustment). Negatives shown in `( )`.

| Row | A — Line item                                  |   B (Yr2) | C (Yr3 unadj.) |  **D (answer)** |  E (Yr3 adj.) |
| --- | ---------------------------------------------- | --------: | -------------: | --------------: | ------------: |
| 3   | _Current assets_                               |           |                |                 |               |
| 4   | Cash                                           |   645,000 |        777,000 |       _(blank)_ |       777,000 |
| 5   | Accounts receivable (net)                      |   110,500 |         80,100 |     **(3,000)** |        77,100 |
| 6   | Inventory                                      |    46,250 |         41,700 |     **(8,260)** |        33,440 |
| 7   | Prepaid expenses                               |     4,500 |          2,500 |       **5,000** |         7,500 |
| 8   | **Total current assets**                       |   806,250 |        901,300 |  _(6,260) auto_ |       895,040 |
| 10  | _Noncurrent assets_                            |           |                |                 |               |
| 11  | Property, plant and equipment (net)            |   705,000 |        820,000 |     **(5,000)** |       815,000 |
| 12  | Intangible assets (net)                        |    55,000 |         65,000 |    **(20,000)** |        45,000 |
| 13  | **Total assets**                               | 1,566,250 |      1,786,300 | _(31,260) auto_ | **1,755,040** |
| 15  | _Current liabilities_                          |           |                |                 |               |
| 16  | Accounts payable and accrued expenses          |   188,300 |        165,000 |      **33,500** |       198,500 |
| 17  | Current portion of long-term debt              |         0 |        100,000 |       _(blank)_ |       100,000 |
| 18  | **Total current liabilities**                  |   188,300 |        265,000 |   _33,500 auto_ |       298,500 |
| 20  | _Noncurrent liabilities_                       |           |                |                 |               |
| 21  | Long-term debt, less current portion           |   400,000 |        200,000 |       _(blank)_ |       200,000 |
| 22  | **Total liabilities**                          |   588,300 |        465,000 |   _33,500 auto_ |       498,500 |
| 24  | _Shareholders' equity_                         |           |                |                 |               |
| 25  | Common stock                                   |     5,000 |          5,000 |       _(blank)_ |         5,000 |
| 26  | Additional paid-in capital                     |   210,340 |        225,300 |       _(blank)_ |       225,300 |
| 27  | Retained earnings                              |   748,110 |      1,078,600 |    **(64,760)** |     1,013,840 |
| 28  | Accumulated other comprehensive income         |    14,500 |         12,400 |       _(blank)_ |        12,400 |
| 29  | **Total shareholders' equity**                 |   977,950 |      1,321,300 | _(64,760) auto_ |     1,256,540 |
| 30  | **Total liabilities and shareholders' equity** | 1,566,250 |      1,786,300 | _(31,260) auto_ | **1,755,040** |

**Self-check (from p19 "Completed task"):** total adjusted assets **$1,755,040**
= total adjusted liabilities + equity **$1,755,040**. ✓ (Balance is the built-in
"you got it right" signal.)

**Response-format taxonomy for this item:** numeric cells **only**. No JE
grid, no dropdown/option cells, no citation/research box, no highlighted-phrase
dropdowns. (Journal entries _appear_ in the answer explanation as the reasoning,
but the candidate never enters them — they type net dollar deltas.)

---

## 4. Exhibits (all 7, transcribed verbatim)

The p2 EXHIBITS panel lists them as tabbed links: _Email regarding sale of
accounts receivable · Year-end inventory analysis · Accounts payable subledger ·
Accrued expense general ledger detail · Home Build Corp. Invoice · Guardian LLC
Invoice · Intangible Asset Summary_. Each opens as a draggable window with a
dark title bar and a red ✕ close button.

### E1 — Email regarding sale of accounts receivable _(type: email thread, 2 messages)_

> **From:** senioraccountant@blearco.com **To:** armanager@blearco.com
> **Sent:** 12/30/year 3 **Subject:** RE: Sale of Accounts Receivable
>
> Accounts Receivable Manager:
> I have already recorded the following entry for the December close to record
> the sale:
>
> ```
> Dr.  Cash                    27,000
> Cr.  Accounts receivable            27,000
> ```
>
> Thanks, Senior Accountant · senioraccountant@blearco.com · 111.222.3456

> **From:** armanager@blearco.com **To:** senioraccountant@blearco.com
> **Sent:** 12/29/year 3 **Subject:** Sale of Accounts Receivable
>
> Senior Accountant:
> On December 28, we entered into an agreement to sell **$30,000** of our
>
>> outstanding accounts receivable balances of our east coast operations. The
>> agreement was made **without recourse for a 10% fee**. We received **$27,000**
>> from the buyer today to settle the transaction. Please adjust the general
>> ledger accordingly.
>> Thanks, Accounts Receivable Manager · armanager@blearco.com · 111.222.7890

### E2 — Year-end inventory analysis _(type: table)_

Blear Co. — Inventory Analysis — As of December 31, year 3

| Product type | Qty per inventory subledger | Qty per physical count | Unit cost | Replacement cost | Net realizable value (NRV) | Normal profit margin |
| ------------ | --------------------------: | ---------------------: | --------: | ---------------: | -------------------------: | -------------------: |
| A            |                       1,500 |                  1,450 |       $25 |              $26 |                        $20 |                   $2 |
| B            |                         140 |                    148 |       $30 |              $37 |                        $35 |                   $2 |

> **Note** — The physical count was done on 12/31/year 3 by the warehouse
> manager, and the company uses **FIFO** for valuation purposes. The impact of
> the inventory analysis is not reflected in the unadjusted inventory balance as
> of 12/31/year 3.

### E3 — Accounts payable subledger _(type: subledger table)_

Blear Co. — Accounts payable subledger — Month ended January 31, year 4

| Date         | Vendor         | Description                                                                  |   Amount |
| ------------ | -------------- | ---------------------------------------------------------------------------- | -------: |
| 12/31/year 3 |                | Beginning balance                                                            |  155,000 |
| 1/4/year 4   | Clean Co.      | Janitorial services received in **December, year 3**                         |    6,000 |
| 1/5/year 4   |                | Payments to vendors                                                          | (15,000) |
| 1/10/year 4  | Guardian, LLC  | Legal fees for general corporate matters                                     |   27,500 |
| 1/15/year 4  |                | Payments to vendors                                                          | (25,000) |
| 1/18/year 4  |                | Payments to vendors                                                          | (22,000) |
| 1/19/year 4  | Machine Co.    | Inventory received on January 10, year 4 (f.o.b. destination)                |   18,000 |
| 1/22/year 4  | Computer Corp. | Computer supplies received on January 15, year 4 (ordered January 2, year 4) |    8,500 |
| 1/28/year 4  |                | Payments to vendors                                                          | (75,300) |
| 1/29/year 4  | Match Corp.    | Inventory received on January 27, year 4 (f.o.b. destination)                |   22,200 |
| 1/31/year 4  |                | Ending balance                                                               |   99,900 |

> **Note:** The payments made during January, year 4, to vendors are for amounts
> included in the 12/31/year 3 balance in accounts payable.

### E4 — Accrued expense general ledger detail _(type: table — all distractors)_

Blear Co. — Accrued expense detail — Month ended January 31, year 4

| Date         | Description                                          | Amount |
| ------------ | ---------------------------------------------------- | -----: |
| 12/31/year 3 | Beginning balance                                    | 10,000 |
| 1/31/year 4  | Accrued sales commissions for January, year 4        |  8,000 |
| 1/31/year 4  | Accrued consulting fees incurred for January, year 4 |  7,000 |
| 1/31/year 4  | Ending balance                                       | 25,000 |

### E5 — Home Build Corp. Invoice _(type: vendor invoice w/ posting stamp)_

Home Build Corp., 100 Park Street, Park, VA 55432 · Phone 999-998-1234 ·
**INVOICE** · DATE **12/31/year 3** · INVOICE # **0567** ·
Bill to: Accounts payable department, Blear Co., 49 Industry Lane, Old Towne, MD 54321

**Posting stamp (diagonal overlay):** _Posted to: Property, plant and equipment ·
Amount Posted: **$85,300** · Accounting Period: December, year 3 · Posted:
12/31/year 3 · Paid: 12/31/year 3_

| Item #  | Description                                                                | Unit Price |  TOTAL |
| ------- | -------------------------------------------------------------------------- | ---------: | -----: |
| 1122455 | HVAC for manufacturing building installed December 31, year 3              |     75,000 | 75,000 |
|         | Annual maintenance contract for the period 1/1/year 4 through 12/31/year 4 |      5,000 |  5,000 |

SUBTOTAL 80,000 · TAXABLE 75,000 · TAX RATE 6.00% · TAX 4,500 · SHIPPING AND
HANDLING 800 · **TOTAL $85,300**. Comments: "1. Total payment due on
installation. 2. Please include the invoice number on your remittance."

### E6 — Guardian LLC Invoice _(type: vendor invoice w/ posting stamp)_

Guardian LLC · January 9, year 4 · Invoice Number 22544855 · **Invoice** ·
Bill to: Accounts Payable Department, Blear Co., 49 Industry Lane, Old Towne, MD 54321

**Posting stamp (diagonal overlay):** _Posted to: Legal expense acct #6100 ·
Amount posted: **$27,500** · Accounting period: January, year 4 · Posted:
1/10/year 4 · Paid: 2/28/year 4_

| Date(s) of Services         | Description of Services                                    | Service Total |
| --------------------------- | ---------------------------------------------------------- | ------------: |
| 12/1/year 3 to 12/31/year 3 | December, year 3, legal fees for general corporate matters |       $27,500 |

Invoice Terms: **Net 60** · Guardian LLC, 102 Main Street, Baltimore, MD 55551 ·
Phone 1-200-121-1212 · billing@guardianllc.com

### E7 — Intangible Asset Summary _(type: rollforward table)_

Blear Co. — Intangible Asset Summary — As of and for the year ended December 31, year 3

| Account                  | Bal 12/31/yr1 | Additions | Disposals | Bal 12/31/yr2 |  Additions | Disposals | Bal 12/31/yr3 |
| ------------------------ | ------------: | --------: | --------: | ------------: | ---------: | --------: | ------------: |
| Patents                  |        75,000 |         - |         - |        75,000 | **20,000** |         - |        95,000 |
| Copyrights               |        40,000 |         - |         - |        40,000 |          - |         - |        40,000 |
| Accumulated amortization |      (50,000) |  (10,000) |         - |      (60,000) |   (10,000) |         - |      (70,000) |
| **Total**                |        65,000 |  (10,000) |         - |        55,000 |     10,000 |         - |        65,000 |

> **Note:** The **$20,000 addition to the patent account** is attributable to
> salary and benefit costs incurred to continue **research and development**
> activities during the development of a new product expected to launch in year 4.

---

## 5. Answer key + per-adjustment derivation

Each adjustment is an independent sub-problem. The AICPA solution presents each
as: the reasoning → the _correcting journal entry_ (explanatory only) → the
**cell + signed value to enter** → **References** to authoritative literature.

### A1 · Accounts receivable (net) — factoring / derecognition

- Sold $30,000 A/R **without recourse**, 10% fee; received $27,000. Without
  recourse ⇒ control surrendered ⇒ qualifies as a **sale**.
- Senior accountant booked only `Dr Cash 27,000 / Cr A/R 27,000` — **omitted the
  fee/loss and under-derecognized A/R.**
- Correct entry: `Dr Cash 27,000 · Dr Loss on sale of A/R 3,000 · Cr A/R 30,000`
  (loss = $30,000 × 10% = **$3,000**).
- **Adjusting entry:** `Dr Loss on sale of A/R 3,000 / Cr A/R 3,000` (reduces NI & RE).
- **Enter `D5 = −3,000`.** RE impact −3,000.
- **References:** ASC 860-10-05-14; ASC 860-10-40-5; ASC 860-10-55-45.

### A2 · Inventory — lower of cost & NRV + count cutoff

- **Product A:** NRV $20 < cost $25 ⇒ write down; use physical count 1,450.
  Book = 1,500 × $25 = 37,500; correct = 1,450 × $20 = 29,000 ⇒ **overstated 8,500**.
- **Product B:** cost $30 < NRV $35 ⇒ keep at cost; count 148 vs 140 ⇒ +8 units
  × $30 = **understated 240**.
- Net = 8,500 − 240 = **8,260 overstated**.
- **Adjusting entry:** `Dr COGS 8,260 / Cr Inventory 8,260` (reduces NI & RE).
- **Enter `D6 = −8,260`.** RE impact −8,260.
- **References:** ASC 330-10-35-1B; ASC 330-10-20-Net Realizable Value.

### A3 · PP&E (net) & Prepaid expenses — capitalizable cost + reclass

- Home Build invoice **$85,300** was fully capitalized to PP&E. Correct PP&E =
  HVAC 75,000 + sales tax 4,500 + shipping 800 = **80,300**. The **$5,000 annual
  maintenance** (1/1/yr4–12/31/yr4) is a **prepaid expense** (amortized over 12
  months from Jan yr4).
- **Adjusting entry:** `Dr Prepaid expenses 5,000 / Cr PP&E 5,000` (pure
  reclass — **no NI/RE impact**, since depreciation/amortization don't start
  until January year 4).
- **Enter `D7 = +5,000` and `D11 = −5,000`.**
- **References:** ASC 360-10-30-1; ASC 360-10-30-2.

### A4 · Intangible assets (net) — R&D expensing

- The $20,000 patent addition = **salary/benefit costs for R&D** on a new
  product ⇒ must be **expensed**, not capitalized.
- **Adjusting entry:** `Dr Research and development expense 20,000 / Cr Patent
  20,000` (reduces NI & RE).
- **Enter `D12 = −20,000`.** RE impact −20,000.
- **References:** ASC 350-30-25-1 and 25-3; ASC 730-10-25-1 and 25-2.

### A5 · Accounts payable & accrued expenses — accrual / period cutoff

- **Guardian LLC $27,500** legal fees are for **Dec yr3** services but were
  booked in Jan yr4 ⇒ accrue in Dec yr3.
- **Clean Co. $6,000** janitorial is for **Dec yr3** services but booked to A/P
  on 1/4/yr4 ⇒ accrue in Dec yr3.
- **Distractors (no adjustment):** Jan-yr4 sales commissions $8,000 & consulting
  $7,000 (correctly in Jan yr4); f.o.b.-destination inventory received in Jan yr4
  (Machine Co 18,000, Match Corp 22,200); computer supplies ordered & received
  Jan yr4 (8,500).
- **Adjusting entry:** `Dr Legal expense 27,500 · Dr General & administrative
  expense 6,000 · Cr Accounts payable 33,500` (reduces NI & RE by 33,500).
- **Enter `D16 = +33,500`.** RE impact −33,500.
- **Reference:** FASB **Statement of Financial Accounting Concepts No. 8**,
  Conceptual Framework for Financial Reporting, pages 3–4.

### A6 · Retained earnings — rollup of all income-statement effects

- `(64,760) = (3,000) + (8,260) + (20,000) + (27,500) + (6,000)`
- Note the PP&E/Prepaid reclass (A3) does **not** hit RE.
- **Enter `D27 = −64,760`.**

**Answer vector (only the cells a candidate touches):**

| Cell                        | Line item                             |     Value |
| --------------------------- | ------------------------------------- | --------: |
| D5                          | Accounts receivable (net)             |    −3,000 |
| D6                          | Inventory                             |    −8,260 |
| D7                          | Prepaid expenses                      |    +5,000 |
| D11                         | Property, plant and equipment (net)   |    −5,000 |
| D12                         | Intangible assets (net)               |   −20,000 |
| D16                         | Accounts payable and accrued expenses |   +33,500 |
| D27                         | Retained earnings                     |   −64,760 |
| D4, D17, D21, D25, D26, D28 | (distractor rows)                     | blank / 0 |

---

## 6. Grading / partial-credit notes

- Nothing partial-credit is _printed on the item_ (it's a retired sample, not a
  scoring key), **but the structure is intrinsically step-graded**: each column-D
  cell is an independent numeric entry that can be right or wrong on its own.
  This is exactly our `grading.rs` model (`Σ weight × correct`, per-cell,
  method-vs-slip).
- **Signs matter** — increases positive, decreases negative — so the answer key
  must store signed integers.
- **Whole dollars**, so `tolerance` = 0 (or ≤ 0.5). Our default numeric tolerance
  handling in `logic::numeric_matches` (strips `$ , %`) fits.
- **Dependency caveat for weighting:** `D27` (retained earnings) and the
  auto-calc subtotals are _derived_ from the other cells. The AICPA UI
  auto-calculates subtotals, and it grades `D27` on its face value (−64,760),
  independent of whether the candidate also got A1–A5 right. If we replicate
  auto-calc we should **not** grade subtotal cells; if we don't auto-calc, we can
  grade `D27` as its own step (candidate must sum correctly).

---

## 7. Official TBS UI observations (for the desktop/iOS surface work)

Directly visible in the rendered pages (cross-ref `04-aicpa-official-tbs-ui.md`,
`09-desktop-surface-plan.md`, `10-ios-surface-plan.md`):

- A persistent **EXHIBITS** panel with tabbed exhibit **hyperlinks**, plus
  "close all exhibits" and single-window/tiled toggle icons.
- Each exhibit opens as a **draggable, scrollable window** with a dark title bar
  and a red ✕ close button (with horizontal + vertical scrollbars).
- The work area is a **spreadsheet**: lettered columns A–E, numbered rows, bold
  auto-calc subtotal rows, and a **`123` glyph marking each editable numeric
  cell**. Prev/next **scroll arrows** at the bottom.
- "Scroll down to complete all parts of this task" + "Amounts in column E and
  subtotals will calculate automatically" ⇒ **live-recalc spreadsheet** is a
  real expectation for numeric TBS fidelity.

---

## 8. Encoding into our model

Note type fields (`rslib/src/ankountant/notetypes.rs::tbs_fields`): `tbs_type`,
`prompt`, `exhibits_json`, `steps_json`, `schema_tag`, + provenance
(`source_passage`, `gen_method`, `checker_status`). Grading
(`rslib/src/ankountant/grading.rs`) consumes `steps_json` as
`[{id, answer_key, weight?, tolerance?}]`; `answer_key` is a **scalar** for
numeric cells or an **object** (`{account, side, amount}`) for JE lines. The
seed authoring format (`seed_content.json`) additionally carries `label` (display
only, ignored by the grader) and `title`/`body` exhibits.

### 8.1 `tbs_type` / `schema_tag`

- `tbs_type = "numeric"`
- `schema_tag`: suggest `"far.balancesheet.adjustments.v1"` (a stable per-shape/
  template tag; keep whatever convention `notetypes`/`seed` settles on).

### 8.2 `exhibits_json` (current `[{title, body}]` model)

`body` is the only content slot today, so each exhibit becomes a text/markdown
blob. Tables render as pipe tables; the email thread and stamped invoices go in
as text (the **posting stamp becomes a labeled block** — we lose the visual
overlay). Excerpt (full item would carry all 7):

```json
[
    {
        "title": "Email regarding sale of accounts receivable",
        "body": "From: senioraccountant@blearco.com | To: armanager@blearco.com | Sent: 12/30/year 3 | Subject: RE: Sale of Accounts Receivable\n\nAccounts Receivable Manager:\nI have already recorded the following entry for the December close to record the sale:\n  Dr. Cash 27,000\n  Cr. Accounts receivable 27,000\n\n---\nFrom: armanager@blearco.com | To: senioraccountant@blearco.com | Sent: 12/29/year 3 | Subject: Sale of Accounts Receivable\n\nOn December 28, we entered into an agreement to sell $30,000 of our outstanding accounts receivable balances of our east coast operations. The agreement was made without recourse for a 10% fee. We received $27,000 from the buyer today to settle the transaction."
    },
    {
        "title": "Year-end inventory analysis",
        "body": "Blear Co. — Inventory Analysis — As of December 31, year 3\n\n| Product | Qty subledger | Qty physical | Unit cost | Repl. cost | NRV | Normal margin |\n|---|--:|--:|--:|--:|--:|--:|\n| A | 1,500 | 1,450 | $25 | $26 | $20 | $2 |\n| B | 140 | 148 | $30 | $37 | $35 | $2 |\n\nNote: physical count 12/31/year 3; FIFO; not reflected in the unadjusted balance."
    },
    {
        "title": "Accounts payable subledger",
        "body": "…pipe table (see §4 E3)…"
    },
    {
        "title": "Accrued expense general ledger detail",
        "body": "…pipe table (see §4 E4)…"
    },
    {
        "title": "Home Build Corp. Invoice",
        "body": "INVOICE 0567, 12/31/year 3.\n[POSTED STAMP] Posted to: PP&E · Amount Posted: $85,300 · Period: Dec year 3.\nLines: HVAC 75,000; Annual maintenance 1/1/yr4–12/31/yr4 5,000. Subtotal 80,000; tax 4,500; S&H 800; TOTAL $85,300."
    },
    {
        "title": "Guardian LLC Invoice",
        "body": "Invoice 22544855, Jan 9 year 4.\n[POSTED STAMP] Posted to: Legal expense #6100 · Amount posted: $27,500 · Period: Jan year 4.\nServices 12/1/year 3–12/31/year 3: December year 3 legal fees for general corporate matters. $27,500. Net 60."
    },
    {
        "title": "Intangible Asset Summary",
        "body": "…rollforward pipe table (see §4 E7); Note: $20,000 patent addition = R&D salary/benefit costs for a new product."
    }
]
```

### 8.3 `steps_json` (what `grading.rs` grades)

One step per editable cell. `answer_key` is a signed integer; `tolerance: 0`
(whole dollars). Include the six distractor rows as `answer_key: 0` **only if**
we surface those rows as inputs and want to reward "correctly left blank";
otherwise grade just the seven that move. Weights below are illustrative (equal
across the 7 substantive cells).

```json
[
    {
        "id": "D5",
        "label": "Accounts receivable (net)",
        "answer_key": -3000,
        "tolerance": 0,
        "weight": 0.1428
    },
    {
        "id": "D6",
        "label": "Inventory",
        "answer_key": -8260,
        "tolerance": 0,
        "weight": 0.1428
    },
    {
        "id": "D7",
        "label": "Prepaid expenses",
        "answer_key": 5000,
        "tolerance": 0,
        "weight": 0.1428
    },
    {
        "id": "D11",
        "label": "Property, plant and equipment (net)",
        "answer_key": -5000,
        "tolerance": 0,
        "weight": 0.1428
    },
    {
        "id": "D12",
        "label": "Intangible assets (net)",
        "answer_key": -20000,
        "tolerance": 0,
        "weight": 0.1428
    },
    {
        "id": "D16",
        "label": "Accounts payable and accrued expenses",
        "answer_key": 33500,
        "tolerance": 0,
        "weight": 0.1428
    },
    {
        "id": "D27",
        "label": "Retained earnings",
        "answer_key": -64760,
        "tolerance": 0,
        "weight": 0.1432
    }
]
```

### 8.4 Provenance fields

- `source_passage`: the per-adjustment ASC citations (A1–A5 above) — this item is
  a natural fixture for validating a **citation-aware** answer key.
- `gen_method`: `"aicpa_retired_sample"`; `checker_status`: `"human_verified"`
  (balances to $1,755,040).

### 8.5 Fidelity gaps vs. the real item (flag for schema evolution)

1. **No structured grid model.** We store answers as `D5…D27` step ids but have
   no first-class "spreadsheet with given columns B/C + auto-calc E/subtotals".
   The reference balances (Year 2 / Year 3 unadjusted) currently have to live in
   `prompt` or an exhibit `body`. See `11-seed-and-schema-plan.md`.
2. **No exhibit typing.** Everything is `{title, body}` text; we can't mark an
   exhibit as `email` / `invoice` / `table` / `stamp`, which the
   `document-review` shape will need. Consider a forward-compatible
   `{title, kind, body}` (or `content` union) so `numeric` and `document-review`
   share one exhibit schema.
3. **"Leave blank" semantics.** The grader compares submitted vs. key; we need a
   convention that _blank == 0 == correct_ for distractor rows (don't punish a
   correctly-empty cell).

---

## 9. What this teaches us for `research` & `document-review`

Although this file contains neither shape, it is the best evidence we have for
the _house style_ both will inherit:

- **Citation format for `research`.** Real AICPA answer keys cite
  `ASC <topic>-<subtopic>-<section>-<paragraph>` (e.g., `ASC 860-10-05-14`,
  `ASC 330-10-35-1B`, `ASC 360-10-30-2`) and occasionally non-ASC authorities
  (`FASB Statement of Financial Accounting Concepts No. 8 … pages 3–4`). A
  `research` `answer_key` should therefore be a **structured citation**
  (topic/subtopic/section/paragraph) with tolerant matching, not a free-text
  string — and must allow **multiple acceptable citations** (this item lists 2–3
  ASC refs per issue). See `05-research-sim-and-licensing.md`.
- **Exhibit vocabulary for `document-review`.** The exhibit set here (email
  thread, vendor **invoice with a posting stamp**, subledger, GL detail,
  rollforward summary) is precisely the material a document-review TBS drops
  "which treatment applies?" blanks into. The **posting stamp** ("Posted to: … ·
  Amount Posted: … · Accounting Period: …") is the exact hook a doc-review item
  uses to ask _"was this posted to the right account / period?"_. See
  `06-docreview-sim.md`.
- **Distractor design.** Note how E3/E4 are stuffed with _correctly-recorded_
  items (Jan-yr4 accruals, f.o.b.-destination receipts) so the candidate must
  _not_ adjust them. Both deferred shapes should carry deliberate distractors.
- **One scenario → many sub-issues.** A single company + one exhibit set drives
  6 independent gradable decisions. Our seed can mine this pattern: reuse a rich
  scenario across `numeric`, `document-review`, and `research` items.

---

## 10. Cross-references

- `04-aicpa-official-tbs-ui.md` — the UI observations in §7 corroborate/extend it.
- `05-research-sim-and-licensing.md` — citation-format evidence in §9.
- `06-docreview-sim.md` — exhibit vocabulary + stamp hook in §4/§9.
- `08-rust-backend-changemap.md`, `11-seed-and-schema-plan.md` — schema gaps in §8.5.
- Model of record: `rslib/src/ankountant/{notetypes,grading,seed_content}.rs/json`.

---

## Appendix A — extraction method / reproducibility

The PDF text is **font-obfuscated** (readable when rendered, scrambled when
copied): body text uses a two-rule glyph cipher — encoded bytes `0x46–0x5F`
(`F`–`_`) decode to lowercase `a`–`z` (Caesar), and bytes `0x05–0x3F` decode to
`chr(byte + 27)` (space = `\x05`, `$` = `\t`, `,` = `\x11`, digits `0`–`9` =
`\x15`–`\x1e`, uppercase `A`–`Z` = `&`–`?`). Because the _glyphs_ draw correctly,
the **authoritative extraction was rendering each page to PNG at ~173 DPI and
reading it visually**; the decoded text stream was used only as a spelling
cross-check. No tool wrote anything outside this markdown file (scratch in
`/tmp`). `pdftotext` is not installed on this machine; `PyMuPDF` (`fitz`) is.
