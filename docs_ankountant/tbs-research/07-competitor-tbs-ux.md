# 07 — Competitor TBS Practice UX Survey (Becker, UWorld/Roger, Gleim, Surgent, Wiley)

**Goal:** learn how commercial CPA-review platforms render Task-Based Simulation
(TBS) practice so Ankountant's FAR TBS surfaces feel faithful to the real exam —
but better. Focus on the four exam TBS shapes we care about: **research**,
**document review**, **journal-entry**, and **numeric**.

**Scope & method.** Desk research via web search (Exa-equivalent), Jina reader
(`r.jina.ai`), and YouTube walkthrough transcripts (`yt-dlp`), per the
`agent-reach` skill. I could not run the actual paid product UIs (they sit behind
paywalls), so platform detail is triangulated from: each vendor's own marketing +
help docs, third-party hands-on reviews, the **Becker Course User Guide PDFs**
(which document the exam-emulating simulation UI feature-by-feature), the **AICPA
CPA Evolution change notices + SpreadJS FAQ** (the ground truth), and **narrated
video walkthroughs of actual AICPA released sims** (Roger Philipp / Liz Kolar /
Farhat). Every claim below has a source in the [Sources](#sources) section.
`agent-reach`/`mcporter` binaries were not installed on this machine, so I used
the built-in web-search/fetch as the Exa/web-reader equivalent plus `yt-dlp` +
`curl r.jina.ai` directly.

> **Why the ground truth matters more than any one vendor:** every serious course
> openly states its goal is to _replicate the AICPA interface_, and every review
> tells candidates the real practice tool is the **free AICPA Sample Test**. So
> "test-accurate" = "matches the AICPA sample test," and the vendors differ
> mostly in (a) how faithfully they emulate it and (b) how good their
> _post-submit explanation_ layer is. We should treat the AICPA interface as the
> spec and the vendors as the competitive bar for explanations + ergonomics.

---

## 0. TL;DR — what to copy, what to skip

- **Copy the AICPA information architecture:** a tabbed workpaper (work tab(s)
  with a **pencil icon** = gradable; plus exhibit/info tabs, a Help tab, and — for
  research — an Authoritative-Literature/excerpt tab), a persistent toolbar
  (calculator, scratch spreadsheet, split-screen, submit), and a **timer**. This
  is the shared skeleton behind Becker/UWorld/Gleim/Surgent/Wiley.
- **The single biggest fidelity gap in our JE grid today:** the exam constrains
  account names to a **pop-up "Select Item" list** (a controlled dropdown), plus a
  **"no entry required"** control and **more blank rows than needed**. Our JE
  account field is currently free-text (`TbsSurface.svelte` / `TbsTaskView.swift`).
  Free-text is _easier_ but _not test-accurate_ and it also makes grading noisier.
- **Keep polishing the two formerly stubbed shapes:** **document-review** (click
  underlined text → dropdown of edits → Accept / Reset, with a per-blank
  answered/unanswered marker) and **research** (now, post-2024, an
  **excerpt-as-exhibit + structured citation entry**, not a full searchable
  codification). Both are now implemented on desktop and iOS; remaining work is
  fidelity polish, richer rationales, and broader seeded coverage.
- **Our differentiator should be the results layer.** Everyone shows a partial-%;
  the leaders (UWorld written rationales; Becker SkillBuilder/ExamSolver videos;
  Gleim explanations + **blueprint references**) explain the _why_ per blank and
  reveal the correct answer. We currently show only ✓/✗ + a total %.
- **Skip the gimmicks:** clunky calculators, a full spreadsheet nobody uses, and
  the biggest anti-pattern — **whole-row / all-or-nothing grading** that Roger &
  Becker are widely criticized for (it under-scores candidates vs. the exam's
  per-blank grading). Our server already grades per-step; keep it.

---

## 1. Ground truth: the real AICPA TBS interface (2024 CPA Evolution)

This is the spec every vendor chases. Sourced from the Becker Course User Guides
(feature-level description of the emulated exam UI), the AICPA CPA Evolution
change notices, the AICPA SpreadJS FAQ, and narrated walkthroughs of released sims.

**Layout & navigation**

- A TBS is a **case study rendered as tabs**. Tab types: **work tab(s)** marked
  with a **pencil icon** (contains the gradable blanks), **exhibit/information
  tabs** (financials, memos, invoices, trial balances, schedules), a **Help tab**
  (explains the mechanics), a **Directions** entry, and a **Resources** tab
  (present-value tables, formulas, spreadsheet operators). [Becker guide;
  Going Concern]
- **Blanks are shaded cells**; instructions say exactly what each shaded area
  wants. A cell is answered by typing (direct entry) or by clicking to open a
  **pop-up "Select Item" list** (dropdown). [Becker guide]
- **Split screen** (horizontal **and** vertical) lets you view any two tabs at
  once, with a **draggable divider to resize panes**; you can't show the same tab
  in both panes. [Becker guide; Roger Philipp DRS video]
- **Reminder flags** per task (self-only; don't affect score). In the **TBS
  testlet you can see _all_ sims at once** (unlike MCQ testlets), so candidates
  triage. [Roger sample-test video; Liz Kolar DRS webinar]
- **Timer** top-of-screen; at ~2–3 min it switches to minutes:seconds and turns
  **red**. Submitting a testlet is irreversible (upper-right Submit). [Roger &
  Liz Kolar videos]

**Toolbar tools**

- **Calculator:** a basic on-screen calculator (candidates can click or type into
  it). It is deliberately minimal. [Becker guide; Roger DRS video]
- **Scratch spreadsheet:** since Jan-2024 this is **SpreadJS** (a JS,
  Excel-_like_ tool from GrapeCity — replaced desktop Excel 2016). It's available
  in **every** testlet (MCQ and TBS), can be **moved/resized**, hidden via
  "Save & Close," reopened via the Spreadsheet icon. **Security lockdowns:** some
  features disabled; **copy/paste only via Ctrl-X/C/V hotkeys** (no ribbon
  buttons) — you can copy an exhibit table straight into the sheet, or a computed
  value from the sheet into a TBS response field. [AICPA SpreadJS FAQ; CPA
  Evolution notice]
- **Highlight** + **cut/copy/paste** tools exist for exhibits/text. [Gleim on
  AICPA tutorials]

**The three big 2024 "CPA Evolution" changes (fidelity landmines):**

1. **Authoritative Literature is NO LONGER a fully searchable codification.** The
   exam now typically **provides the relevant excerpt(s) as an exhibit** for
   research tasks. (Historically it was a searchable FASB ASC / IRC / Prof.
   Standards DB with keyword + "Search Within" + boolean AND/OR.) Note: several
   vendors' _marketing still advertises a "built-in research tool,"_ so this is a
   place where old review-course UIs are **less** test-accurate than they claim.
   [MNCPA "CPA Evolution explained"; AICPA infrastructure-changes notice]
2. **Excel → SpreadJS** (above).
3. **Written Communication tasks removed** entirely. [MNCPA]

**Formats you will actually see (per released sims):**

| Shape                                 | What the candidate does                         | UI primitive                                                                       |
| ------------------------------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------- |
| **Journal entry** (adjusting entries) | pick account(s), choose Dr/Cr, enter amounts    | account **dropdown** + side + amount cells; **"no entry required"**; spare rows    |
| **Numeric / direct entry**            | compute → type a value                          | shaded numeric cell (whole numbers, negatives for reductions, "enter 0 if zero")   |
| **Choice list**                       | pick from a dropdown per row                    | dropdown of accounts / amounts / yes-no / favorable-unfavorable                    |
| **Document review (DRS)**             | click underlined text → keep / replace / delete | inline dropdown on each underlined segment + Accept/Reset + answered marker        |
| **Research**                          | find & cite the guidance                        | (2024) read excerpt exhibit → enter **structured citation** (e.g. ASC 842-20-25-1) |

**Grading (this is important and widely misunderstood):**

- **Per "measurement opportunity" (per blank).** Each box is graded
  independently; you can get 3-of-3, 2-of-3, etc. Weight per box/per sim is not
  published and varies by form. [another71 "How are SIMs graded"]
- **Exception — research is all-or-nothing:** you must get the citation exactly
  right for any credit. [another71]
- **No wrong-answer penalty; never leave a blank.** Partial credit rewards
  attempting every box. [Andrew Katz; UWorld/Efficient Learning]

---

## 2. Per-platform findings

### 2.1 Becker

**Fidelity & IA.** Becker's homework and **Simulated Exams** are built to "look and
act like" the exam: the same tabbed model (work tab + pencil icon, info tabs,
Authoritative Literature tab, Help), the same toolbar (Calculator, Spreadsheet,
Split Vert/Horiz with draggable resize), reminder flags, and timer. In coursework
the exam's Help button is replaced by a **Solution** button that reveals the
answer + explanation _per tab_. [Becker Course User Guide]

**JE grid / numeric / dropdown.** Matches the exam primitives: **Direct Entry**
(type numeric value into a shaded cell), **Pop-up tasks** (click cell → "Select
Item" dropdown → OK), **Form Completion** (fills a real tax form), and
**Multiple-Selection** (checkbox lists that enforce "select exactly N"). [Becker
guide]

**Research / authoritative literature.** Historically the classic **3-pane** AL
browser: search/nav on top, **TOC hierarchy on the left**, **document pane on the
right**, **resizable divider**, keyword + **Advanced Search** (exact phrase /
synonyms / alternatives). Prep subset flags dead ends as **"Wrong Path."** You
locate the paragraph, then type the citation back in the Research work tab.
[Becker guide]

**Spreadsheet / calculator.** A basic Excel-like scratch sheet ("not as robust as
Excel"); a single on-screen calculator. [Becker guide]

**Post-submit results & explanations (their strength).**

- Simulated/Final exam review is a **two-pane screen**: problem on top, explanation
  on the bottom, with **color coding: green = correct, yellow = incorrect,
  blue = unanswered** — applied to both the requirement cells and the question
  numbers. [Becker guide]
- **SkillBuilder videos** = instructor walks through a coursework TBS step-by-step;
  **ExamSolver videos** (900+) do the same for _every_ MCQ/TBS in Mini/Simulated
  Exams. Widely rated the best TBS explanation layer in the market ("on-demand
  personal tutor"). Also a **Newt AI tutor**. [Becker; cpaexamguide review]
- ⚠️ Known criticism: Becker (like Roger) is reported to grade **the whole
  requirement/row as one unit**, so candidates see lower sim scores than the real
  exam's per-blank grading would give. A fidelity _anti-pattern_ to avoid.
  [another71]

**Video description (SkillBuilder, `AlMmjGlUhrI`):** an instructor screen-shares a
FAR TBS, reads the requirement first, opens exhibits on demand, computes in the
scratchpad, fills the shaded cells, then narrates why each entry is right.

**Test-accurate:** tabbed workpaper, pencil-icon work tabs, Select-Item dropdowns,
3-pane AL, split-screen resize, color-coded review. **Simplification/anti-pattern:**
whole-row grading; coursework "Solution" button (fine for learning, not exam-like).

Sources: Becker Course User Guide PDF; becker.com blog "5 ways to prepare for
TBS"; becker.com/support-products (ExamSolver); cpaexamguide.com Becker review.

---

### 2.2 UWorld (formerly Roger CPA Review)

**Fidelity & IA.** Explicitly "designed to closely match the AICPA CPA Exam
environment, including **tab navigation between question and exhibits**, the
**authoritative literature research tool**, and input-based response formats," with
an **"Exam Sim" mode** replicating the 4-hour, 5-testlet, Prometric-style flow.
Advertises "identical tools and navigation," "real-world exhibit management," and
an "authentic split-screen layout." Covers all shapes: **DRS, journal entries,
research (FASB/PCAOB/IRC), dropdown tables, exhibit-based**. [UWorld TBS &
practice-exam pages]

**JE grid (from an actual UWorld TBS sample, `4k0a8dUeyKI`).** The narrated PP&E
sim shows the exact grid ergonomics we want to match:

- "**Click a cell, select our account name**" → account is a **controlled
  dropdown**, not free text.
- Separate **Debit** and **Credit** entry; "enter everything as **positive
  amounts**," it **rounds to whole numbers.**
- "**You may not need all of the rows**" → **spare blank rows** are provided.
- "If there's no journal entry needed, click that **'no entry required'** button."
- **Submit → immediate correct/incorrect** feedback ("we'll hit submit and see if
  we got the correct answer — and we did").

**Research.** Historically Roger's DRS/research walkthrough (`fPCHmyQLlUA`,
Roger Philipp) shows the AL tab with **keyword search + "Search Within,"** used to
disambiguate IRC §1033 vs §1041 live. (Post-2024, expect excerpt-as-exhibit.)

**Post-submit results & explanations.** Every TBS ships a **detailed written
explanation** ("not only the correct answer but _why_ and which concept it
tests"), often with **flowcharts/diagrams**, plus **TBS Mastery Videos** —
instructor thinks aloud through each sim type, **auto-surfaced in the study flow
("SmartPath")** next to the relevant question. Roger's lectures are the
energetic-instructor draw. **Mobile app** preserves exhibit tabs + input fields.
[UWorld pages]

**Video descriptions:** `4k0a8dUeyKI` (PP&E acquire-through-sale TBS, full grid
walkthrough — best single artifact for JE-grid ergonomics); `fPCHmyQLlUA` (Roger
Philipp narrates _actual AICPA released_ DRS + research sims, showing exhibits
tab, underlined-text dropdowns, Accept/Reset, AL search); `suJstixB4zE` (1-hr TBS
Mastery webinar).

**Test-accurate:** account **dropdowns**, positive-amounts + rounding, spare rows,
"no entry required," split-screen, exhibit tabs, immediate per-blank result.
**Simplification:** same whole-row-vs-per-box grading complaint as Becker/Roger
historically (candidate forums).

Sources: accounting.uworld.com TBS + practice-exams pages; YouTube
`4k0a8dUeyKI`, `fPCHmyQLlUA`, `suJstixB4zE`.

---

### 2.3 Gleim

**Fidelity & IA.** Positions its **"Exam Rehearsal"** as the most exam-emulating
mock on the market ("mirror-image simulation… replicating format and functionality
in every possible way, including topic weighting"), and says _every_ practice
quiz is emulated too. Largest sim bank (~1,300 sims). Uses the same tab set the
AICPA does — **Directions, Resources (PV tables/formulas), Authoritative
Literature, Help** — plus the standard toolbar. [Gleim blogs; Going Concern]

**Research / AL.** Gleim's docs track the AICPA AL closely (3 subject areas;
FASB-codification-header menu ordering). They lean on candidates practicing the
free AICPA sample test for the exact tool. [Gleim "AICPA Sample Test Updates"]

**Post-submit results & explanations (their differentiator).** After Exam Rehearsal
you get a **review session with answer explanations for correct _and_ incorrect
choices**, and results **feed the adaptive engine** to drive Final Review. Since
the 2019 AICPA sample added them, each Gleim sim carries **detailed answer
explanations _plus a Blueprint reference_** (which AICPA blueprint skill/area the
task maps to) shown just above the explanation. **Granular analytics** is the
brand promise. No live per-keystroke grading — you self-check against solutions.
[Gleim "2019 CPA Sample Exam"; Gleim "Practice CPA Exam"]

**Test-accurate:** full tab set incl. Resources; topic-weighted mock; blueprint
tagging (arguably _more_ rigorous than the exam surfaces). **Simplification:**
review-then-self-assess model; UI reads as dense/utilitarian (volume-first),
per third-party reviews.

Sources: gleim.com/cpa-review/blog/{practice-cpa-exam, aicpa-sample-test-updates,
2019-cpa-sample-exam}; goingconcern.com TBS explainer.

---

### 2.4 Surgent

**Fidelity & IA.** "**Exam simulator** very close to the AICPA version." Its
signature is **two modes**: **Practice mode** shows the **answer + explanation
immediately after each choice** (study), while **Exam mode** shows **nothing until
the full testlet is submitted** (test conditions). Practice exams mirror the real
5-testlet / 4-hour format. [sacbee review; wallstreetmojo review]

**Adaptivity (the brand).** **A.S.A.P.** (Adaptive Study, Accelerated Performance)

- **ReadySCORE** exam-readiness predictor. TBS enter the daily plan in a
  **"Study + Simulation" phase** once you've mastered the MCQs; the engine _suggests_
  a TBS when it detects a weak area, and you can **hover a grey slot to preview a
  sim's number/category/status** and hand-pick one. 500+ TBS incl. DRS. [wallstreetmojo;
  surgent.com]

**DRS walkthrough (Liz Kolar, `nvMzbHdP00w`) — richest single DRS artifact found.**
Narrates an actual AUD DRS end-to-end and documents the exact DRS mechanics
Surgent replicates:

- **Directions screens have a 10-minute lockout** (miss it → locked out) — a real
  exam constraint worth teaching.
- DRS work tab has the **pencil icon**; each **underlined segment** shows a
  **blue "unanswered" marker**; click it → **dropdown of edits** (keep = "original
  text," **delete** = strikes the text through, or replace with an option); pick →
  marker flips to a **check**; **Accept** collapses it; you can **Reset**.
- Exhibits tab holds a **comparative trial balance (year-6/year-5 columns, account
  numbers/descriptions)**, an email from the CFO, an A/R memo, board minutes.
- Explicit strategy taught: **glance at all exhibits first**, "**these individual
  questions are graded independently** so a wrong one only loses that blank,"
  **guess if stuck** (15–20% of items are unscored pretest anyway), and **scan for
  any still-blue markers before submitting** (the answered/unanswered icons are
  tiny and easy to miss).

**Post-submit / explanations.** Practice mode's instant answer+rationale; plus
instructional + solution videos in-platform. ReadySCORE reframes "results" as a
**predicted section score** rather than a raw %. [Surgent; Liz Kolar webinar]

**Test-accurate:** DRS underline→dropdown→Accept/Reset with answered markers;
directions lockout; independent per-blank grading; exhibit trial-balance framing.
**Gimmick-ish (for a _practice_ tool, not exam-accurate but arguably useful):**
ReadySCORE and adaptive daily "surge" are meta-layers around the sim, not part of
the sim UI.

Sources: sacbee.com Surgent review; wallstreetmojo.com Surgent review;
support.surgent.com A.S.A.P.; surgent.com CPA pages; YouTube `nvMzbHdP00w`,
`XOkIRjQVunE`, `6cJkkR00Mkw`.

---

### 2.5 Wiley (CPAexcel)

**Status:** **UWorld acquired Wiley CPAexcel in 2023** and merged the content into
the UWorld platform; it no longer exists as a standalone product, so its _current_
TBS UX **is UWorld's** (§2.2). Historical Wiley detail below for completeness.
[cpaexamguide "best courses"; ipassthecpaexam Wiley review]

**Historical fidelity.** "Exam simulator laid out just like the real exam";
practice exams "mirror the actual exam all the way down to the number, type, and
mix of questions, as well as time limits and break policies." Recognized the three
format families explicitly: **basic TBS, enhanced TBS, and DRS.** Signature
learning unit was the **30-minute "Bite-Sized Lesson"** (text + video + mini-quiz),
and it had one of the largest MCQ/TBS banks (with **~500 TBS**). [Efficient
Learning blog; ipassthecpaexam]

**Test-accurate:** faithful full-length exam-sim (numbers, timing, breaks).
**Notable idea worth stealing:** the **bite-sized lesson → mini-quiz** loop that
pinpoints weak areas — conceptually close to our spaced-practice model.

Sources: efficientlearning.com "Try these strategies… TBS"; ipassthecpaexam.com
Wiley review; cpaexamguide.com "best CPA review courses."

---

## 3. Cross-cutting patterns (what's universal vs. differentiated)

| Dimension                | Universal (all 5 ≈ AICPA)                                                                            | Where leaders differentiate                                                                                                                                                      |
| ------------------------ | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Exhibits**             | Separate **tabs**; consult _per requirement_, don't pre-read                                         | UWorld "exhibit management" + mobile-adapted tabs; Surgent frames a real comparative trial balance                                                                               |
| **Split-screen**         | Horizontal + vertical, **draggable resize**, can't dup a tab                                         | (parity across all)                                                                                                                                                              |
| **JE grid**              | Account **dropdown** + Dr/Cr + amount; positive amounts; **spare rows**; **"no entry required"**     | UWorld's sample is the cleanest reference                                                                                                                                        |
| **Numeric cells**        | Shaded direct-entry; whole numbers; **"enter 0 if zero"**; negatives for reductions                  | (parity)                                                                                                                                                                         |
| **Dropdown/choice**      | "Select Item" pop-up list; enforce "select N" for multi-select                                       | Farhat: eliminate options to raise odds                                                                                                                                          |
| **Research/AL**          | _Was_ searchable 3-pane (TOC/doc/search + "Search Within"); **2024 → excerpt-as-exhibit + citation** | Gleim mirrors AICPA menu ordering; all lean on the free AICPA sample                                                                                                             |
| **Calculator**           | Basic on-screen only                                                                                 | (all replicate; universally disliked)                                                                                                                                            |
| **Spreadsheet**          | SpreadJS-style scratch, resizable, **Ctrl-C/V only**, copy-from-exhibit                              | (parity; underused by candidates)                                                                                                                                                |
| **Timer/flags**          | Countdown (reddens near end); per-task reminder flags; see all sims in TBS testlet                   | Surgent teaches the 10-min directions lockout                                                                                                                                    |
| **Grading**              | **Per-blank** partial credit; **research all-or-nothing**; no wrong penalty                          | ✅ _exam-accurate_; ❌ Becker/Roger criticized for whole-row                                                                                                                     |
| **Results/explanations** | Show correct/incorrect + reveal answer                                                               | **UWorld** written rationales+diagrams; **Becker** SkillBuilder/ExamSolver videos; **Gleim** explanations + **blueprint refs**; **Surgent** instant (practice mode) + ReadySCORE |

---

## 4. Partial-credit & results treatment (deep dive)

- **Per-measurement-opportunity grading is the exam truth** and the thing to be
  faithful to: each blank scores independently; a candidate should be able to see
  _which specific blanks_ earned credit. Our server already returns per-step
  results — good. [another71]
- **Research is all-or-nothing** — if we build a research shape, grade the whole
  citation as one unit and _tell the learner that's how the exam does it._
- **Never-blank nudge:** because there's no wrong-answer penalty, good practice
  UIs encourage attempting every blank. Consider a pre-submit "you left N blanks —
  the exam has no wrong-answer penalty" nudge.
- **How results are shown, best → basic:**
  1. **Becker:** two-pane review, green/yellow/blue color states on every
     requirement + question number, and an **instructor video per sim**.
  2. **UWorld:** per-blank correct/incorrect + **written rationale with
     diagrams** + auto-surfaced mastery video.
  3. **Gleim:** correct/incorrect explanations + **AICPA Blueprint reference** tag.
  4. **Surgent:** instant answer+rationale (practice mode) or fully deferred (exam
     mode); **ReadySCORE** as a predicted-score framing.
  5. **Ankountant today:** ✓/✗ per step + a single "Partial credit X%." → this is
     the **thinnest** results layer of the set; biggest opportunity.

---

## 5. Test-accurate vs. simplifications/gimmicks (verdict)

**Genuinely test-accurate patterns worth matching exactly**

- Pencil-icon **work tabs** + exhibit tabs + Help; shaded gradable cells.
- **Account dropdown** (controlled list), **positive amounts + rounding**,
  **spare rows**, **"no entry required."**
- **DRS**: underlined-segment dropdown with **original text / delete (strike-through)
  / replace**, per-blank **answered marker**, Accept/Reset.
- **Split-screen with resize**; scratch calculator + **SpreadJS-style** sheet with
  **copy-from-exhibit**.
- **Per-blank partial credit; research all-or-nothing; no wrong penalty; timer
  that reddens near the end; triage across all sims in the testlet.**

**Simplifications that are fine (or good) for a practice tool**

- Instant per-blank feedback + reveal (exam defers everything to submit; practice
  should teach). Offer both — Surgent's dual practice/exam mode is the model.
- Auto-surfaced explanation videos / rationales (pure upside).
- Blueprint tagging (Gleim) — arguably _more_ useful than the exam itself.

**Anti-patterns / gimmicks to avoid**

- ❌ **Whole-row / all-or-nothing grading** (Becker/Roger complaint): under-scores
  learners and mis-teaches partial credit. We already grade per-step — keep it and
  _market it_.
- ❌ A **full spreadsheet** nobody uses, or a cumbersome calculator, built for
  fidelity's sake. Provide a light scratchpad; don't over-invest.
- ⚠️ **Advertising a "searchable authoritative-literature tool"** as if it were the
  exam — post-2024 the exam gives **excerpts**. Emulating a full searchable
  codification is _less_ accurate now (and a big build). Prefer excerpt-as-exhibit.
- ⚠️ Meta-scores (ReadySCORE) are marketing, not sim fidelity — fine as a separate
  readiness surface, don't bake into the sim.

---

## 6. Notable UX affordances worth copying

1. **Controlled account picker with autofill** (exam + UWorld): a searchable
   combobox seeded from a chart of accounts / the sim's allowed accounts. Type to
   filter, arrow to select, Enter to commit. Fixes both fidelity _and_ grading
   noise vs. our current free-text account field.
2. **"No entry required" affordance** per JE line/whole-entry, and **more rows than
   needed** — teaches candidates to _decide_ whether an entry exists.
3. **Positive-amounts + auto-round + "enter 0 if zero"** input contract, with a
   live "Dr = Cr" balance indicator (a _practice_ nicety the exam lacks but that
   accelerates learning without hiding the answer).
4. **Copy-from-exhibit → paste-into-cell / scratchpad** (SpreadJS Ctrl-C/V). Even a
   click-to-copy a figure from an exhibit is a real time-saver.
5. **Resizable, co-visible panes** so the active cell and the relevant exhibit are
   on screen together (kills split-attention). Our desktop already uses a **sticky
   side exhibit pane** — good; make exhibits **tabbed** when there are several and
   **resizable**.
6. **Requirement-first flow** (Andrew Katz / everyone): show requirements before
   dumping exhibits; consider collapsing exhibits until the learner opens them.
7. **Per-blank answered/unanswered markers + a pre-submit "N unanswered" scan**
   (Liz Kolar's tip about tiny icons) — a small, high-value safeguard.
8. **Keyboard-first entry:** Tab between cells, Dr/Cr via `d`/`c` keypress,
   arrow-key grid nav, Enter to commit a dropdown. None of the vendors are great at
   this; it's an easy way for us to feel _better than_ the real exam.
9. **Dual mode** (Surgent): "Study" (instant feedback) vs. "Exam" (deferred until
   submit, timed). Reuses one surface with a flag.
10. **Explanation depth per blank** (UWorld/Becker/Gleim): reveal the correct
    value, a one-line "why," and a **Blueprint/standard reference** (e.g. ASC 842).

---

## 7. Concrete recommendations for Ankountant

Grounded in our current code:
`ts/routes/(ankountant)/ankountant-tbs/TbsSurface.svelte`,
`ios/AnkountantApp/Sources/Simulations/TbsTaskView.swift`,
`ios/Sources/AnkiKit/TbsModels.swift`,
`ios/AnkountantApp/Sources/Simulations/ResearchTaskView.swift`, and
`ios/AnkountantApp/Sources/Simulations/DocReviewTaskView.swift`. Today
**`journal_entry` + `numeric` + `research` + `doc_review` are implemented** on
desktop and iOS; grading is **server-side** (`SubmitPerformanceAttempt`, answer
keys never sent to the client — keep this security model). Desktop already has a
sticky exhibit/document shell and the Ledger design system (tabular figures,
color-never-alone ✓/✗); iOS uses native simulation views and should keep
improving co-visibility on small screens.

### P0 — fidelity fixes to what we already ship

- **Replace the free-text JE account field with a controlled, searchable account
  picker.** Desktop: swap the `je-account` `<input>` for a combobox (list =
  allowed accounts for the sim, add to `RenderStep`/`TbsModel` a per-sim
  `accountOptions`); iOS: swap the account `TextField` for a searchable `Menu`/
  picker. This is the #1 fidelity + grading-quality win.
- **Add "no entry required"** (per entry) and **render 1–2 spare blank rows** so the
  learner must decide whether an entry exists.
- **Input contract:** enforce **positive amounts**, auto-round to whole numbers,
  accept a literal **0**, and show a **live Dr=Cr balance** hint on JE (practice
  aid, not an answer leak).
- **iOS exhibits: stop stacking below the task.** Move exhibits into **tabs / a
  segmented control / a pull-up sheet** so a cell and its exhibit are co-visible
  (match the desktop sticky pane intent).

### P1 — deepen the two formerly stubbed shapes

- **Document review (`doc_review`):** render the memo/document with **underlined
  segments**; tapping/clicking a segment opens a **dropdown** (`original text` /
  `delete` → strike-through / replacement options); show a **per-segment
  answered/unanswered marker**; support **Accept/Reset**. Reuse the server
  per-step grading (each segment = one step). This is now playable; the remaining
  gap is exam-grade interaction polish and seeded variety.
- **Research (`research`):** keep the **2024** shape, not the legacy searchable
  codification — show the **guidance excerpt as an exhibit** + a structured
  citation entry, and grade it **all-or-nothing** with a note that the exam does
  the same. Current surfaces are playable; next improvements are segmented
  citation controls, richer result explanations, and more section coverage.

### P2 — make the **results layer** our differentiator

- Beyond ✓/✗ + %: on submit, **reveal the correct value per blank**, a **one-line
  rationale**, and a **standard/Blueprint reference** (e.g. "ASC 360 — PP&E").
  Store these on the note (server returns them post-grade so keys stay server-side
  until submit). This closes the gap to UWorld/Becker/Gleim.
- Adopt **green/incorrect/blue = unanswered** review states (we already do
  color-never-alone ✓/✗; add the **unanswered** state + a **pre-submit "N blanks
  empty; no wrong-answer penalty" nudge**).
- **Dual mode** flag on the surface: _Study_ (instant per-blank feedback) vs.
  _Exam_ (deferred until Submit; timed). One component, one boolean.

### P3 — exam-sim ergonomics (do later / behind an "Exam mode")

- **Scratchpad + copy-from-exhibit** (click-to-copy a figure into a cell). A tiny
  calculator is enough; **do not** build a full spreadsheet.
- **Resizable, tabbed exhibits** on desktop when a sim has several; **split-view**
  parity.
- **Keyboard-first grid**: Tab between cells, `d`/`c` for Dr/Cr, arrows to move,
  Enter to commit the account dropdown — an area where we can beat the real exam.
- Optional **timer that reddens near the end** + **flag-for-review** + a
  triage list across a multi-sim testlet.

**Sequencing:** P0 (fidelity of shipped shapes) → P1 (doc-review + research
coverage) → P2 (results/explanations differentiator) → P3 (exam-sim polish).

---

## Sources

**AICPA ground truth / CPA Evolution**

- Andrew Katz Tutoring — "CPA Exam Simulation Strategy (2026)":
  https://andrewkatztutoring.com/cpa-exam-simulation-strategy/
- Becker Course User Guide (documents the exam-emulating sim UI):
  http://onlinestatic.becker.com/public/2013BeckerKB/2013%20Course%20User%20Guide.pdf
  and https://onlinestatic.becker.com/public/2012BeckerKB/manual/2012CourseUserGuide.pdf
- AICPA SpreadJS FAQ (spreadsheet, Ctrl-C/V, resize):
  https://assets.ctfassets.net/rb9cdnjh59cm/6TpbsHENfAPsJDcyMiWxXD/9d62b98e76a7bc8875a5a7940302ee49/92317096_2306-393888_cpa_exam_spreadjs_-_faq_updates_final.pdf
- AICPA "Infrastructure changes to the CPA Exam in 2024" (Excel→SpreadJS; research):
  https://assets.ctfassets.net/rb9cdnjh59cm/4qZw9ND4KRtVTrb8XcSOJB/5918af32470079a0ca3712ace8ceed62/infrastructure-changes-to-CPA-Exam-in-2024.pdf
- MNCPA — "CPA Evolution explained" (AL→excerpts; no WC; SpreadJS):
  https://www.mncpa.org/resources/publications/footnote/june-july-2023/cpa-evolution-explained/
- Going Concern — "What are Task-Based Simulations?" (tab set):
  https://www.goingconcern.com/cpa-exam-task-based-simulations/
- another71 forum — "How Are SIMs Actually Graded???" (per-blank; research all-or-nothing):
  https://forum.another71.com/forum/welcome-cpa-exam-forum/the-forum/topic/how-are-sims-actually-graded/
- CPA Exams Mastery — FAR scoring & question types (partial credit):
  https://cpaexamsmastery.com/far/exam-structure-and-far-overview/scoring-and-question-types/

**Becker**

- becker.com blog — "5 ways to prepare for TBS":
  https://www.becker.com/blog/accounting/5-ways-to-prepare-for-task-based-simulations
- becker.com — CPA videos (SkillBuilder / ExamSolver):
  https://www.becker.com/cpa-review/courses/cpavideos
- becker.com — Support products (ExamSolver, 900+ videos):
  https://www.becker.com/support-products
- cpaexamguide.com — Becker review (hands-on):
  https://www.cpaexamguide.com/review-courses/becker

**UWorld (Roger)**

- UWorld — CPA Task-Based Simulations:
  https://accounting.uworld.com/cpa-review/cpa-courses/features/tbs/
- UWorld — Practice Exams / QBank (Exam Sim mode):
  https://accounting.uworld.com/cpa-review/cpa-courses/features/practice-exams/

**Gleim**

- Gleim — "Practice CPA Exam" (Exam Rehearsal):
  https://www.gleim.com/cpa-review/blog/practice-cpa-exam/
- Gleim — "AICPA Sample Test Updates" (toolbar, AL pop-up):
  https://www.gleim.com/cpa-review/blog/aicpa-sample-test-updates/
- Gleim — "Updated CPA Sample Exam and Tutorial" (explanations + blueprint refs):
  https://www.gleim.com/cpa-review/blog/2019-cpa-sample-exam/

**Surgent**

- Surgent — CPA Exam Review (ReadySCORE, 500+ sims):
  https://www.surgent.com/exam-review/cpa-exam-review/
- Surgent support — "What is A.S.A.P. Technology?":
  https://support.surgent.com/hc/en-us/articles/15051140376333-What-is-A-S-A-P-Technology
- WallStreetMojo — Surgent review (practice vs exam mode; phases):
  https://www.wallstreetmojo.com/surgent-cpa-review/
- SacBee — Surgent review (exam simulator modes):
  https://www.sacbee.com/careers-education/surgent-cpa-review/

**Wiley (CPAexcel → UWorld)**

- ipassthecpaexam — Wiley CPAexcel review (bite-sized lessons; 500+ TBS):
  https://ipassthecpaexam.com/wiley-cpa-review-cpaexcel/
- Efficient Learning — "Try these strategies… TBS" (basic/enhanced/DRS; mirrors exam):
  https://www.efficientlearning.com/blog/try-these-strategies-improve-your-performance-task-based-simulations/
- cpaexamguide — "Best CPA Review Courses" (Wiley acquired by UWorld 2023):
  https://www.cpaexamguide.com/best-cpa-review-courses

**Video walkthroughs (YouTube; transcripts pulled where captions existed)**

- `4k0a8dUeyKI` — "PP&E Acquisition through Sale — UWorld CPA Review TBS Sample"
  (best JE-grid ergonomics artifact): https://www.youtube.com/watch?v=4k0a8dUeyKI
- `fPCHmyQLlUA` — Roger Philipp, "New CPA Exam TBS: Document Review Simulations"
  (narrates actual AICPA released DRS + research): https://www.youtube.com/watch?v=fPCHmyQLlUA
- `nvMzbHdP00w` — Liz Kolar (Surgent), "Document Review Simulation (DRS) for AUD
  Walkthrough" (richest DRS mechanics): https://www.youtube.com/watch?v=nvMzbHdP00w
- `DODYBfh3-70` — Farhat Lectures, "How to Solve CPA Exam Simulations?" (the four
  shapes + UI primitives): https://www.youtube.com/watch?v=DODYBfh3-70
- `EeNm6wH_b0o` — Roger CPA, "Using AICPA Sample Tests" (sample-test IA, "How did I
  do?" results, blue = has-input): https://www.youtube.com/watch?v=EeNm6wH_b0o
- `AlMmjGlUhrI` — Becker, "SkillBuilder video for task-based simulations" (no
  captions; instructor TBS walkthrough): https://www.youtube.com/watch?v=AlMmjGlUhrI
- `suJstixB4zE` — UWorld, "TBS Mastery Webinar, Part 1":
  https://www.youtube.com/watch?v=suJstixB4zE
- `XOkIRjQVunE` — Surgent, "What is a Document Review Simulation (DRS)?":
  https://www.youtube.com/watch?v=XOkIRjQVunE

_Research current as of Jul 2026. The paid product UIs sit behind paywalls; detail
is triangulated from vendor docs, hands-on third-party reviews, the Becker Course
User Guides, AICPA change notices/FAQ, and narrated walkthroughs of actual AICPA
released sims. Where a vendor's marketing conflicts with the 2024 exam (e.g. a
"searchable authoritative-literature tool"), the AICPA CPA Evolution notices are
treated as authoritative._
