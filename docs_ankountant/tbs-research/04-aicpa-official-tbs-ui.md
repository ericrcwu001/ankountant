# 04 — The Real AICPA / Prometric Task-Based Simulation (TBS) UI

**Purpose:** an authoritative, concrete description of the _actual_ current (CPA
Evolution, blueprint effective **January 2024**) Uniform CPA Examination TBS
interface, so Ankountant can copy it at test-accurate fidelity — with a focus on
the two surfaces we are building: **research** and **document review**.

**Scope note / currency:** The CPA Exam delivery software ("the CPA Exam Driver")
is built by the AICPA and delivered in Prometric test centers. The UI has been
stable since the 2018 interface refresh and carried forward through CPA Evolution
(2024). The single most authoritative artifact is the **AICPA official Sample
Test**, which runs the _actual exam driver_ in a browser (see §0). Everything
below is corroborated against AICPA's own docs (Sample Test, SpreadJS FAQ,
Candidate Guide) plus the major review providers (UWorld/Roger, Gleim, Becker)
who reverse-describe the interface for candidates.

> **How to get ground truth (do this):** Launch the official Sample Test
> (§0) in Chrome/Edge on desktop and screen-record each widget. It is the exact
> driver, is free, and is the reference implementation we are cloning.

---

## 0. Where the real UI lives (the official Sample Test)

- **Sample Tests landing page (AICPA & CIMA):**
  https://www.aicpa-cima.com/resources/article/get-familiar-with-the-cpa-exam-by-practicing-with-our-sample-tests
- **Direct launcher (the actual exam driver, SPA):**
  `https://exams.aicpa.org/driver.web.v13/#/sample/AUD/`
  (the landing page's "CPA Exam Sample Test" button; a fresh session must be
  started from the landing page — the driver rejects deep links / expired
  sessions, and is only supported on **Windows or macOS desktop using Google
  Chrome or Microsoft Edge**).
- **Accessible (screen-reader) sample tests:**
  https://www.aicpa-cima.com/resources/article/practice-with-accessible-cpa-exam-sample-tests
- **Features & Functionality / software tutorial video:**
  https://www.aicpa-cima.com/resources/video/learn-more-about-the-cpa-exam-software
- **Official spreadsheet info download ("The Uniform CPA Examination — the Exam"):**
  https://www.aicpa-cima.com/resources/download/the-uniform-cpa-examination-the-exam

Facts about the Sample Test itself (from the AICPA landing page):

- Includes items from **all six sections** (AUD, FAR, REG, ISC, BAR, TCP).
- **Up to 2 hours**, **not scored**, and you can **reveal the correct answers**.
- Runs the same software as the test center but may differ on display settings /
  security lockdowns (e.g., some keyboard shortcuts). Content "current as of
  July 1, 2023."
- In-app **HELP** icon in the toolbar documents every tool. Candidates are
  _required_ to attest they reviewed the tutorial + sample test before testing
  (NASBA Candidate Guide).

---

## 1. Split-screen layout & how exhibits are presented

**Overall frame.** A TBS renders as a two-pane split screen sized for the
Prometric HD monitor:

- **Left pane = the "work" area**: the task's requirements/instructions and the
  response widget (grid, document, or research box).
- **Right pane = "resources"/exhibits**: everything you need to answer —
  exhibits, and the tool windows (Authoritative Literature, spreadsheet,
  calculator). On the current large-monitor layout you generally do **not** have
  to toggle a separate "resources tab" to see work + resources at once.

Sources: UWorld/Efficient Learning, _Experience the CPA Exam Interface_
(https://www.efficientlearning.com/blog/new-cpa-exam-interface-now-available-in-our-practice-exams/):
"The working screen will always appear on the left and the right side of the
screen will be used to display any extra information you need." Vishal CPA Prep
(https://vishalcpaprep.com/blogs/news/excelling-in-task-based-simulations-5-strategies-for-success):
"a split screen, with the simulation question and exhibit links on the left and
exhibits, calculator, authoritative literature, and a spreadsheet on the right."

**Tabs.** Inside each TBS testlet there is a tab strip. Tab types (UWorld "Research
Task Format" video):

- **Work tabs** — marked with a **pencil icon** (where you enter answers).
- **Information tabs** — reference material, including the exhibits and the
  **"Authoritative Literature"** tab.
- **Help tab** — tool documentation.
  Each exhibit is reachable as its own tab, and you can move freely between the
  requirements and the exhibits (Andrew Katz Tutoring,
  https://andrewkatztutoring.com/cpa-exam-simulation-strategy/).

**Exhibit windows (the "detach"/multi-window behavior).**

- You can **open up to 8 exhibits simultaneously** as separate windows.
- Windows can be arranged with two built-in layouts — **Tile** and **Cascade** —
  and can also be **moved and resized** freely (drag the window; drag the bottom
  edge to enlarge). (Efficient Learning; Gleim,
  https://www.gleim.com/cpa-review/cpa-task-based-simulations/.)
- Per-exhibit controls observed in the UWorld TBS Mastery webinar
  (https://www.youtube.com/watch?v=suJstixB4zE): an **"explore"/search** icon
  (find a word/number _within_ that document), a **+/- sizer** and a
  **percentage sizer** (zoom), a **full-size toggle** (enlarge to full / restore),
  and side arrows exposing **rotate / text-select / scroll** options; large
  exhibits **scroll**.
- **Highlight tool:** select text inside an exhibit and choose "highlight" → the
  text gets a **bright yellow** highlight. **Multiple highlights** are allowed and
  they **persist** after you close the exhibit or switch tabs (Gleim).

> Test-accurate takeaways for Ankountant: model exhibits as **floating,
> movable/resizable windows** (not just tabs) with **tile/cascade** presets, a
> **cap of ~8** open at once, per-window **zoom + in-document find + scroll**, and
> **persistent yellow highlighting** that survives navigation.

---

## 2. Response widget types

The Uniform CPA Examination Blueprints define **four general TBS response
formats** (Gleim; AICPA Blueprints): **Free-response Numeric Entry**, **Option
List**, **Journal Entry**, and **Document Review**. "Research" is a distinct task
that uses the Authoritative Literature tool (§4). "Form completion" is realized as
grids of numeric/option-list cells (e.g., preparing a financial statement,
schedule, or tax form). A single TBS can combine formats.

Completion indicator convention: each answer cell shows a small status icon that
**changes/fades once answered** — e.g., a blue **"123"** chip for numeric cells, a
blue **three-line** chip for option-list/DRS cells that becomes a **checkmark**
when a selection is made (Gleim; Going Concern). Use this as the "answered vs.
unanswered" affordance.

### 2a. Numeric entry (cell-fill) — _most common on FAR_

- Click a shaded/answer cell → an entry box appears; you type a number.
- The value is **auto-formatted** after entry (currency, decimals, negatives per
  instructions) — always re-check for typos because auto-format can mask errors.
- No option hints (free response). Watch instructions for **rounding / negative
  number** conventions.
- Grading: per-cell against a model answer with a **tolerance band** (typically
  exact-dollar/whole-dollar rounding). Each cell scored **independently** — never
  leave cells blank (FreeFellow, https://freefellow.org/blog/cpa-far-task-based-simulations-2026/;
  Gleim).

### 2b. Option list (dropdown cells)

- Click a cell → a **dropdown list of choices** appears; pick the _best_ one.
- Different cells can have **different lists**; instructions may restrict **how
  many times** a choice may be reused (once vs. unlimited).
- Used for account selection, classifications, "select the statement," etc.

### 2c. Journal entry grid (combines option list + numeric)

- A grid with an **Account column (option-list dropdown)** and **Debit / Credit
  numeric columns**.
- Standard instructions (from the AICPA sample, per UWorld webinar): "Double-click
  the shaded cell" to open the account list; **start with debits**, then credits,
  place accounts in the order given by the source data, and **leave unused rows
  blank**.
- Order of rows does **not** matter for grading; each row is scored on **account
  - amount + correct debit/credit direction** all matching (Gleim; FreeFellow).

### 2d. Document Review Simulation (DRS) — _one of our target surfaces_

The DRS presents a **primary document** (memo, financial-statement note, audit
report, tax return, contract clause) plus **source-material exhibits** (and the
Authoritative Literature tab). Embedded in the document are **modifiable
segments** — words, phrases, sentences, or whole paragraphs — rendered as
**blue, underlined text** followed by a small blue **status icon** (three
horizontal lines).

Interaction (Gleim; Going Concern, https://www.goingconcern.com/document-review-simulation-last-minute-tips/;
SuperfastCPA, https://www.superfastcpa.com/explanation-of-the-new-document-review-simulation-drs-on-the-cpa-exam/):

1. **Click** an underlined segment → a popup/dropdown opens with a list of
   options — commonly **5–7 choices**.
2. The option list always includes **"[Original text] / keep as written"** and
   often a **"Delete"** option, plus **3–5 replacement/edit** variants.
3. You **must select exactly one option for every underlined segment** — _even to
   keep the original_. An unanswered segment is graded **incorrect**, regardless
   of whether the original was fine.
4. On selection, the segment's icon changes from **three lines → a white
   checkmark** (your visual proof it's answered).
5. Each segment is graded **independently** against the AICPA-designated option.

> Test-accurate takeaways: DRS = an inline rich-text document where certain
> spans are **interactive "keep / delete / replace-with-option-N" pickers**; the
> correct edit is determined by cross-referencing the **source exhibits**; every
> span is mandatory; per-span status icon (lines → check).

### 2e. Research response — _our other target surface_ (see §4 for full detail)

Entered via the **Authoritative Literature** tool: you locate the governing
paragraph and **"Transfer to Answer"**, which populates a citation answer box
(Topic / Subtopic / Section / Paragraph). Partial credit applies.

---

## 3. The Spreadsheet (SpreadJS) and the Calculator

### 3a. Spreadsheet — **SpreadJS** (GrapeCity/MESCIUS JavaScript spreadsheet)

Primary source: **AICPA official "Spreadsheet FAQs" PDF**
(https://assets.ctfassets.net/rb9cdnjh59cm/6TpbsHENfAPsJDcyMiWxXD/9d62b98e76a7bc8875a5a7940302ee49/92317096_2306-393888_cpa_exam_spreadjs_-_faq_updates_final.pdf);
corroborated by the UWorld TBS Mastery webinar (which explicitly names it
"SpreadJS") and Gleim.

- **Look & feel:** Microsoft-Excel-like. Has the functionality needed for the
  exam; **not** full Excel (some features disabled for security).
- **Availability:** open **throughout the entire exam** — both **MCQ testlets and
  TBS testlets**. Toggle via a **"Spreadsheet" icon**; **"Save & Close"** hides it.
- **Window:** can be **resized and moved anywhere** on screen.
- **Formulas:** the Excel formulas you know are available; there **is** a formula
  wizard, but with **less instructional text** than Excel's. Also supports
  **sort** and **filter** (Gleim).
- **Copy / paste (critical, hotkey-only):** available **only via keyboard**:
  - **Cut = Ctrl-X, Copy = Ctrl-C, Paste = Ctrl-V**
  - **Undo = Ctrl-Z, Redo = Ctrl-Y**
  - There are **NO copy/paste/undo/redo buttons** in the ribbon or menus.
  - You can copy **from an MCQ or TBS into the spreadsheet**, and **from the
    spreadsheet into a TBS response field**. Select with mouse-drag, then hotkey;
    click a cell first so the sheet has focus; verify the paste landed.
  - **Ctrl-F (Find) and Ctrl-A (Select All) are DISABLED** in the real exam
    (they _may_ work in the Sample Test — a known sample-vs-exam discrepancy).
- **Persistence:** **autosaves periodically**; work is retained even while the
  spreadsheet is closed and while navigating **within the same testlet**. It
  **clears automatically when you submit a testlet** — it is **blank at the start
  of each new testlet** (do not expect to carry a scratch model across testlets).
- **Note from instructors:** it is "not exactly like Excel"; some auto-behaviors
  and shortcuts differ — practice on the Sample Test to avoid surprises.

### 3b. Calculator

- A **basic on-screen 4-/"8-function" calculator** (add, subtract, multiply,
  divide; memory keys) — intended for quick single calculations. Use the
  spreadsheet for multi-step math. (Gleim; UWorld webinar.)
- Like the spreadsheet, it's reachable from the TBS toolbar and can be
  repositioned. Copy/paste into the calculator is supported per Efficient
  Learning ("you can now paste into Excel, the calculator, or the response area").

---

## 4. Authoritative Literature / research browser + FAR (FASB ASC) citation format

This is the **research surface**. On the CPA Exam it is a built-in, searchable
copy of the authoritative literature, opened from the **"Authoritative
Literature"** information tab (or the toolbar) within a TBS testlet.

**Which literature by section:**

- **FAR, AUD, BAR → FASB Accounting Standards Codification (ASC)** (AUD also has
  the audit/attestation standards; PCAOB AS vs. AICPA AU-C depending on
  issuer/non-issuer).
- **REG, TCP → Internal Revenue Code (IRC)**.
  (Andrew Katz; UWorld "How to Tackle Research Questions"
  https://accounting.uworld.com/cpa-review/lc/cpa-videos/video/how-tackle-research-questions/.)

**Browser structure & navigation (UWorld Research Task Format video; Andrew Katz):**

- A **table of contents / browse-by-topic tree** ("a predetermined list of
  codes") on one side, and a **keyword Search box** ("treat it like a Google
  search").
- After a search you can use **"Search Within"** to find specific keyword
  instances inside a subsection; **matches are highlighted** in the text so you
  can step through them.
- Recommended flow: search a few precise terms → open the candidate
  topic/subtopic → "Search Within" for the operative words → read to confirm the
  governing paragraph.

**How the answer is entered — "Transfer to Answer":**

- When you have the correct paragraph on screen, you **highlight/select it and
  click the "Transfer to Answer" button**, which **auto-populates the research
  answer box** with the citation. Do **not** hand-retype if Transfer to Answer is
  available (UWorld videos). This is the canonical entry mechanic to replicate.
- The answer box captures the citation **by component**: **Topic – Subtopic –
  Section – Paragraph.**

**FAR citation format (FASB ASC) — concrete:**

- Pattern: **`ASC Topic-Subtopic-Section-Paragraph`** → e.g. **`ASC 330-10-30-9`**
  (inventory), `ASC 805-30-25-1` (business combinations), `ASC 350-20-35-30`
  (goodwill). Levels: **Topic** (broad area) → **Subtopic** (transaction/asset
  class) → **Section** (scope / recognition / measurement / disclosure) →
  **Paragraph** (the specific rule). (EY FRD; CPA Exams Mastery,
  https://cpaexamsmastery.com/far/conceptual-framework-and-standard-setting/gaap-hierarchy-and-codification-research/.)
- Handy high-frequency topic numbers to seed the tree: 606 revenue, 842 leases,
  805 business combinations, 350 intangibles/goodwill, 330 inventory.

**Grading (partial credit — important):** Research is **not all-or-nothing**.
Graders look for the **four components (Topic, Subtopic, Section, Paragraph)**;
the **Topic + Subtopic + Section are the most important** and the **Paragraph is
"icing on the cake"** — you can **max the points by getting the section-level
citation right even if the paragraph is off** (Roger Philipp / UWorld). FreeFellow
frames the pass condition as "correct if the citation matches the model citation
**at the section level**." Every applicable section has **≥1 research TBS** (AUD,
FAR, BAR, REG, TCP), and some candidates report two.

**Free practice DB:** NASBA offers a **free 6-month "Professional Literature"
subscription** to anyone with a valid Notice to Schedule, so candidates can
practice searching the real ASC/IRC before exam day (UWorld video).

> Test-accurate takeaways for our research surface: build a **TOC tree + keyword
> search + "Search Within" (with in-text match highlighting)**, and a
> **"Transfer to Answer"** action that fills a **4-field citation box
> (Topic/Subtopic/Section/Paragraph)**; grade with **partial credit weighted to
> section-level**.

---

## 5. Keyboard/mouse, copy-paste, flag-for-review, timing

**Mouse/keyboard & copy-paste:**

- Predominantly **mouse-driven** (click cells, open dropdowns, drag windows,
  highlight text). Text entry is keyboard.
- **Copy/paste is hotkey-only** (Ctrl-C/X/V) and works **exhibit/MCQ/TBS ↔
  spreadsheet ↔ response field**; you can paste into the spreadsheet, the
  calculator, or a response area (Efficient Learning; AICPA SpreadJS FAQ).
  Instructors caution that pasting is finicky and some cut/paste doesn't behave
  like Excel — copy tables separately from surrounding text and verify.
- **In-exhibit highlighting** (yellow, persistent) is the main annotation tool;
  there is also a per-document **"explore"/find** search.

**Flag / mark for review:**

- Every item (MCQ and TBS/cell) can be **flagged/marked and returned to** within
  the testlet; a **navigation/overview panel** lists items and lets you jump
  around. Recommended practice: flag any TBS eating >20 min and move on, then
  return (FreeFellow; Andrew Katz). Note: you **cannot go back to a previous
  testlet** once submitted.

**Timer / structure / breaks (NASBA Candidate Guide + Gleim/FreeFellow):**

- Each section is **4 hours**; a **countdown timer** shows at the top of the
  screen throughout.
- **FAR structure = 5 testlets:** T1 25 MCQ, T2 25 MCQ, T3 **2 TBS**, T4 **3 TBS**,
  T5 **2 TBS** → **50 MCQ + 7 TBS**. (AUD 7 TBS, BAR 7, TCP 7, REG **8**, ISC 6 —
  all TBS live in testlets 3/4/5.)
- MCQs ≈ **50%** of score, TBS ≈ **50%** (ISC: TBS = 40%). Each TBS has multiple
  independently graded sub-cells (~3–7 each).
- **One standardized 15-minute break** is offered after the **first TBS testlet**
  (roughly midway); it **does not** count against testing time. Optional breaks
  are allowed **between testlets** but the **clock keeps running**.
- Pacing rules of thumb: ~**1.25–1.33 min/MCQ**, ~**18 min/TBS**.
- Test center provides **scratch noteboards/pencils** (no personal paper); strict
  security (no personal calculator, etc.).

---

## 6. Sample-test walkthrough (the official practice UI)

Walkthrough of the official experience, assembled from the AICPA landing page +
UWorld/Roger video walkthroughs (see links in §0/§4):

1. From the **Sample Tests landing page**, click **"CPA Exam Sample Test"** →
   launches the driver SPA (`exams.aicpa.org/driver.web.v13`). Chrome/Edge on
   desktop only.
2. **Introductory screens** (in the real exam these run under a strict 5-minute
   limit), then you land in a **testlet**. A **toolbar** exposes global tools:
   **HELP**, **Calculator**, **Spreadsheet**, and (in TBS testlets) the
   **Authoritative Literature** and **Exhibits**, plus the **countdown timer**
   and testlet navigation.
3. **MCQ testlets:** one question at a time with A–D radio options, next/previous,
   and flag-for-review; the spreadsheet/calculator are available here too.
4. **TBS testlets:** the split-screen (§1). Read the **requirements** (left),
   open **exhibits** (right; tile/cascade/resize; highlight), and complete the
   response widget (numeric grid / option-list / journal-entry / DRS / research).
5. **Research item:** open **Authoritative Literature**, search → Search Within →
   **Transfer to Answer** to fill the citation box.
6. The Sample Test lets you **reveal correct answers** and is **not scored**; the
   **HELP** icon documents each tool — record it as the spec.

Direct link to include in-product ("practice on the real thing"):
https://www.aicpa-cima.com/resources/article/get-familiar-with-the-cpa-exam-by-practicing-with-our-sample-tests

---

## 7. Screenshots found (described)

Live driver frames couldn't be scraped (session-gated SPA; Chrome/Edge only), and
the AICPA screenshots inside the driver require a session. The clearest public
stills are on the Efficient Learning/UWorld interface post
(https://www.efficientlearning.com/blog/new-cpa-exam-interface-now-available-in-our-practice-exams/):

- **`AICPA-Prometric-9`** — the **split-screen** TBS: work pane left, resource/exhibit
  pane right on a wide HD layout ("two documents at once").
- **`excel-620`** — the **embedded spreadsheet** window floating over the TBS,
  Excel-like grid + formula bar, movable/resizable.
- **`AICPA-Prometric-2` / `AICPA-Prometric-7`** — **multiple exhibit windows**
  shown **tiled** and **cascaded** respectively.
- **`AICPA-Prometric-11`** — **cut/copy/paste** between exhibit, spreadsheet,
  calculator, and response area.

Additional annotated stills worth capturing ourselves (fair-use, for design
reference): Gleim's TBS page shows the numeric/option-list/journal-entry/DRS cell
chips and the DRS "three-lines → checkmark" icon
(https://www.gleim.com/cpa-review/cpa-task-based-simulations/); SuperfastCPA's DRS
post shows a primary document with a highlighted sentence expanding into an option
list plus a "Financial Statements" source tab
(https://www.superfastcpa.com/explanation-of-the-new-document-review-simulation-drs-on-the-cpa-exam/).
**Best action:** screen-record the official Sample Test (§0) for pixel-accurate
reference rather than relying on third-party stills.

---

## 8. Decision-relevant implications for Ankountant (research + document-review)

- **Adopt the split-screen shell now**: left = requirements + response widget;
  right = **floating, movable/resizable exhibit windows** with **tile/cascade**
  presets, **~8-window cap**, per-window **zoom / in-doc find / scroll**, and
  **persistent yellow highlight** across navigation. Plus a **global toolbar**
  (Help, Calculator, Spreadsheet, Auth. Literature) and a **countdown timer**.
- **Research surface spec:** TOC/browse tree **+** keyword search **+** "Search
  Within" with **in-text match highlighting**; a **"Transfer to Answer"** action
  that fills a **4-component citation box (Topic-Subtopic-Section-Paragraph)** in
  **FASB ASC** form (`ASC 330-10-30-9`); **partial-credit grading weighted to the
  section level** (paragraph = bonus).
- **Document-review surface spec:** rich-text primary document with **interactive
  underlined spans** (blue + status icon); clicking a span opens a **5–7 option
  picker** that always contains **"keep original"** and usually **"delete"**;
  **every span mandatory**; **per-span independent grading**; **lines → checkmark**
  answered-state icon; answers derived from **source exhibits** (and Auth. Lit.).
- **Spreadsheet:** if we embed one, **SpreadJS** is the literal exam engine — same
  vendor gives us free fidelity. Enforce the exam quirks: **hotkey-only
  copy/paste/undo**, **no ribbon copy buttons**, **Ctrl-F/Ctrl-A disabled**,
  **auto-clear on testlet submit**, autosave-on-close.
- **Calculator:** a simple on-screen 4-function calculator is sufficient and
  test-accurate; don't over-build it.
- **Completion affordances matter:** replicate the **per-cell status chips**
  ("123" / three-lines → check) and the **flag-for-review + item navigator**;
  these are load-bearing for candidate UX and "did I answer everything?".

---

## Sources

| #  | Source                                                        | URL                                                                                                                                                              | Used for                                                                    |
| -- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 1  | AICPA & CIMA — Practice with Sample Tests (landing)           | https://www.aicpa-cima.com/resources/article/get-familiar-with-the-cpa-exam-by-practicing-with-our-sample-tests                                                  | Official sample test, launcher link, rules                                  |
| 2  | AICPA exam driver (sample launcher)                           | https://exams.aicpa.org/driver.web.v13/#/sample/AUD/                                                                                                             | The actual UI/driver                                                        |
| 3  | AICPA — accessible sample tests                               | https://www.aicpa-cima.com/resources/article/practice-with-accessible-cpa-exam-sample-tests                                                                      | Accessibility variants                                                      |
| 4  | AICPA — Spreadsheet (SpreadJS) FAQ (PDF)                      | https://assets.ctfassets.net/rb9cdnjh59cm/6TpbsHENfAPsJDcyMiWxXD/9d62b98e76a7bc8875a5a7940302ee49/92317096_2306-393888_cpa_exam_spreadjs_-_faq_updates_final.pdf | Spreadsheet behavior/hotkeys/persistence (authoritative)                    |
| 5  | AICPA — software tutorial video                               | https://www.aicpa-cima.com/resources/video/learn-more-about-the-cpa-exam-software                                                                                | Official tool walkthrough                                                   |
| 6  | NASBA — CPA Exam Candidate Guide (2024)                       | https://nasba.org/wp-content/uploads/2024/07/CPA-Exam-Candidate-Guide_07012024.pdf                                                                               | Testlets, timing, breaks, scratch paper, tabs                               |
| 7  | UWorld/Efficient Learning — Experience the CPA Exam Interface | https://www.efficientlearning.com/blog/new-cpa-exam-interface-now-available-in-our-practice-exams/                                                               | Split-screen, 8 exhibits, tile/cascade, copy/paste, screenshots             |
| 8  | UWorld — CPA Task-Based Simulations (2026)                    | https://accounting.uworld.com/cpa-review/cpa-courses/features/tbs/                                                                                               | TBS formats, tabs, authoritative literature tool                            |
| 9  | UWorld — Research Task Format (video)                         | https://accounting.uworld.com/cpa-review/lc/cpa-videos/video/research-task-format/                                                                               | Auth. Lit. tab, work/info/help tabs, Search Within                          |
| 10 | UWorld/Roger — How to Tackle Research Questions               | https://accounting.uworld.com/cpa-review/lc/cpa-videos/video/how-tackle-research-questions/                                                                      | Transfer-to-Answer, partial credit, ASC 330-10-30-9                         |
| 11 | UWorld — TBS Mastery Webinar Pt.1 (video)                     | https://www.youtube.com/watch?v=suJstixB4zE                                                                                                                      | SpreadJS name, exhibit tools, 4 TBS types, DRS/journal walkthrough          |
| 12 | Gleim — CPA Task-Based Simulations                            | https://www.gleim.com/cpa-review/cpa-task-based-simulations/                                                                                                     | Calculator, spreadsheet, exhibits/highlight, 4 widget types, testlet counts |
| 13 | FreeFellow — CPA FAR TBS 2026                                 | https://freefellow.org/blog/cpa-far-task-based-simulations-2026/                                                                                                 | FAR 5-testlet structure, item types, grading tolerances                     |
| 14 | Andrew Katz Tutoring — TBS Strategy 2026                      | https://andrewkatztutoring.com/cpa-exam-simulation-strategy/                                                                                                     | Auth. Lit. search+browse, exhibit tabs, flag/timing                         |
| 15 | Going Concern — DRS last-minute tips                          | https://www.goingconcern.com/document-review-simulation-last-minute-tips/                                                                                        | DRS blue underline + icon, 5–7 options, checkmark state                     |
| 16 | SuperfastCPA — Explanation of the DRS                         | https://www.superfastcpa.com/explanation-of-the-new-document-review-simulation-drs-on-the-cpa-exam/                                                              | DRS primary doc + source tabs, click-to-expand options                      |
| 17 | Vishal CPA Prep — Excelling in TBS                            | https://vishalcpaprep.com/blogs/news/excelling-in-task-based-simulations-5-strategies-for-success                                                                | Split-screen left/right description                                         |
| 18 | CPA Exams Mastery — GAAP hierarchy & codification research    | https://cpaexamsmastery.com/far/conceptual-framework-and-standard-setting/gaap-hierarchy-and-codification-research/                                              | ASC Topic/Subtopic/Section/Paragraph structure                              |

_Compiled via web research (Jina Reader + web search); the live AICPA driver is
session-gated (Chrome/Edge desktop only) so ground-truth capture should be done
by screen-recording the official Sample Test._
