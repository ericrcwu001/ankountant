# Research TBS & Licensing — FAR Authoritative-Literature Simulation

> Scope: How the real CPA **FAR** research task-based simulation (TBS) works, the
> FASB ASC citation format, grader-normalization rules, and a **legally-safe**
> plan for Ankountant's bundled, offline, sync-safe scoped corpus (T2).
>
> Status: research memo (informational). Sources are listed inline and in
> [Appendix — Sources](#appendix--sources). Nothing here is legal advice; the
> licensing section is a good-faith reading of published FAF/FASB terms and
> should be confirmed by counsel before shipping.

---

## TL;DR

- The real FAR research TBS asks the candidate to **find the one governing
  paragraph** in the FASB Accounting Standards Codification (ASC) and **submit a
  citation** like `ASC 842-20-25-1`. The answer _is a citation string_ — a
  fact — not copyrighted prose.
- ASC text is **copyrighted by the Financial Accounting Foundation (FAF)**. Since
  **Feb 2023 access is free** (the paid "Professional View" was retired), but the
  license is still **"Personal and Non-Commercial Use"** and explicitly forbids
  copying, storing, redistributing, making derivative works, digital display,
  **commercial use**, and **AI ingestion**.
- **GASB/GARS is _also_ FAF-copyrighted** — not a safe proxy. **SEC regs and IRS
  publications are U.S.-government works (public domain)**. **OpenStax is
  CC BY-NC-SA** (usable with attribution, but NonCommercial + ShareAlike +
  no-LLM-training caveats).
- **Recommendation for T2:** grade on the **citation string** (never redistribute
  ASC prose). Ship an ASC **skeleton** (topic/subtopic/section numbers + short
  titles = uncopyrightable facts) + our **own plain-language section summaries**
  (original expression) + **deep links** to the free `asc.fasb.org` so learners
  read the real text at the source. Use **public-domain primary sources**
  (SEC/IRS) where we want faithful "read-the-actual-text" sims. This is
  offline-friendly, sync-safe, and copyright-clean.

---

# PART A — Research-TBS mechanics

## A1. What the real exam's "Authoritative Literature" browser is

- Since **2011**, research is tested as its **own standalone TBS** (one research
  cell per applicable section). On the exam screen it lives on an **information
  tab labeled "Authoritative Literature"** (a book/pencil-tabbed panel), separate
  from the work tabs. (UWorld; ipassthecpaexam)
- For **FAR** (and AUD, BAR) the literature is the **FASB Accounting Standards
  Codification**. For **REG/TCP** it is the **Internal Revenue Code**. (Andrew
  Katz Tutoring)
- The candidate can **(a) keyword-search** the Codification, **(b) drill down the
  hierarchy** (Area → Topic → Subtopic → Section → Paragraph), or **(c) jump to a
  known citation**. A **"Search Within"** function narrows to a paragraph inside a
  topic. Sections are the only pages that actually hold guidance text; Area/Topic/
  Subtopic pages are link-only "landing pages." (FASB Codification Learning Guide;
  Baruch search-tips; ipassthecpaexam)
- Candidates get a **free 6-month practice subscription** to the exam's licensed
  professional literature via **NASBA/AICPA Online Professional Library**, tied to
  an unexpired **Notice To Schedule (NTS)** — this is the "licensed exam copy"
  candidates practice on. (Another71; USI libguide)

## A2. The FAR citation format (authoritative)

Per the **FASB ASC _Notice to Constituents_** (§ "Referencing the Codification …
in other documents", © FAF), the canonical reference pattern from **outside** the
Codification is:

| Granularity  | Canonical form (FASB)                    | Bare-number form |
| ------------ | ---------------------------------------- | ---------------- |
| Topic        | `FASB ASC Topic 310` [, _Receivables_]   | `310`            |
| Subtopic     | `FASB ASC Subtopic 310-10` [, _Overall_] | `310-10`         |
| Section      | `FASB ASC Section 310-10-15` [, _Scope_] | `310-10-15`      |
| Paragraph    | `FASB ASC paragraph 310-10-15-2`         | `310-10-15-2`    |
| Subparagraph | `FASB ASC subparagraph 310-10-15-2(a)`   | `310-10-15-2(a)` |

Structure = **`XXX-YY-ZZ-PP`** → **Topic-Subtopic-Section-Paragraph** (paragraph
may carry a `(a)`/`(1)` **subparagraph** suffix). (FASB Notice to Constituents;
Baruch; UF Business Library; RIT)

**Number semantics (useful for search hints and validation):**

- **Topic** = 3 digits; first digit is the **Area**:

  | Series | Area               | Series | Area               |
  | ------ | ------------------ | ------ | ------------------ |
  | 100    | General Principles | 600    | Revenue            |
  | 200    | Presentation       | 700    | Expenses           |
  | 300    | Assets             | 800    | Broad Transactions |
  | 400    | Liabilities        | 900    | Industry           |
  | 500    | Equity             |        |                    |

- **Subtopic** = 2 digits; **`10` is always "Overall."**
- **Section** = 2 digits, **standardized across all topics** (candidates memorize
  these — they double as strong search signals):

  | ## | Section                  | ## | Section                                 |
  | -- | ------------------------ | -- | --------------------------------------- |
  | 00 | Status                   | 40 | Derecognition                           |
  | 05 | Overview & Background    | 45 | Other Presentation Matters              |
  | 10 | Objectives               | 50 | Disclosure                              |
  | 15 | Scope & Scope Exceptions | 55 | Implementation Guidance & Illustrations |
  | 20 | Glossary                 | 60 | Relationships                           |
  | 25 | Recognition              | 65 | Transition & Open Effective Date        |
  | 30 | Initial Measurement      | 70 | Grandfathered Guidance                  |
  | 35 | Subsequent Measurement   | 75 | XBRL Elements                           |

  So the _section digit_ encodes the **kind of question**: a "when do you record"
  prompt → **25 Recognition**; "how much at inception" → **30 Initial
  Measurement**; "what do you disclose" → **50 Disclosure**; "is it in scope" →
  **15 Scope**. (Wikipedia ASC; FASB Learning Guide; CPA Exams Mastery)

> **SEC overlay:** ASC sections ending in **`S99`** (e.g., `210-10-S99`) hold SEC
> guidance mirrored into the ASC. The underlying SEC material (Reg S-X, SABs) is
> government-authored — relevant to the licensing analysis in Part B.

## A3. How candidates search and submit

1. **Define the issue first**, then search — a keyword like `"variable
   consideration constraint"` or `"lease classification criteria"` beats a broad
   `"revenue"`/`"lease"`. Use quotes for phrases. (CPA Exams Mastery; Andrew Katz)
2. **Land on the governing Section**, skim the whole section (watch boldface
   headings), then pick the **exact paragraph** that resolves the fact pattern.
3. **Submit the citation** into the research cell in the required format,
   e.g. `ASC 805-30-25-1`. (FreeFellow)

**Grading nuances (important for our grader design):**

- Research citations are scored **correct if the citation matches the model
  citation at the section level** (Topic-Subtopic-Section), with the paragraph
  expected when the prompt demands paragraph-level specificity. (FreeFellow)
- The research cell is **all-or-nothing — "no partial credit"** and the response
  **must be formatted correctly and completely** per AICPA. (Another71, quoting
  AICPA) → implication: our grader should accept a **set of equivalent correct
  citations** and be **strict on format but lenient on cosmetic variation**
  (see [A5](#a5-recommended-citation-normalization-rules-for-our-grader)).
- The AICPA typically pre-populates the answer as **structured boxes** (Topic /
  Subtopic / Section / Paragraph), which sidesteps most free-text formatting
  ambiguity. Our UI should mirror this: **segmented inputs** (or a single field
  we parse into segments) rather than one raw string.
- **Time is a secondary signal only** — correctness first. This matches
  Ankountant's stated grading intent.

## A4. Representative research prompts + expected citations

These are **representative** FAR-style prompts with the **kind of citation** the
real exam expects. Citation strings are **facts** (safe to ship); the ASC prose
behind them is not (see Part B). Concrete paragraph numbers below are drawn from
FASB's own reference examples and the _Skills for Accounting Research_ textbook
(Collins/Salzman), then framed as exam-style prompts.

| #  | Prompt (issue)                                                                                              | Expected citation                  | Section digit → why           |
| -- | ----------------------------------------------------------------------------------------------------------- | ---------------------------------- | ----------------------------- |
| 1  | "What criteria must be met for a **lessee to classify a lease as a finance lease**?"                        | `ASC 842-20-25-2`                  | 25 Recognition/classification |
| 2  | "At what amount is the **initial lease liability** measured?"                                               | `ASC 842-20-30-1`                  | 30 Initial Measurement        |
| 3  | "When is a **loss contingency accrued** (the 'probable + reasonably estimable' rule)?"                      | `ASC 450-20-25-2`                  | 25 Recognition                |
| 4  | "May **inventory be carried above cost at selling price** (e.g., a mined commodity with an active market)?" | `ASC 330-10-35-16` _(subpar. (b))_ | 35 Subsequent Measurement     |
| 5  | "What **impairment recoverability test** applies to a long-lived asset held and used?"                      | `ASC 360-10-35-17`                 | 35 Subsequent Measurement     |
| 6  | "What are the **inventory disclosure** requirements?"                                                       | `ASC 330-10-50-1`                  | 50 Disclosure                 |
| 7  | "What is the **core principle / 5-step model** for revenue from contracts with customers?"                  | `ASC 606-10-05-3` … `606-10-25`    | 05 Overview / 25 Recognition  |
| 8  | "When is an **asset retirement obligation (ARO)** recognized?"                                              | `ASC 410-20-25-1`                  | 25 Recognition                |
| 9  | "How is **goodwill acquired in a business combination** initially measured?"                                | `ASC 805-30-30-1`                  | 30 Initial Measurement        |
| 10 | "What are the criteria to **offset (net) assets and liabilities** on the balance sheet?"                    | `ASC 210-20-45-1`                  | 45 Other Presentation         |

> Sourcing note: prompts 4 & 5 mirror worked examples in _Skills for Accounting
> Research_ (`ASC 330-10-35-16(b)`, `ASC 360-10-35-17`); 3, 8, 9, 10 use FASB/
> textbook example paragraphs. Exact "model answers" for a shipped item bank must
> be re-verified against the **current** ASC at `asc.fasb.org` at authoring time,
> because paragraph numbers shift with Accounting Standards Updates (ASUs).

## A5. Recommended citation-normalization rules for our grader

Grade the **candidate's citation** against a **set of acceptable citations** per
item. Normalize **both sides** to a canonical tuple before comparing:

**Canonical internal form:** ordered integer segments
`(topic, subtopic, section, paragraph?, subparagraph?)`, e.g.
`842-20-25-2` → `(842, 20, 25, 2)`.

Normalization pipeline (apply in order):

1. **Uppercase + trim**; collapse internal whitespace to nothing between segments.
2. **Strip the prefix**: remove a leading `FASB ASC`, `ASC`, `FASB`, or the words
   `Topic|Subtopic|Section|Paragraph|Subparagraph` (case-insensitive). Accept with
   or without the "FASB ASC" prefix.
3. **Unify separators**: treat `-`, `–` (en-dash), `.`, and spaces between numeric
   segments as the segment delimiter. Canonical output uses hyphens.
4. **Strip leading zeros _only_ on the Topic/Subtopic/Section triplet**
   (`00`→`0`, `05`→`5`) _for comparison_ — but **preserve two-digit section codes
   in display** (a bare `5` must equal `05`; `310-10-15` == `310-10-015`). Do **not**
   zero-pad/limit paragraph digits (paragraphs can be 2–3 digits).
5. **Subparagraph handling**: normalize `-2(a)`, `-2 a`, `-2.a` → `2(a)`. When the
   model answer is paragraph-level, **accept the paragraph with _or_ without a
   subparagraph** (configurable per item); when the model answer _is_
   subparagraph-specific, require it.
6. **Granularity policy (per-item flag)**:
   - `section` items → correct if `(topic, subtopic, section)` matches (ignore any
     paragraph the candidate adds). Mirrors the exam's section-level scoring.
   - `paragraph` items → require the paragraph too.
7. **Equivalent-answer set**: some issues are legitimately answered by more than
   one paragraph (e.g., a rule stated in `-25-1` and elaborated in `-25-2`).
   Store an explicit **allow-list** of acceptable citations per item; a match
   against any is correct.
8. **Reject cross-form ambiguity**: do **not** silently "fix" a wrong Area digit
   or a missing subtopic — those are substantive errors, not cosmetics.

Cosmetic variants that MUST be treated as equal:
`FASB ASC 606-10-25-1` = `ASC 606-10-25-1` = `606-10-25-1` =
`606 10 25 1` = `606–10–25–1` = `ASC 606-10-25-01`.

Variants that MUST differ: different Topic/Subtopic/Section; and, for
`paragraph`-flagged items, a missing or wrong paragraph.

> Prefer a **segmented input UI** (four/five boxes) to remove most free-text
> noise up front, then still run the normalizer server-side for safety and for
> imported/typed answers.

---

# PART B — Licensing

## B1. Who owns the ASC, and what the license actually says

- **The FAF owns the copyright** to the FASB ASC (and to GASB material). "…the
  Financial Accounting Foundation (the 'FAF'), the owner of the Codification."
  (asc.fasb.org Terms; BDO FASB Terms) FAF is a private non-profit and treats
  publishing/licensing of the Codification and GASB materials as **revenue**.
  (Crunchafi)
- **Free ≠ free to reuse.** On **Feb 27, 2023** FAF launched **enhanced free
  online access** to the full Codification and retired the paid **"Professional
  View"** subscription (and issued pro-rated refunds). The old two-tier
  **Basic View (free, citation/drill-down only) vs Professional View (paid,
  keyword/advanced search)** split is now **historical** — everyone gets the
  enhanced free view with search, printing, and copy/paste. (AAA; Deloitte DART;
  NYSSCPA)
- **But the license is still restrictive.** The current click-through at
  `asc.fasb.org` is **"For Personal and Non-Commercial Use"** and grants only a
  _"non-exclusive, non-transferable and nonassignable license — without the right
  to sublicense, copy, or redistribute (in whole or part) — to access a limited
  use and feature version of the Codification."_ It further provides that the
  **Codification may only reside on FAF's hosted environment** and the user may
  not transfer it off that environment. The user has **no right to**:
  - _"electronically copy or reproduce the Codification or any portion thereof in
    any … electronic storage device … or … repurpose all or any portion … or any
    derivat[iv]e work thereof in any physical, electronic or machine readable
    form for any purpose"_;
  - _"create any derivative work of any part of the Codification"_;
  - _"display or distribute the content or any portion … on a website, blog, or
    other digital format"_;
  - _"sell, resell, license, sublicense, loan, assign, furnish, or redistribute
    any portion"_; _"use the Codification for commercial purposes"_; and
  - **AI ingestion is banned**: _"Artificial Intelligence may not … use any
    portion of the Codification … as input into or for the training or
    development of generative artificial intelligence, machine learning,
    algorithms …"_ and **screen-scraping/robotic extraction is "strictly
    prohibited."** (asc.fasb.org Terms, current text)
- **Two independent legal layers** constrain us:
  1. **Copyright** — FAF owns the _expression_ (the paragraph prose and the
     original selection/arrangement). Copying substantial ASC prose is
     infringement absent fair use.
  2. **Contract** — anyone who clicks "Access" is bound by the above terms, which
     forbid copying/redistribution/derivatives/AI use **regardless** of fair use.
     So even "fair use"-sized excerpts, if taken _from asc.fasb.org_, breach the
     access contract.
- **What is _not_ protected (safe to use):** **citation numbers and short
  standardized titles are facts/short phrases**, not copyrightable —
  `ASC 842-20-25-1`, the topic name "Leases", the section label "Recognition",
  the Area/Section number tables in Part A. We can freely build and ship the
  entire **navigable ASC skeleton** (all numbers + titles); we just cannot ship
  the **paragraph body text**.
- **The "government edicts" escape does _not_ apply to the ASC.** Statutes/regs/
  opinions are uncopyrightable (_Georgia v. Public.Resource.Org_, 2020), and the
  SEC _recognizes_ ASC as authoritative GAAP — but the ASC was **not enacted into
  federal law**, so it remains FAF's copyrighted private work. (Reasoned reading;
  confirm with counsel.)

## B2. The "licensed exam copy" (Prometric / AICPA / NASBA)

- The CPA exam does **not** hand candidates the public `asc.fasb.org` site. AICPA
  **sub-licenses** the Codification from FAF for use inside the exam and inside
  the **AICPA Online Professional Library** practice product. AICPA's own license
  text says a library "Plus FASB Accounting Standards Codification" includes the
  **full FASB ASC**, that all rights "**enure to the … FAF**," and that a
  subscriber may **view and save for personal reading only — not copy, modify,
  distribute, or create derivative works.** (AICPA `LicenseText.htm`)
- Candidates get this as a **free 6-month NTS-gated subscription** — i.e., a
  **licensed, view-only** copy, not a redistributable dataset. (Another71; USI)
- **Takeaway for us:** there is an established licensing path (sub-license from
  FAF) — but it is a **paid/contractual B2B arrangement with view-only terms**,
  not something a third-party app can self-serve, and it would not permit bundling
  offline copies for redistribution. Pursue only if we ever want _verbatim_ ASC in
  the app, and expect view-only, non-redistributable, likely-commercial terms.

## B3. Public-domain / open proxies — what's actually safe

| Source                                                      | Status                                                                                                                                                         | Bundle & redistribute offline? | Notes for us                                                                                                                                                                                            |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **FASB ASC**                                                | © FAF, license = personal/non-commercial, no copy/derivative/AI                                                                                                | **No**                         | Cite-only; deep-link to `asc.fasb.org`.                                                                                                                                                                 |
| **GASB / GARS**                                             | **© FAF** — _"may not be reproduced, stored … or transmitted … without prior written permission of the FAF"_ (GASBS 96, etc.). Personal/intra-org copies only. | **No**                         | **Not a safe proxy** despite "free." Same owner, same restrictions.                                                                                                                                     |
| **SEC regs** (Reg S-X 17 CFR 210, Reg S-K 17 CFR 229, SABs) | **U.S. government work → public domain** (17 U.S.C. § 105; edicts doctrine). Authoritative via eCFR.                                                           | **Yes**                        | Strongest faithful primary source; also underlies ASC `S99` sections.                                                                                                                                   |
| **IRS** (IRC, Treasury Regs, Pubs, forms)                   | **U.S. government work → public domain**                                                                                                                       | **Yes**                        | For REG/TCP research sims; not FAR-GAAP.                                                                                                                                                                |
| **OpenStax** (e.g., _Principles of Financial Accounting_)   | **CC BY-NC-SA** + "no LLM training without permission"                                                                                                         | **With conditions**            | Attribution required; **NonCommercial** + **ShareAlike** — risky if the app is commercial or if we don't want copyleft on derived text. Good for _concepts_, not authoritative-literature substitution. |
| **Our own summaries**                                       | © us (original expression of uncopyrightable _rules/ideas_)                                                                                                    | **Yes**                        | The core of the bundled corpus.                                                                                                                                                                         |
| **ASC skeleton** (numbers + short titles)                   | Facts / short phrases, not copyrightable                                                                                                                       | **Yes**                        | Enables full offline navigation + citation grading.                                                                                                                                                     |

## B4. Evaluation of the four T2 options

- **(i) Ship short scoped ASC excerpts** — _Reject as default._ Even short
  verbatim excerpts are (a) contractually barred if sourced from asc.fasb.org and
  (b) a copyright risk at scale; fair-use is fact-specific and not a foundation to
  build a shipped product on. Copyright/contract risk is high; offline/sync are
  fine but legally unsafe.
- **(ii) Paraphrase / summarize sections** — _Yes, but carefully._ **Rules and
  ideas aren't copyrightable — only expression is.** Genuinely original,
  independently-written summaries are fine and are the backbone of the corpus.
  **Do not** produce them by feeding ASC text into an LLM (violates the AI-use
  clause and risks derivative-work claims); write from **public secondary sources
  - our own knowledge**, and keep them structurally independent (don't track ASC's
    wording/ordering paragraph-for-paragraph).
- **(iii) Cite-only + our own plain-language summaries** — **Recommended core.**
  The research answer _is the citation_, so we can grade with 100% fidelity while
  shipping **zero** copyrighted prose. Pair each citable node with our summary and
  a **deep link** to the real paragraph on the free `asc.fasb.org` for learners
  who want the exact text (linking is not redistribution).
- **(iv) Public-domain proxies** — **Recommended supplement.** Use **SEC (eCFR)**
  and **IRS** public-domain primary text where we want a _faithful "read the
  actual authoritative text and cite it"_ experience with real bundled prose.
  Skip **GASB/GARS** (FAF-copyrighted) and treat **OpenStax** as optional,
  attributed _concept_ material subject to NC/SA.

## B5. Recommendation (concrete) + rationale

**Build the FAR research TBS as a "citation-graded, cite-only" simulation over an
ASC _skeleton_, backed by our own summaries and deep links, and reserve
verbatim-text sims for public-domain SEC/IRS sources.** Specifically:

1. **Corpus =** (a) full **ASC skeleton** we author ourselves — every Topic/
   Subtopic/Section number + official short title (facts) so the browser/search/
   drill-down feels test-accurate; (b) **our original plain-language summary** per
   section/paragraph node; (c) **deep links** to `asc.fasb.org/{topic}/{subtopic}`
   for the real text. **No ASC prose is bundled.**
2. **Grader =** deterministic match of the submitted **citation string** against a
   per-item **allow-list**, using the [A5](#a5-recommended-citation-normalization-rules-for-our-grader)
   normalizer and a per-item `section`/`paragraph` granularity flag. Correctness
   is primary; **time is the secondary signal.**
3. **Faithful "read-the-text" mode (optional)** = a parallel set of research items
   over **SEC Reg S-X/S-K and IRS** public-domain text, which we _can_ bundle
   verbatim. Great for TCP/REG and for SEC-overlay FAR topics.
4. **Do not** bundle ASC or GASB text; **do not** LLM-ingest ASC text to generate
   summaries; **do** keep summaries independently authored and attributed where
   they lean on open sources (OpenStax → CC BY-NC-SA notice).
5. **If we ever need verbatim ASC in-app**, pursue a **FAF/AICPA sub-license**
   (§ B2) — budget for paid, view-only, non-redistributable, per-user terms.

**Why this wins:**

- **Legally clean.** Ships only facts (numbers/titles), our own expression, and
  government public-domain text; links (not copies) to copyrighted prose.
  Sidesteps both the copyright and the click-through-contract layers, plus the
  AI-ingestion ban.
- **Test-accurate.** The exam's research answer _is a citation_; grading the
  citation string reproduces the real skill and the real scoring
  (section-level match, all-or-nothing, format-normalized).
- **Offline + sync-safe.** The bundled corpus is 100% our own IP + PD text, so it
  can live in the app binary/DB and be versioned like code — **no per-user
  copyrighted payload ever touches sync**, and grading needs no network.
- **Faithful where it's free.** SEC/IRS give a genuine "open the source, read it,
  cite it" experience without licensing exposure.

---

## Appendix — Sources

**Exam mechanics & format**

- UWorld — Research Task Format: https://accounting.uworld.com/cpa-review/lc/cpa-videos/video/research-task-format/
- ipassthecpaexam — CPA Exam Authoritative Literature: https://ipassthecpaexam.com/cpa-exam-authoritative-literature/
- CPA Exams Mastery — GAAP Hierarchy & Codification Research: https://cpaexamsmastery.com/far/conceptual-framework-and-standard-setting/gaap-hierarchy-and-codification-research/
- Andrew Katz Tutoring — CPA Exam Simulation Strategy (2026): https://andrewkatztutoring.com/cpa-exam-simulation-strategy/
- FreeFellow — CPA FAR Task-Based Simulations 2026 (citation form; section-level grading): https://freefellow.org/blog/cpa-far-task-based-simulations-2026/
- Another71 forum — Partial Credit for Research Question (AICPA: no partial credit): https://forum.another71.com/forum/welcome-cpa-exam-forum/ot-off-topic/topic/partial-credit-for-research-question/
- FASB Codification Learning Guide (navigation/hierarchy): https://leeds-faculty.colorado.edu/buchman/ACCT3230/FASB%20Codification%20learning%20guide.pdf
- Baruch College — Codification Search Tips: https://guides.newman.baruch.cuny.edu/c.php?g=1098220&p=8009027

**Citation format & structure**

- FASB ASC _Notice to Constituents_ (referencing format; © FAF, mirror): https://www.sfu.ca/~poitras/ASC_FASB.pdf (original: https://asc.fasb.org/imageRoot/63/6537863.pdf)
- Wikipedia — Accounting Standards Codification (Area/Section tables): https://en.wikipedia.org/wiki/Accounting_Standards_Codification
- UF Business Library — How to cite the Codification: https://answers.businesslibrary.uflib.ufl.edu/faq/24694
- Baruch College — Citing the Codification: https://guides.newman.baruch.cuny.edu/c.php?g=1101194&p=8030317
- RIT — FASB Citation Style: https://infoguides.rit.edu/c.php?g=339841&p=2463592
- Queens College CUNY — ASC example (330-10-50-2): https://qc-cuny.libguides.com/c.php?g=970237&p=9902928
- _Skills for Accounting Research_ (Collins/Salzman) — worked examples incl. `ASC 330-10-35-16(b)`, `ASC 360-10-35-17` (via mirror): https://www.sweetstudy.com/files/skillsforaccountingresearch4th-pdf-7706893

**Licensing — FASB/FAF**

- FASB ASC — Terms of Use / access gateway (current "Personal and Non-Commercial Use" + full license text): https://asc.fasb.org/ (terms: https://asc.fasb.org/terms)
- FAF free-access announcement (retires Professional View), American Accounting Association: https://aaahq.org/Research/FASB-GARS
- Deloitte DART — FAF Grants Free Online Access to FASB Codification and GARS: https://dart.deloitte.com/USDART/home/news/all-news/2023/feb/faf-access
- NYSSCPA — FAF to Enhance Online Access (Basic vs Professional View history): https://www.nysscpa.org/news/publications/the-trusted-professional/article/faf-to-enhance-online-access-to-fasb-and-gasb-standards-013123
- BDO — FASB Terms & Conditions (FAF copyright ownership): https://www.bdo.com/fasb-terms
- AICPA — exam/library License Text (sub-license of full FASB ASC; view-only): https://pub.aicpa.org/exams/LicenseText.htm
- Crunchafi — What is the FAF? (publishing/licensing revenue): https://www.crunchafi.com/blog/financial-accounting-foundation
- FASB XBRL Taxonomy Terms (contrast: taxonomy is royalty-free, ASC is not): https://xbrl.fasb.org/terms/TaxonomiesTermsConditions.html

**Licensing — candidate access (Prometric/NASBA/AICPA)**

- Another71 — Free 6-month Professional Literature subscription (NTS-gated): https://www.another71.com/have-you-activated-your-subscription-to-the-professional-literature/
- USI Library — CPA Exam Resources (free 6-month literature + sample tests): https://usi.libguides.com/accounting/CPA

**Public-domain / open proxies**

- GASB — GASBS 96 (© FAF, no reproduction w/o permission): https://storage.gasb.org/GASBS%2096.pdf
- OpenStax — license (CC BY-NC-SA; no-LLM-training clause): https://openstax.org/books/business-law-i-essentials/pages/14-2-the-framework-of-securities-regulation
- SEC regulations via eCFR — Title 17 (Reg S-X §210, Reg S-K §229): https://www.ecfr.gov/current/title-17
- U.S. Copyright Act § 105 (U.S. government works not copyrightable): https://www.copyright.gov/title17/92chap1.html#105
- IRS — Forms & Publications (U.S. government works): https://www.irs.gov/forms-instructions
