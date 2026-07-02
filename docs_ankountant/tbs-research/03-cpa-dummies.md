# CPA Exam For Dummies (2nd ed., 2024) — TBS / exam-software knowledge extraction

**Source:** Kenneth W. Boyd, _CPA Exam For Dummies_, 2nd Edition, Wiley/For Dummies, 2024
(ISBN-13 9781394245994). 307-page PDF.
**Extracted:** via `pymupdf` → `/tmp/dummies.txt` (page markers `===== PDF_PAGE N =====`).
**Page-number convention below:** `book p.X` is the number printed in the book; `PDF p.Y` is
the physical PDF page. In this file **book page = PDF page − 16** (e.g., book p.18 = PDF p.34).

> **Fidelity warning before you read.** This is a _For Dummies_ survey book, written at a
> "sixth-grade reading level" (its words, book p.49). It is a **strong, quotable primary
> source for the exam's high-level UX vocabulary and TBS taxonomy**, but it is **not**
> screen-accurate. It **never uses the terms "document review," "exhibit(s)," "DRS," or
> "Accounting Standards Codification / ASC,"** and it gives **no citation-format detail**.
> For pixel/interaction fidelity of the research browser and the document-review surface we
> still need the AICPA sample tests / tutorial (see "Gaps" at the end). Treat this file as the
> UX-vocabulary and mental-model layer, not the spec.

---

## TL;DR — most decision-relevant findings

1. **The exam UX vocabulary is confirmed and quotable:** a **toolbar** (test/testlet name,
   time remaining, **calculator**, **spreadsheet** tool, exit), **tabs at the top-left** of a
   simulation that hold "extra information/resources," **question navigator at the bottom**
   (numbers, current question boxed in **red**), and **testlet directions at the far-left
   bottom**. This maps cleanly onto our split-screen TBS shell. (book p.18–19 / PDF p.34–35)
2. **Research TBS = "type a search term → software searches the authoritative-literature
   database → shows results," then you cite it.** The book frames research as (a) picking a
   _research question_ and (b) selecting a _key search term_ to "pull important information
   from a database" and "identify the correct authoritative literature." Our research surface's
   core loop (keyword search → pick a passage → submit citation) is exactly this. (book p.20–21,
   p.50–51 / PDF p.36–37, p.66–67)
3. **The spreadsheet is deliberately dumb.** It does "simple calculations (add, multiply, and
   so on), just like an Excel document," but **has no built-in accounting formulas** — "you
   won't find those formulas in the spreadsheet tool." Don't over-build our spreadsheet with
   formula helpers; that would be _less_ test-accurate. (book p.18 / PDF p.34)
4. **FAR = 50 MCQ + 7 TBS, 4 hours, 50/50 score weighting** (MCQ 50% / TBS 50%; only ISC differs
   at 60/40). TBS are half the grade — our two surfaces are load-bearing. (Table 2-1, book p.19;
   scoring, book p.23 / PDF p.35, p.39)
5. **TBS answer-input types the book names:** drop-down menu, journal-entry grid (type accounts +
   dollar amounts), free-text/essay (with spell-check), plus the research search box and the
   spreadsheet. These are the concrete widget types we should support. (book p.18 / PDF p.34)
6. **"Document review" is absent from this book.** The closest analog it describes is the AUD
   _workpaper_ simulation ("you're presented with a workpaper… asks whether the work performed
   was appropriate"). There is **no** dropdown-in-a-document / highlight-the-relevant-exhibit
   description here — that fidelity must come from another source. (book p.50 / PDF p.66)
7. **Timing pressure is a real UX feature:** 4-hour clock always visible; **the clock keeps
   running during breaks**; breaks are allowed only _between testlets_; candidates are told to
   "get into the habit of checking the time remaining as you work through a question." Persistent
   countdown + testlet-boundary breaks are worth reproducing. (book p.31, p.51 / PDF p.47, p.67)
8. **Noteboards, not paper.** Scratch work happens on laminated noteboards with a fine-point
   marker (no paper/pencil). If we add a scratchpad, this is the real-world analog to imitate.
   (book p.31, p.235–236 / PDF p.47, p.251–252)
9. **FAR authoritative literature = FASB (+ GASB for governmental, SEC, IFRS/IASB context).**
   The FAR chapter's regulator list tells us which standard-setters' literature a FAR research
   TBS would search. (book p.104 / PDF p.120)
10. **MCQs come before TBS and can prime them.** The book repeatedly says to reuse a related MCQ
    when solving a TBS. Not directly a UI requirement, but informs how we might sequence content.
    (book p.51 / PDF p.67)

---

## 1. CPA exam software / UI

### 1.1 The toolbar (time, calculator, spreadsheet, exit)

> "**Toolbar:** The toolbar displays the test and the testlet you're currently taking. A testlet
> is a section of a test… The toolbar also displays the amount of time remaining to complete the
> exam and provides a **calculator** and **exit button**. For more complex portions of the exam,
> the toolbar gives you access to a **spreadsheet tool**." — book p.18 (PDF p.34)

**Spreadsheet tool — capabilities and (deliberate) limits:**

> "The spreadsheet allows you to perform some simple calculations (add, multiply, and so on),
> just like an Excel document. For more complex formulas, you'll need to use your calculator.
> Because the CPA exam requires you to know many formulas, **you won't find those formulas in the
> spreadsheet tool.**" — book p.18 (PDF p.34)

Design implication: the spreadsheet is a bare arithmetic grid (Excel-like cell math), **not** a
formula-assisted accounting tool. Candidates bring the formulas. Later reinforced: FAR "involves
the most mathematical calculations… you may use the spreadsheet function. Using a spreadsheet
allows you to quickly calculate answers and lets you review your work." (book p.51 / PDF p.67)

### 1.2 Tabs = the exhibit/resource pane (top-left)

> "**Tabs:** Some exam questions, called simulations, provide extra information that you use to
> solve the question. You can access this info using **tabs at the top left portion of the
> screen**." — book p.18 (PDF p.34)

This is the book's name for what the real software/our build calls the **exhibits pane**. The
book does not call them "exhibits," but functionally these top-left tabs _are_ the exhibits/
resource surface for a TBS.

### 1.3 Navigation & flagging

> "**Navigation between questions:** The question numbers for your current testlet are listed at
> the bottom of the screen, and the question you're currently working on is inside a **red box**.
> At a glance, you can see which question you're on and how many questions remain… You have the
> ability to skip a question as well as the ability to go back to any question to review or change
> an answer." — book p.18 (PDF p.34)

> "**Testlet directions:** …The directions are displayed at the far left at the bottom of the
> screen, to the left of the numbered questions." — book p.18 (PDF p.34)

Note: the book does **not** describe a dedicated "flag for review" control by name; it only
describes free skip/return navigation via the numbered list. (The word "flag" appears in the book
only as "red flag," an idiom — book p.50, p.204.) So _flagging_ is a gap in this source.

### 1.4 Answer-input widgets for TBS

> "**Task-based simulation questions:** …After working on the question, you input your answer on
> the computer screen. In some cases, you choose an answer from a **drop-down menu**. For a
> **journal entry**, you may type in the accounts and dollar amounts to post the entry. Finally,
> you may be asked to **type in paragraphs of text** to answer in an essay format. The test
> provides **spell-check** and some other features you may use with other word processing
> programs, such as Microsoft Word." — book p.18 (PDF p.34)

So the named widget set is: **drop-down**, **journal-entry grid** (accounts + dollar amounts),
**free-text/essay** (spell-check), plus the **search box** (research) and the **spreadsheet**.

### 1.5 MCQ input & tutorial

- MCQ: "click on the **radio button** next to the single best answer… click on the radio button
  for your new answer choice" to change. (book p.18 / PDF p.34)
- "You're supplied with **headphones** for the audio portion of the exam." (book p.31 / PDF p.47)
- Official UX reference the book points candidates to: "watch the **tutorial** on the AICPA
  website (www.aicpa-cima.com/)." Candidates must "**attest** to the fact that you've reviewed
  the **tutorials and sample tests**" before each test. (book p.18, p.29 / PDF p.34, p.45)
  → This tutorial + AICPA sample tests are the higher-fidelity source we should mine next.

---

## 2. TBS taxonomy & mechanics

### 2.1 What a TBS _is_

> "**Application of a body of knowledge:** Task-based simulations test your ability to apply
> knowledge to an accounting situation. The exam provides you with resources, such as a page of
> authoritative literature or a spreadsheet, and you have to figure out what to do with them." —
> book p.19 (PDF p.35)

> "Simulations require you to apply a body of knowledge to an accounting issue. You're given a
> variety of tools, which may include a **calculator, a spreadsheet, or some authoritative
> literature**, and you have to figure out how to use those resources to complete a task." —
> book p.20 (PDF p.36)

TBS are described as **case studies** (book p.19 / PDF p.35).

### 2.2 The six exam skills (blueprint skill levels)

The book lists the skills TBS test (these mirror the AICPA blueprint's skill dimension). Two are
directly the surfaces we're building:

- **Research:** "All CPAs must perform research… You may be asked to identify an appropriate
  research question to address an accounting topic. The exam may also ask you to **select a key
  search term to pull important information from a database**." (book p.20 / PDF p.36)
  Continued: "This skill requires you to assess information from several different sources and
  reach a conclusion… as well as **identify the correct authoritative literature** to address a
  topic." (book p.21 / PDF p.37)
- **Evaluation of a business process**, **Application of technology** (spreadsheets/Excel),
  **Analysis** (trends, variances, forecasting), **Complex problem-solving and judgment**, and
  **Decision-making**. (book p.20–21 / PDF p.36–37)

### 2.3 TBS types the book actually demonstrates

The dedicated TBS section ("Considering Task-Based Simulations," book p.50–51 / PDF p.66–67)
walks through **two** concrete archetypes:

- **AUD — workpaper review + research** (see §5.1 transcription). Present a workpaper; ask whether
  procedures were appropriate and whether adjustments are needed; provide authoritative literature
  to search.
- **FAR — true/false + research, and inventory calculation** (see §5.2). Series of true/false
  statements with a searchable authoritative-literature database; and a number-crunching inventory
  valuation task solved with the spreadsheet.

> "Keep in mind that **all the topics for a particular test are fair game** for a simulation
> question. That can create anxiety, because you don't know the specific topic until it pops up on
> your test screen." — book p.50 (PDF p.66)

---

## 3. Research citations — how they're located & entered

This is the book's most useful material for our **research** surface. Note it describes the
_search_ mechanic well but is **silent on the citation format** (no ASC/section syntax, no
"transfer to answer" step).

**The core loop (from the AUD example, book p.50 / PDF p.66):**

> "This type of simulation may provide **authoritative literature that you can reference**. To use
> your time efficiently, you need to have some **search terms** in mind. Based on Step 1, you use
> search terms like 'receivables' and 'confirmation.' **Type a search term into the computer
> screen where indicated. The test software will search the literature for that particular term
> and show you the results.**" — book p.50 (PDF p.66)

**Keyword-quality is the whole skill (from the FAR example, book p.51 / PDF p.67):**

> "You may be provided with a **database of authoritative literature that you can search**. The
> key, however, is to know enough about the topic to come up with some **effective keywords**…
> If you want to search the database effectively, you could use '**FIFO inventory valuation
> rules**' as a search term." — book p.51 (PDF p.67)

**Research-as-decision (book p.21 / PDF p.37):**

> "If you're researching an appropriate depreciation expense method for equipment… you need to
> **search the firm's database** for the current depreciation method — and you need to **locate
> the correct literature** to decide on the right method." — book p.21 (PDF p.37)

**Which literature (FAR):** the FAR regulator list implies the searchable corpus = **FASB**
standards (for-profit + not-for-profit), **GASB** (governmental), with **SEC** and **IFRS/IASB**
context. (book p.104 / PDF p.120)

**Search tips the book gives (usable as in-app hints/tutorial copy):**

- Derive keywords from the topic _before_ searching; jot them on the noteboard (e.g.,
  "receivables, confirmation"). (book p.50 / PDF p.66)
- Use multi-word topical phrases ("FIFO inventory valuation rules") rather than bare terms.
  (book p.51 / PDF p.67)
- Reuse terminology from a related MCQ seen earlier in the test. (book p.51 / PDF p.67)

**Gap:** no description of the citation _entry_ format (e.g., typing a Topic/Subtopic/Section, or
selecting a paragraph and clicking a "transfer"/"add to answer" button). Must come from AICPA
sample tests.

---

## 4. Document-review items — what this source has (little)

**Bottom line: this book does not cover document-review TBS.** A full-text search of the extracted
book finds **zero** occurrences of "document review," "exhibit," "highlight" (as a UI verb; only
"highlighter" for paper study), or "ASC." The only dropdown mention re: answers is the generic
"choose an answer from a drop-down menu" (book p.18 / PDF p.34).

The nearest structural analog the book describes is the **AUD workpaper simulation** — a
prepared document you must evaluate:

> "You're presented with a **workpaper**, which is an internal document created by an auditor. The
> form documents what was done to audit a particular account balance… The simulation asks whether
> the work performed was appropriate… The question also asks whether any accounting adjustments
> need to be made to the receivable balance." — book p.50 (PDF p.66)

That's "read a document + provided resources, then answer structured questions about it," which is
the _spirit_ of document review, but the book gives **no** detail on in-document dropdowns/blanks,
highlighting the relevant exhibit passage, or exhibits-as-tabs feeding a fill-in document. **This
is a hard gap for our document-review surface.**

---

## 5. Worked sample TBS (transcribed)

The book gives **narrative walkthroughs / plans of attack**, not fully specified prompts with
answer keys. Both are transcribed below.

### 5.1 AUD workpaper + research simulation (book p.50–51 / PDF p.66–67)

Setup:

> "Suppose a simulation addresses an audit of accounts receivable. You're presented with a
> workpaper… The simulation asks whether the work performed was appropriate for an audit of
> accounts receivable. The question also asks whether any accounting adjustments need to be made
> to the receivable balance."

Plan of attack (verbatim structure):

1. "**Consider the content of the question.** Think through what you know about auditing accounts
   receivable… auditors want to confirm that amounts listed as receivables are based on actual
   sales… an auditor may send confirmation letters to customers… you may jot down 'receivables,
   confirmation' on a noteboard."
2. "**Look at the other resources provided.** This type of simulation may provide authoritative
   literature that you can reference… you use search terms like 'receivables' and 'confirmation.'
   Type a search term into the computer screen where indicated. The test software will search the
   literature for that particular term and show you the results."
3. "**Mull over multiple-choice questions on the same topic.** Multiple-choice questions come
   before simulations… a question on confirming accounts receivable may help you with the
   simulation."
4. "**After you think through these steps, you're ready to answer the question.**"

### 5.2 FAR inventory simulation(s) (book p.51 / PDF p.67)

Variant A — true/false + research:

> "Say a simulation question asks you a series of **true/false questions about inventory**. You
> may be provided with a database of authoritative literature that you can search… FIFO
> (first-in, first-out) and LIFO (last-in, first-out) are two methods used to value inventory…
> you could use 'FIFO inventory valuation rules' as a search term."

Variant B — calculation via spreadsheet:

> "Another inventory simulation may ask you to **calculate the value of inventory, given a series
> of inventory purchases and sales**. For this type of question, you may use the spreadsheet
> function… you may need to multiply four or five different costs per unit by the number of units
> either bought or sold. If you input the data into a spreadsheet, the data will be easier to
> review and correct."
> "Include a **label with each number** you write on a noteboard or in a spreadsheet. You need to
> know whether a number represents a dollar amount or the number of units bought or sold."

### 5.3 Ending-inventory "solve for the blank" algebra (book p.39 / PDF p.55)

A representative FAR calc pattern (fill-in-the-blank via algebra), transcribed:

> "the formula for calculating ending inventory is: **Beginning inventory + Purchases − Cost of
> goods sold = Ending inventory**… If you were given all the amounts except cost of goods sold,
> you'd put the three known amounts in the formula and then use algebra to calculate cost of goods
> sold." — book p.39 (PDF p.55)

_(No answer-key numbers are provided for these; the book teaches the approach, not a scored item.)_

---

## 6. FAR-specific TBS topics / blueprint weighting

### 6.1 Format & weighting

| Section          | Time     | MCQs   | TBSs  | TBS score weight |
| ---------------- | -------- | ------ | ----- | ---------------- |
| AUD — Core       | 4 hr     | 78     | 7     | 50%              |
| **FAR — Core**   | **4 hr** | **50** | **7** | **50%**          |
| REG — Core       | 4 hr     | 72     | 8     | 50%              |
| BAR — Discipline | 4 hr     | 50     | 7     | 50%              |
| ISC — Discipline | 4 hr     | 82     | 6     | **40%**          |
| TCP — Discipline | 4 hr     | 68     | 7     | 50%              |

Source: Table 2-1 "Test Formats and Time Limits" (book p.19 / PDF p.35) + scoring rules:

> "All tests except the information systems and controls (ISC) test… 50 percent of your score
> comes from the multiple-choice questions, and 50 percent comes from task-based simulations."
> — book p.23 (PDF p.39)

Passing score: **75** (scaled, not raw %). "your reported score isn't simply a percentage of
answers that are correct." (book p.23 / PDF p.39)

**Blueprint** = AICPA "Uniform CPA Examination Blueprints," which "explains the tests in detail,
listing the **percentage of test questions for each particular topic**" (book p.15 / PDF p.31,
and referenced again p.17). The book does **not** reproduce FAR's numeric blueprint weights (it
only gives an AUD example: "ethics, professional responsibilities, and general principles" = 15–25%
of AUD). → **FAR blueprint percentages must be pulled from the AICPA Blueprint itself.**

### 6.2 FAR character & content areas (for choosing TBS topics)

- FAR "**involves the most mathematical calculations**" / "the most number-crunching" and needs
  the most study (150–180 hrs). (book p.38, p.51 / PDF p.54, p.67)
- FAR chapter ("Taking a Closer Look at the FAR Test," Ch. 11) organizes FAR as: **accounting
  standards & standard-setters**, **accounts in the financial statements**, and **posting
  accounting transactions** (journal entries, debits/credits, dollar amounts). (book p.103–104 /
  PDF p.119–120)
- **Standard-setters / authoritative-literature sources for FAR:** SEC, **FASB** (for-profit &
  not-for-profit), **GASB** (governmental), **IFRS Foundation / IASB** (international).
  (book p.104 / PDF p.120)
- **Source documents** (invoice, shipping doc, purchase order, packing slip) drive FAR
  transaction-posting TBS. (book p.37–38 / PDF p.53–54)

### 6.3 "Six key FAR concepts on every FAR test" (good TBS seed topics)

From "Reviewing Six Key Concepts to Improve Your Score" (book p.51–52 / PDF p.67–68):

1. **Balance-sheet formula** stays in balance: _Assets − Liabilities = Equity_; "an answer choice
   that doesn't keep the balance sheet formula in balance is incorrect."
2. **Realized vs. recognized gains** (a realized gain isn't always recognized, e.g., inside a
   401(k)).
3. **Total depreciation is method-independent** (straight-line vs. double-declining give the same
   lifetime total).
4. **Depreciation vs. amortization** (physical vs. intangible assets).
5. **Bond premium/discount amortization** (premium → extra income; discount → extra expense).
6. **Dilutive securities / diluted EPS** (options, rights, warrants, convertibles lower EPS).

These map naturally to FAR TBS item topics (journal entries, EPS calc, depreciation schedules,
bond amortization tables, inventory valuation).

---

## 7. Test-taking UX details that make the software feel real

- **Persistent 4-hour countdown** in the toolbar; candidates told to "get into the habit of
  **checking the time remaining** as you work through a question." (book p.18, p.51 / PDF p.34, p.67)
- **+30 minutes** of non-test time is scheduled for login + instructions ("If you're taking a
  4-hour test… your confirmation will list 4 hours and 30 minutes"). (book p.30 / PDF p.46)
- **Testlets** structure the test; **breaks are allowed only after you finish a testlet, and the
  clock keeps running during the break.** (book p.31 / PDF p.47)
- **Introduction/instructions are timed** — "You have a limited amount of time to read and respond
  to the introduction… If you take too long, you'll be logged out." (book p.31 / PDF p.47)
- **Noteboards** replace paper: "Paper and pencil are no longer used for note-taking. Instead,
  candidates use noteboards, which are laminated, colored sheets that you use to take notes with a
  fine-point marker." Glossary echoes this. (book p.31, p.235–236, glossary / PDF p.47, p.251–252)
- **Copy/paste & resizing:** the book **does not** describe copy/paste between exhibits/spreadsheet
  or pane resizing. ("Copy" appears only as anti-cheating rules and study-planner references.) →
  Gap; verify against the AICPA tutorial.
- **Word-processor niceties in essay tasks:** spell-check and "some other features you may use with
  other word processing programs, such as Microsoft Word." (book p.18 / PDF p.34) _(Note: free-form
  written-communication tasks were dropped under CPA Evolution 2024; the book still references
  "written communication" in appeal/score-report contexts — treat essay-widget mentions cautiously
  for FAR.)_
- **Answer-review discipline:** skip/return freely; use the numbered navigator (current = red box)
  to revisit; the book's whole MCQ method assumes going back to change answers. (book p.18, p.235
  / PDF p.34, p.251)

---

## 8. Gaps — what this source does NOT give us (build-relevant)

1. **Document-review TBS**: no coverage at all (no exhibits/blanks/in-document dropdowns/highlights).
   The AUD "workpaper" is the only structural cousin. **Get this from AICPA sample tests.**
2. **Citation format for research**: no ASC Topic-Subtopic-Section syntax, no "transfer to answer"
   interaction, no example of an entered citation. Only the _search_ half of the loop is described.
3. **Research browser layout**: table-of-contents tree, section navigation, in-result highlighting —
   none described.
4. **Flag-for-review control**: not described (only free skip/return).
5. **Pane resizing / copy-paste / split-screen proportions**: not described.
6. **FAR numeric blueprint weights**: not reproduced (book points to the AICPA Blueprint doc).
7. **Screen-accurate spreadsheet feature set** (cell references, functions available): only
   "add, multiply… like Excel," explicitly _without_ accounting formulas.

**Recommended next source(s):** the **AICPA CPA Exam tutorial and sample tests**
(aicpa-cima.com — the book itself points here, book p.18/p.29) and the **AICPA Uniform CPA
Examination Blueprints** (FAR) for the missing fidelity and weighting detail.

---

## Appendix — key quotes with page refs (quick index)

| Topic                                     | Quote anchor                                                                       | book p. | PDF p.  | line(s) in /tmp/dummies.txt |
| ----------------------------------------- | ---------------------------------------------------------------------------------- | ------- | ------- | --------------------------- |
| Toolbar: time/calc/spreadsheet/exit       | "The toolbar displays the test and the testlet…"                                   | 18      | 34      | 1113–1121                   |
| Spreadsheet has no formulas               | "you won't find those formulas in the spreadsheet tool."                           | 18      | 34      | 1119–1121                   |
| Tabs = extra info (top-left)              | "You can access this info using tabs at the top left…"                             | 18      | 34      | 1123–1124                   |
| Navigation / red box / skip-return        | "…the question you're currently working on is inside a red box."                   | 18      | 34      | 1126–1130                   |
| Testlet directions (far-left bottom)      | "…displayed at the far left at the bottom of the screen…"                          | 18      | 34      | 1132–1135                   |
| TBS answer widgets (dropdown/JE/essay)    | "you choose an answer from a drop-down menu. For a journal entry…"                 | 18      | 34      | 1141–1147                   |
| Tutorial on AICPA site                    | "watch the tutorial on the AICPA website"                                          | 18      | 34      | 1148–1149                   |
| TBS = apply body of knowledge             | "…a page of authoritative literature or a spreadsheet…"                            | 19      | 35      | 1161–1163                   |
| Table 2-1 formats (FAR 50/7, etc.)        | "FAR — Core / 4 hours / 50 / 7"                                                    | 19      | 35      | 1179–1210                   |
| Research skill / key search term          | "select a key search term to pull important information from a database."          | 20      | 36      | 1255–1257                   |
| Research = locate correct literature      | "identify the correct authoritative literature to address a topic."                | 21      | 37      | 1262–1266                   |
| Scoring 75; TBS 50% (ISC 40%)             | "50 percent comes from task-based simulations."                                    | 23      | 39      | 1395–1409                   |
| Noteboards / launch code / breaks         | "Paper and pencil are no longer used… noteboards…"                                 | 31      | 47      | 1699–1712                   |
| +30 min for login/instructions            | "your confirmation will list 4 hours and 30 minutes."                              | 30      | 46      | 1683–1686                   |
| FAR study plan (50/7; 150–180 hrs)        | "50 multiple-choice questions and 7 simulation questions."                         | 37–38   | 53–54   | 1983–1992                   |
| Ending-inventory algebra formula          | "Beginning inventory + Purchases − Cost of goods sold = Ending inventory"          | 39      | 55      | 2050–2059                   |
| TBS section intro / all topics fair game  | "all the topics for a particular test are fair game…"                              | 50      | 66      | 2515–2526                   |
| AUD workpaper sim + search mechanic       | "Type a search term… The test software will search the literature…"                | 50      | 66      | 2534–2551                   |
| FAR true/false + keywords ("FIFO…")       | "'FIFO inventory valuation rules' as a search term."                               | 51      | 67      | 2565–2572                   |
| FAR spreadsheet calc + label numbers      | "you may use the spreadsheet function…"                                            | 51      | 67      | 2573–2581                   |
| Check time remaining habit                | "get into the habit of checking the time remaining…"                               | 51      | 67      | 2582–2586                   |
| Six key FAR concepts                      | "Emphasizing the balance sheet formula…"                                           | 51–52   | 67–68   | 2589–2635                   |
| FAR chapter scope (Ch. 11)                | "Digging into accounting standards / posting accounting transactions"              | 103–104 | 119–120 | 4778–4803                   |
| FAR standard-setters (FASB/GASB/SEC/IFRS) | "Financial Accounting Standards Board (FASB)…"                                     | 104     | 120     | 4808–4848                   |
| Noteboard usage detail                    | "Because the exam is no longer in written form, you're allowed to use noteboards." | 235–236 | 251–252 | 10999–11056                 |
| Blueprint = % per topic                   | "listing the percentage of test questions for each particular topic."              | 15      | 31      | 986–989                     |
