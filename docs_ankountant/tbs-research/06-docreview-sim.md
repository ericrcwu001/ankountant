# 06 — Document Review Simulation (DRS) Format Research

> Research for Ankountant's **document-review TBS surface**. Goal: understand how the
> real CPA-exam Document Review Simulation (DRS) is structured and graded, transcribe
> representative items **with the option list per blank**, and map it onto our note-type
> model (`exhibits_json` + `steps_json`, where `steps = {id, answer_key, weight}` and each
> blank is a "which treatment applies?" confusion-set choice graded per-blank with partial
> credit).
>
> Method: `agent-reach` skill — web search (Exa unavailable in this env) + Jina Reader
> (`curl -s https://r.jina.ai/<URL>`). Sources listed at the bottom; all accessed 2026-07-02.

---

## 1. What a DRS is (structure)

A **Document Review Simulation** is a Task-Based Simulation (TBS) format the AICPA
introduced in **July 2016**. Instead of typing values into cells, the candidate is given a
**realistic primary document** (a memo, letter, engagement/audit report, financial-statement
footnote, contract clause, or an internal work-product list) in which **certain words,
phrases, sentences, or whole paragraphs are highlighted / underlined**. The candidate clicks
each highlighted span, which opens a **dropdown of answer choices**, and must pick the
**one option** that makes the document correct given the supporting materials.

AICPA's own description (via SuperfastCPA):

> "The DRS presents a realistic task that simulates what a newly licensed CPA might do on
> the job. The item features a **primary document** as well as **related source materials**
> for candidate review. Highlighted words, phrases, sentences, or paragraphs in the DRS
> document may or may not be correct, requiring the candidate to select appropriate edits
> based on the relevant source materials."

**The option list for each blank is almost always shaped as a "treatment" choice:**

- **Retain the original text** (i.e., "keep as-is" / "no change needed"), **and**
- (usually) **Delete the text**, **and**
- **3–5 "Replace with …" alternatives**, each a differently-worded / differently-computed
  version of the phrase.

So each blank is functionally _"which of these ~5–7 candidate treatments is the correct one
for this phrase?"_ — exactly the **confusion-set** framing in our model. "Retain" and
"Delete" are just two members of the confusion set.

### Tabs / surfaces in a DRS (from Going Concern / Gleim)

Every DRS is a multi-tab workspace:

| Tab                          | Contents                                                                                                         |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Document Review**          | the primary document being edited (holds the blanks)                                                             |
| **Exhibits**                 | supporting source docs: emails, letters, invoices, balance sheets, memos, meeting minutes, contracts, workpapers |
| **Financial Statements**     | (when present) related financial data, sometimes **including notes to the financials**                           |
| **Authoritative Literature** | FASB ASC / AICPA Prof. Standards / IRC — for research                                                            |
| **Help**                     | how to operate the review/edit UI                                                                                |

UI mechanics: a modifiable span is **blue + underlined** with a small icon; clicking opens
the choice list; after you accept a choice the icon shows a **check mark**. You must
explicitly choose for **every** blank — _including choosing "Retain the original text" when
the text is already correct_. **A blank with no selection is graded wrong even if the
original text happened to be correct.**

---

## 2. Typical sizes (blanks, document length, choices, exhibits)

- **Blanks per DRS:** roughly **5–12 modifiable spans** ("callouts"). Multiple summaries put
  the _graded sub-items_ of a typical simulation in the **3–7** range; the classic AICPA-style
  DRS reproduced below has **8** callouts. Treat **~6–10** as the design center.
- **Choices per blank:** **5–7 answer choices** (Going Concern: _"You may be presented with
  five to seven answer choices for each underlined section … one option to retain the original
  text, and sometimes another to delete the text. The other three to five … offer various
  ways to revise the text."_). Not every blank offers "Delete" (see KCN callout #8 below).
- **Document length:** one to a few screens — a full memo / one-page request list / a
  footnote or two. Long enough to feel like a real work-product, short enough to read in a
  couple of minutes.
- **Exhibits:** typically **2–5** supporting exhibits (trial balance, several emails/memos, a
  contract). The core skill is **requirement-driven exhibit triage** — read the blank, then
  go find the _one_ exhibit fact that resolves it. "Detect shared meaning between the answer
  choices and the exhibits" (Going Concern) — i.e., the correct option often **restates an
  exhibit fact in different words**.
- **Time budget:** ~**18 minutes per TBS** on average (candidate-facing guidance).

---

## 3. Grading (per-blank, partial credit, weighting)

This is the part that matches our model most directly.

- **Each blank is scored independently** ("each 'box' on the SIMS portion is graded
  separately" — another71; FreeFellow: _"The grader scores each option independently"_).
- **Partial credit is real.** You get credit for the blanks you get right regardless of the
  others. A 5-blank item where you nail 3 and miss 2 earns ~60% of that item's contribution,
  **not zero**.
- **Document-review blanks are exact-match to the AICPA-designated option** (unlike numeric
  cells, which use a tolerance band): _"Document review options: correct if you chose the
  AICPA-designated option."_ (FreeFellow). So a blank's grade is binary **correct / incorrect**,
  then weighted.
- **No penalty for wrong answers**, and **never leave a blank empty** (empty = 0; a guess has
  positive expected value). This is why the UI forces a choice including "Retain".
- **Weighting exists but is opaque.** Public sources agree individual sub-items carry weight
  and that harder items/sub-items are worth more, but the exact per-blank weights are **not
  published** by the AICPA ("What is unknown is how much WEIGHT is assigned and where" —
  another71). For our purposes: model a **per-blank `weight`** and default it to `1`, with the
  ability to bump specific blanks.
- **TBS share of section score:** **50%** for AUD/FAR/REG/BAR/TCP (ISC is 40%). MCQs are the
  other half. Scores are scaled 0–99, not raw percent-correct.
- **One documented exception to per-box grading (not DRS-specific):** the _research_ cite
  question is all-or-nothing. DRS blanks are **not** all-or-nothing — they're per-blank.

**Grading model for us:** `score = Σ(weightᵢ · [chosenᵢ == correctᵢ]) / Σ(weightᵢ)`, evaluated
per blank, stored per blank.

---

## 4. Where DRS appears (and the FAR angle)

- DRS launched on **AUD, FAR, and REG** (July 2016) and remains **AUD-heavy** — most public
  examples are audit work-products (request lists, engagement letters, audit reports,
  workpaper memos). AUD DRS questions cluster into: _does evidence support an assertion?_,
  _is this procedure appropriate?_, _does this document contain a misstatement/inconsistency?_
- **On FAR, DRS shows up as disclosure-/reporting-prep tasks** (FreeFellow: _"Document review
  … appears on FAR for disclosure-prep tasks."_). The draft document is typically a
  **financial-statement footnote, a MD&A / financial-highlights memo, or an accounting memo**,
  and the source tab is the **financial statements + notes**. The candidate reconciles the
  narrative to the numbers/standard (revenue recognition ASC 606, leases ASC 842,
  contingencies & commitments, subsequent events, etc.).
- REG uses DRS for tax documents (returns/positions with erroneous or irrelevant figures).
- The Discipline sections (BAR/TCP) lean on the closely-related **"open response"** format
  (fill-in / dropdown / matching), which encodes the same way.

**Implication for our FAR-focused build:** the _mechanic_ is identical to AUD; only the
document genre differs (footnote/memo/disclosure instead of audit request list). Our surface
should treat the primary document as generic rich text with inline blanks, and let the
`exhibits_json` carry either audit exhibits **or** a financial-statements+notes bundle.

---

## 5. Verbatim / representative examples (with option lists per blank)

### Example A — AUD, **fully verbatim**: KCN "Audit Request List" DRS

The most widely reproduced AICPA-style DRS is the **Keystone Computers & Networks, Inc. (KCN)**
audit-request-list item (illustrative case from Whittington & Pany, _Principles of Auditing &
Other Assurance Services_, McGraw-Hill; surfaced verbatim on Chegg). It is an excellent
canonical DRS: one primary document (a draft request list) + 4 exhibits + **8 callouts**, each
with a **Retain / Delete / 3× Replace** confusion set.

**Prompt (verbatim):**

> This simulation presents an audit request list document for materials requested of management
> … The CPA firm Adams, Barnes & Company is preparing for the year 20X5 audit of Keystone
> Computers & Networks Incorporated (KCN), a calendar year-end nonissuer. An audit staff member
> started with the 20X4 year audit request list for KCN and updated it as he thought appropriate.
> **Required:** Your job as senior on the engagement is to review and revise the year 20X5
> request list for KCN as needed. For each of the sentences called out … determine if the
> current language is **appropriate as is, should be removed altogether, or replaced with any of
> the provided alternatives**. … The **materiality** for the year 20X5 audit has been set at
> **$300,000**.

**Exhibits (verbatim, condensed):**

- **Exhibit 1 — KCN Working Trial Balance** (12/31/X4 audited vs 12/31/X5 unadjusted, account
  numbers like `1050.10 Accounts receivable-trade`, `2100.00 Software development cost`,
  `7100.10 Rent`, `7140.10 Utilities`, etc.).
- **Exhibit 2 — Memo to Files** (partner Charles Adams, 11/5/20X5): Plumbtree intangible
  (~$1,000,000 remaining, amortized $200k/yr; may write off "half or more" this year); earnings
  down ~40%; the company **started capitalizing software development costs this year**; and
  _"There will be an increase in the accounts receivable from officers as President Best asked
  for and obtained **a loan** from the company … a loan agreement Mr. Steele signed … Because
  its amount was slightly below the amount necessary for Board of Directors approval, the matter
  was not addressed by the Board."_
- **Exhibit 3 — Forwarded email (President Best):** _"…let's make sure that we **capitalize**
  these costs ($178,000) because … we may be able to develop software… "_ + PS: rent is going
  up but the **new lease has no payment for the first three months** (abatement).
- **Exhibit 4 — Email (Manager Karen West):** allowance for bad debts $96,000 → $104,000;
  Willay Co. receivable of **$208,234 written off**; ~$32,000 more possibly uncollectible;
  _"we definitely need to consider the adequacy of the allowance for bad debts."_

**Primary document** = "Keystone Computers & Networks, Inc. — Year Ended December 31, 20X5 —
Audit Request List (Draft 1)", a bulleted list of requested items, 8 of which are callouts.

**The 8 blanks and their verbatim option lists** ("Retain the original text." is an option on
all; only #8 omits "Delete the text."):

**Callout #1** — original: _"Accounts receivable summarized by date of most recent purchase."_

- Retain the original text.
- Delete the text.
- Replace with "Accounts receivable aged by date due."
- Replace with "Accounts receivable summarized by length of business relationship with KCN."
- Replace with "Accounts receivable matched with sales items."

**Callout #2** — original: _"Invoices supporting depreciation expense for the year."_

- Retain the original text.
- Delete the text.
- Replace with "Lawyer's letter response on expected life of fixed assets."
- Replace with "Cash deposit slip for increase in cash for 20X5."
- Replace with "Schedule of details of depreciation expense calculation for 20X5."

**Callout #3** — original: _"Software development cost invoices and other support."_

- Retain the original text.
- Delete the text.
- Replace with "Confirmation requests to developers involved with software development costs."
- Replace with "Details of amortization of software development cost."
- Replace with "Physical examples of the software developed."

**Callout #4** — original: _"Vouchers supporting increase in leasehold improvements."_

- Retain the original text.
- Delete the text.
- Replace with "Schedule of additions and retirements to leasehold improvements."
- Replace with "Schedule of descriptions of estimated lives of this year's new additions."
- Replace with "Schedule of tax depreciation for this year's new additions."

**Callout #5** — original: _"Detailed analysis and reconciliation of each unpaid account payable at year-end."_

- Retain the original text.
- Delete the text.
- Replace with "Trial balance of accounts payable at the balance sheet date."
- Replace with "List of amortization of accounts payable at the balance sheet date."
- Replace with "Current and past credit ratings of each supplier."

**Callout #6** — original: _"Documentation supporting change in capital stock outstanding."_

- Retain the original text.
- Delete the text.
- Replace with "Documentation of cash receipts related to new stock issuance."
- Replace with "Addresses of new shareholders."
- Replace with "Schedule supporting retained earnings effect relating to current stock."

**Callout #7** — original: _"Management's review of receivables from officers."_

- Retain the original text.
- Delete the text.
- Replace with "Cash of deposit receipt related to new receivables from officers."
- Replace with "Copy of Board of Director approval of new loans from officers."
- Replace with "Copy of loan agreement with Mr. Best."

**Callout #8** — original: _"Account 7140.10 expense analysis."_ (7140.10 = Utilities)

- Retain the original text.
- Replace with "Account 1000.30 detailed analysis."
- Replace with "Account 5100.10 detailed analysis."
- Replace with "Account 7100.10 expense analysis."
- Replace with "Account 7200.10 expense analysis."

**Reasoned answer key** _(derived from the exhibits + $300,000 materiality — this is an
analytically-defensible key for illustrating `correct_option`, not an official AICPA answer
key; the public transcriptions do not include the graded solution):_

| # | Reasoned correct treatment                                                        | Why (exhibit tie)                                                                                                                        |
| - | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | Replace → "Accounts receivable **aged by date due**."                             | Ex4 flags allowance adequacy; aging by due date (not by purchase date) supports collectibility.                                          |
| 2 | Replace → "**Schedule of details of depreciation expense calculation** for 20X5." | Depreciation is computed, not supported by invoices.                                                                                     |
| 3 | **Retain**                                                                        | Company began capitalizing $178k software dev costs (Ex2/Ex3); auditor needs the invoices/support to test capitalization.                |
| 4 | Replace → "**Schedule of additions and retirements to leasehold improvements**."  | To audit a PP&E change you want the additions/retirements roll rather than only "vouchers for an increase".                              |
| 5 | Replace → "**Trial balance of accounts payable** at the balance sheet date."      | "Each unpaid AP" is impractical vs $300k materiality; AP completeness is tested from the AP trial balance + unrecorded-liability search. |
| 6 | **Delete**                                                                        | TB shows capital stock / paid-in capital unchanged X4→X5 — there is no change to document.                                               |
| 7 | Replace → "**Copy of loan agreement with Mr. Best**."                             | Ex2: it is a **related-party officer loan** with a signed agreement, not board-approved; get the agreement itself.                       |
| 8 | Replace → "**Account 7100.10 (Rent) expense analysis**."                          | Ex3 PS: lease terms changed (rent increase + 3-month abatement); rent is significant. Utilities (7140.10) is immaterial.                 |

> This one item alone gives us a clean AUD confusion-set template: every blank = _pick the
> correct audit-request treatment from a set that mixes "keep / drop / wrong-basis variants"._

### Example B — FAR, **AICPA official sample test**: net-revenues MD&A memo

The AICPA's own sample test (referenced by SuperfastCPA and Gleim) contains a **FAR-flavored
DRS** whose primary document is a **management financial-highlights / MD&A-style memo**, and
whose source tab is the **financial statements _including the notes_**. One highlighted
sentence asserts a growth rate and an ending balance; the candidate must verify them against
the statements:

> "When you click on one of the highlighted sentences, it will expand to give you several
> choices. For this sentence, you basically need to figure out if the **8.5% figure** and the
> ending **net revenues of $32,498** are correct or not. You would … open up the financial
> statements to figure this out."

The exact AICPA option strings aren't published verbatim, but the mechanic is clear: the
blank is a whole **sentence variant**, and the confusion set is a set of sentences with
different (rate, dollar) pairs. **Representative** reconstruction of that blank:

- Retain → "Net revenues grew **8.5%** to **$32,498** in the current year."
- Replace → "Net revenues grew **6.2%** to **$32,498** …"
- Replace → "Net revenues grew **8.5%** to **$34,102** …"
- Replace → "Net revenues **declined 8.5%** to **$32,498** …"
- Replace → "Net revenues grew **6.2%** to **$34,102** …"

This confirms FAR DRS blanks can wrap a **numeric fact inside a sentence choice** — a numeric
check expressed as a dropdown, which encodes identically to a text confusion set.

### Example C — FAR, **representative footnote DRS** (synthesized, test-accurate)

A footnote/disclosure DRS is the FAR genre most relevant to us, and none are published
verbatim (they're behind review-course paywalls). The following is a **synthesized but
test-accurate** revenue-recognition footnote item, built to the same rules, and used as the
JSON worked example in §6. Correct options are derivable from its exhibits.

**Primary document — "Note 7. Revenue Recognition" (draft):**

> The Company recognizes revenue under ASC 606. For its annual software-as-a-service (SaaS)
> subscription contracts, the Company recognizes subscription revenue **‹B1: at the point the
> contract is signed›**. Implementation services that are **not distinct** from the subscription
> are recognized **‹B2: over the subscription term›**. The Company's standard terms include a
> 30-day right of return; the Company records revenue **‹B3: in full at contract inception with
> no adjustment for expected returns›**. For bundled arrangements that include a perpetual
> software license and one year of technical support, the transaction price is allocated
> **‹B4: entirely to the software license›**. Total subscription revenue recognized in 20X5 was
> **‹B5: $4,200,000›**.

**Exhibits:** Ex1 — standard contract terms (subscription billed annually, service delivered
continuously; 30-day refund right; license + PCS are separate performance obligations with
observable standalone prices); Ex2 — revenue schedule / trial balance (subscription revenue
earned in 20X5 = **$3,900,000**; $300,000 billed-not-yet-earned deferred); Ex3 — controller
email confirming expected returns are estimable and immaterial-but-present.

**Blanks + option lists (confusion sets):**

**B1** (`confusion_set: revrec_timing_saas`)

- Retain → "at the point the contract is signed."
- **Replace → "ratably over the subscription period as the customer simultaneously receives and consumes the benefit."** ✅
- Replace → "when the customer is invoiced."
- Replace → "when cash is collected."
- Replace → "at the point control of the software transfers to the customer."

**B2** (`confusion_set: revrec_bundled_nondistinct`)

- **Retain → "over the subscription term."** ✅ (not distinct ⇒ combine with the subscription PO)
- Replace → "immediately upon completion of implementation."
- Replace → "at contract inception."
- Replace → "as a separate performance obligation using a cost-to-cost input method."
- Delete the sentence.

**B3** (`confusion_set: variable_consideration_returns`, **weight 2**)

- Retain → "in full at contract inception with no adjustment for expected returns."
- **Replace → "net of a refund liability for expected returns (variable consideration), constrained to the amount probable of not significantly reversing."** ✅
- Replace → "only after the 30-day return period lapses, deferring all revenue until then."
- Replace → "net of actual returns recorded in the subsequent period."

**B4** (`confusion_set: transaction_price_allocation`)

- Retain → "entirely to the software license."
- **Replace → "to each performance obligation based on relative standalone selling prices."** ✅
- Replace → "equally between the license and the support."
- Replace → "to the support obligation first, with the residual to the license."

**B5** (`confusion_set: figure_ties_to_schedule`, **weight 2**) — numeric-in-sentence

- Retain → "$4,200,000."
- **Replace → "$3,900,000."** ✅ (Ex2: $300k is deferred/unearned)
- Replace → "$4,500,000."
- Replace → "$3,600,000."

---

## 6. Mapping to OUR model (`exhibits_json` + `steps_json`)

**Design decisions:**

1. **The primary document lives in `exhibits_json`** as an exhibit with `role: "document"`,
   holding the body text with **N inline blank markers**. Supporting exhibits are the other
   entries. (Only `exhibits_json` + `steps_json` exist on the note type, so the body has to
   ride in `exhibits_json`.)
2. **Blank markers** are inline tokens that reference a step id. Recommended: an HTML-ish span
   that keeps the _original_ text visible inline —
   `… recognizes subscription revenue <blank step="s1">at the point the contract is signed</blank>.`
   (A bare token like `{{s1}}` also works if the original phrase is stored on the step as
   `original_text`.) The renderer replaces each `<blank>` with a dropdown.
3. **Each blank = one step = one confusion-set choice.** The note type's
   `steps = {id, answer_key, weight}` is **extended per blank** with `options[]`,
   `correct_option`, and `confusion_set_id`:
   - `id` — matches the inline marker.
   - `options[]` — the confusion set: `{id, text, kind}` where `kind ∈ {keep, delete, replace}`
     (`keep` is "Retain the original text", `delete` is "Delete the text", `replace` is a
     variant). Order can be shuffled at render time.
   - `correct_option` — the winning option id. **`answer_key` == `correct_option`** (same
     value; keep both names or alias one to the other).
   - `confusion_set_id` — stable id of the treatment-confusion this blank tests; lets many
     blanks (across items) reuse/track the same confusion for analytics and for our
     "confusion-set" learning model.
   - `weight` — per-blank weight (default `1`; bump high-value blanks, e.g. B3/B5 above).
   - (optional) `original_text`, `rationale`, `exhibit_refs[]`.
4. **Grading** (matches the real exam): per blank, `correct = (chosen == correct_option)`;
   `item_score = Σ(weightᵢ·correctᵢ) / Σ(weightᵢ)`. Binary per blank, then weighted —
   partial credit falls out naturally. Unanswered ⇒ incorrect (never null-skip).
5. **Attempt Log note** stores **per-blank results** (one row per blank), so it slots straight
   into a per-blank confusion-set mastery model.

### Concrete JSON — the FAR footnote item (Example C)

`exhibits_json`:

```json
{
    "document": {
        "id": "doc",
        "role": "document",
        "kind": "footnote",
        "title": "Note 7. Revenue Recognition (draft)",
        "body_html": "<p>The Company recognizes revenue under ASC 606. For its annual software-as-a-service (SaaS) subscription contracts, the Company recognizes subscription revenue <blank step=\"s1\">at the point the contract is signed</blank>. Implementation services that are not distinct from the subscription are recognized <blank step=\"s2\">over the subscription term</blank>. The Company's standard terms include a 30-day right of return; the Company records revenue <blank step=\"s3\">in full at contract inception with no adjustment for expected returns</blank>. For bundled arrangements that include a perpetual software license and one year of technical support, the transaction price is allocated <blank step=\"s4\">entirely to the software license</blank>. Total subscription revenue recognized in 20X5 was <blank step=\"s5\">$4,200,000</blank>.</p>"
    },
    "exhibits": [
        {
            "id": "ex1",
            "kind": "text",
            "title": "Exhibit 1 — Standard Contract Terms",
            "body": "Subscriptions are billed annually in advance; the service is delivered continuously over the 12-month term. Customers have a 30-day right of return. A perpetual license and one year of post-contract support (PCS) are separate performance obligations, each with an observable standalone selling price."
        },
        {
            "id": "ex2",
            "kind": "table",
            "title": "Exhibit 2 — 20X5 Revenue Schedule",
            "columns": ["Item", "Amount"],
            "rows": [
                ["Subscription billings in 20X5", "4,200,000"],
                ["Portion unearned at 12/31/20X5 (deferred)", "300,000"],
                ["Subscription revenue earned in 20X5", "3,900,000"]
            ]
        },
        {
            "id": "ex3",
            "kind": "text",
            "title": "Exhibit 3 — Email from Controller",
            "body": "Returns are estimable from history; they occur every year and are not zero, though individually small. Please make sure the note reflects the returns policy."
        }
    ]
}
```

`steps_json` (each step is one blank / confusion-set choice; `answer_key === correct_option`):

```json
[
    {
        "id": "s1",
        "confusion_set_id": "revrec_timing_saas",
        "original_text": "at the point the contract is signed",
        "options": [
            {
                "id": "o1",
                "kind": "keep",
                "text": "at the point the contract is signed"
            },
            {
                "id": "o2",
                "kind": "replace",
                "text": "ratably over the subscription period as the customer simultaneously receives and consumes the benefit"
            },
            {
                "id": "o3",
                "kind": "replace",
                "text": "when the customer is invoiced"
            },
            { "id": "o4", "kind": "replace", "text": "when cash is collected" },
            {
                "id": "o5",
                "kind": "replace",
                "text": "at the point control of the software transfers to the customer"
            }
        ],
        "correct_option": "o2",
        "answer_key": "o2",
        "weight": 1,
        "exhibit_refs": ["ex1"]
    },
    {
        "id": "s2",
        "confusion_set_id": "revrec_bundled_nondistinct",
        "original_text": "over the subscription term",
        "options": [
            {
                "id": "o1",
                "kind": "keep",
                "text": "over the subscription term"
            },
            {
                "id": "o2",
                "kind": "replace",
                "text": "immediately upon completion of implementation"
            },
            { "id": "o3", "kind": "replace", "text": "at contract inception" },
            {
                "id": "o4",
                "kind": "replace",
                "text": "as a separate performance obligation using a cost-to-cost input method"
            },
            { "id": "o5", "kind": "delete", "text": "Delete the sentence." }
        ],
        "correct_option": "o1",
        "answer_key": "o1",
        "weight": 1,
        "exhibit_refs": ["ex1"]
    },
    {
        "id": "s3",
        "confusion_set_id": "variable_consideration_returns",
        "original_text": "in full at contract inception with no adjustment for expected returns",
        "options": [
            {
                "id": "o1",
                "kind": "keep",
                "text": "in full at contract inception with no adjustment for expected returns"
            },
            {
                "id": "o2",
                "kind": "replace",
                "text": "net of a refund liability for expected returns (variable consideration), constrained to the amount probable of not significantly reversing"
            },
            {
                "id": "o3",
                "kind": "replace",
                "text": "only after the 30-day return period lapses, deferring all revenue until then"
            },
            {
                "id": "o4",
                "kind": "replace",
                "text": "net of actual returns recorded in the subsequent period"
            }
        ],
        "correct_option": "o2",
        "answer_key": "o2",
        "weight": 2,
        "exhibit_refs": ["ex1", "ex3"]
    },
    {
        "id": "s4",
        "confusion_set_id": "transaction_price_allocation",
        "original_text": "entirely to the software license",
        "options": [
            {
                "id": "o1",
                "kind": "keep",
                "text": "entirely to the software license"
            },
            {
                "id": "o2",
                "kind": "replace",
                "text": "to each performance obligation based on relative standalone selling prices"
            },
            {
                "id": "o3",
                "kind": "replace",
                "text": "equally between the license and the support"
            },
            {
                "id": "o4",
                "kind": "replace",
                "text": "to the support obligation first, with the residual to the license"
            }
        ],
        "correct_option": "o2",
        "answer_key": "o2",
        "weight": 1,
        "exhibit_refs": ["ex1"]
    },
    {
        "id": "s5",
        "confusion_set_id": "figure_ties_to_schedule",
        "original_text": "$4,200,000",
        "options": [
            { "id": "o1", "kind": "keep", "text": "$4,200,000" },
            { "id": "o2", "kind": "replace", "text": "$3,900,000" },
            { "id": "o3", "kind": "replace", "text": "$4,500,000" },
            { "id": "o4", "kind": "replace", "text": "$3,600,000" }
        ],
        "correct_option": "o2",
        "answer_key": "o2",
        "weight": 2,
        "exhibit_refs": ["ex2"]
    }
]
```

### Grading + Attempt Log

Score for the item (weights: s1,s2,s4 = 1; s3,s5 = 2; total = 7):

```
item_score = ( w_s1·[s1✓] + w_s2·[s2✓] + w_s3·[s3✓] + w_s4·[s4✓] + w_s5·[s5✓] ) / 7
```

`results_json` on the **Attempt Log** note (one row per blank — this is the per-blank record
that feeds confusion-set mastery):

```json
{
    "item_id": "far-revrec-note7",
    "results": [
        {
            "step_id": "s1",
            "confusion_set_id": "revrec_timing_saas",
            "chosen": "o1",
            "correct_option": "o2",
            "correct": false,
            "weight": 1,
            "awarded": 0
        },
        {
            "step_id": "s2",
            "confusion_set_id": "revrec_bundled_nondistinct",
            "chosen": "o1",
            "correct_option": "o1",
            "correct": true,
            "weight": 1,
            "awarded": 1
        },
        {
            "step_id": "s3",
            "confusion_set_id": "variable_consideration_returns",
            "chosen": "o2",
            "correct_option": "o2",
            "correct": true,
            "weight": 2,
            "awarded": 2
        },
        {
            "step_id": "s4",
            "confusion_set_id": "transaction_price_allocation",
            "chosen": "o2",
            "correct_option": "o2",
            "correct": true,
            "weight": 1,
            "awarded": 1
        },
        {
            "step_id": "s5",
            "confusion_set_id": "figure_ties_to_schedule",
            "chosen": "o1",
            "correct_option": "o2",
            "correct": false,
            "weight": 2,
            "awarded": 0
        }
    ],
    "weight_total": 7,
    "weight_awarded": 4,
    "item_score": 0.5714
}
```

### Encoding note: reusing this for the AUD KCN item

The same schema encodes Example A unchanged: `document.kind = "request_list"`, the body is the
bulleted request list with 8 `<blank>` markers (`s1…s8`), each step's `options[]` are the
verbatim Retain/Delete/Replace lists from §5, and `confusion_set_id`s such as
`ar_analysis_basis` (s1), `depreciation_support` (s2), `related_party_officer_loan` (s7),
`account_selection_for_analysis` (s8). Note **s8 has no `delete` option** — the schema handles
variable-length option lists and the absence of "Delete" fine.

### Small recommendations

- Store `options[].kind` (`keep` / `delete` / `replace`) so the UI can always render "Retain
  the original text" / "Delete the text" consistently and so analytics can ask _"how often do
  learners wrongly Delete?"_.
- Persist `original_text` on each step even when you also inline it in `<blank>` — makes
  regrading/rerendering and shuffling robust.
- Default `weight: 1`; reserve higher weights for the blanks the real exam would treat as
  harder/higher-value (numeric-tie and constraint/judgment blanks like B3/B5).
- `confusion_set_id` is the bridge to the rest of the app's confusion-set model: the same id
  should be reusable across many DRS items so mastery accrues per-confusion, not per-item.

---

## 7. Sources (all accessed 2026-07-02)

- Going Concern — _Document Review Simulation: Last Minute Tips_ (Gleim), structure/tabs, "5–7
  choices per blank", must-answer rule: https://www.goingconcern.com/document-review-simulation-last-minute-tips/
- Gleim — _CPA Task-Based Simulations_ (DRS section): https://www.gleim.com/cpa-review/cpa-task-based-simulations/
- Becker — _Becker introduces Document Review Simulation_ (launch July 2016, AUD/FAR/REG, "realistic document + related source documents"): https://www.becker.com/news/becker-professional-education-introduces-document-review-simulation-in-cpa-exam-review
- SuperfastCPA — _Explanation of the new DRS_ (AICPA quote; **FAR sample-test net-revenues 8.5% / $32,498 memo**, financial-statements+notes source tab): https://www.superfastcpa.com/explanation-of-the-new-document-review-simulation-drs-on-the-cpa-exam/
- FreeFellow — _CPA FAR Task-Based Simulations 2026_ (DRS on FAR for disclosure-prep; "grader scores each option independently"; per-cell/per-option grading; 7 FAR TBS ≈ 25–50 graded sub-items): https://freefellow.org/blog/cpa-far-task-based-simulations-2026/
- Andrew Katz Tutoring — _CPA Exam Simulation Strategy 2026_ (TBS = 50% except ISC 40%; partial credit; requirement-driven exhibit review; ~18 min/TBS; the 3 AUD DRS question archetypes): https://andrewkatztutoring.com/cpa-exam-simulation-strategy/
- AICPA & CIMA — _CPA Exam scoring and pass rates_ (scaled 0–99; weighted MCQ/TBS combination; 50/50 core & discipline, ISC 60/40): https://www.aicpa-cima.com/resources/article/learn-more-about-cpa-exam-scoring-and-pass-rates
- Universal CPA — _How is the CPA Exam Graded?_ (partial credit on TBS; drop-down/numeric answers): https://www.universalcpareview.com/how-is-the-cpa-exam-graded/
- another71 forum — _How Are SIMs Actually Graded???_ (each box graded separately; weighting is not publicly known; research-cite is the all-or-nothing exception): https://forum.another71.com/forum/welcome-cpa-exam-forum/the-forum/topic/how-are-sims-actually-graded/
- CPA Exams Mastery — _REG Exam Format_ (DRS on REG for tax documents with errors/irrelevant info): https://cpaexamsmastery.com/reg/about-reg/format-and-scoring/
- Chegg (verbatim transcriptions of the **KCN audit-request-list DRS**, all 8 callout option lists) — item variants:
  https://www.chegg.com/homework-help/questions-and-answers/1-select-answer-list-retain-original-text-delete-text-replace-accounts-receivable-aged-dat-q96578445 ,
  https://www.chegg.com/homework-help/questions-and-answers/possible-answers-include-retain-original-text-option-retain-original-text-also-option-pict-q97163661
- Whittington & Pany, _Principles of Auditing & Other Assurance Services_ (McGraw-Hill) — origin of the KCN illustrative case: https://highered.mheducation.com/sites/0073010847/information_center_view0/
