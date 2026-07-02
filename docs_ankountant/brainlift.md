## Purpose

To establish a research-backed, first-principles foundation for **Ankountant** - an Anki-forked desktop + mobile study app for the accounting **CPA exam**. Helping CPA candidates pass the exam will require the app to keep the following in mind:

- **Memory** - can the student _recall_ a taught fact? (Anki's FSRS handles raw recall well, but it optimizes open-ended retention rather than peaking on a fixed exam date; the scheduler needs reworking for that - see the deadline-scheduling SPOV.)
- **Performance** - can the student answer a _new, exam-style_ question that uses that fact, including ones never seen? (the memory → transfer bridge.)
- **Readiness** - what would the student _score today_, expressed as a _range with a confidence level_, abstaining when evidence is insufficient? (the performance → score bridge.)

This brainlift grounds product design in cognitive/learning science rather than basic assumptions.

> _NOTE:_ AI was used to find the list of EXperts, DOK1s, sources, and brainstormed the "Features to Build in the Anki Fork" section based off of the DOK4s.

### In Scope

- The learning science of durable skill: spaced repetition & forgetting, retrieval practice, transfer, desirable difficulties, cognitive load, feedback, metacognition.
- Psychometrics & score prediction: item-response theory, adaptive testing, calibration, selective prediction/abstention.
- AI card-generation safety & assessment validity (item quality, data leakage, hallucination, traceability).
- The CPA exam's real structure & scoring (CPA Evolution Core + Discipline; pass rates; question types; scaled scoring).
- The CPA test-prep market & competitive landscape (it motivates why CPA was chosen and the entry strategy).
- Learning-science study features suitable for the project's required ablation study.

### Out of Scope

- Engineering plumbing: the Anki Rust fork, cross-device sync internals, build/installer mechanics.
- Generic flashcard UI/visual design.
- Non-CPA exams (MCAT/LSAT/GMAT/USMLE appear only as contrast where useful).

## DOK 4 - Spiky Points of View (SPOVs)

- ! **SPOV 1:** Anki + FSRS reward comfy, high-volume review (streaks + raw review counts + a ~90% success target), so most reps are easy by design; but effortful retrieval, not comfortable review, is what actually builds durable memory (Roediger & Karpicke: testing beat studying 61% vs 40% at one week, and the studiers forgot more _and_ grew more confident while doing worse; Kornell & Bjork: learners keep preferring the easy option even after seeing the hard one win) --> Ankountant makes you commit an answer + a confidence _before_ the reveal, rewards effortful reps over volume, and uses answer latency (which Anki logs but ignores) to catch too-easy cards and shove their intervals way out or swap in a harder probe; difficulty is time-relative, so the one dial is days-to-exam: effort early, consolidation late.
- ! **SPOV 2:** FSRS was trained to minimize lifelong review cost at a fixed ~90% retention (Ye et al., 220M MaiMemo logs) and has no finish line (its retention knob is even global, not per-deck); but a CPA section is one 4-hour sitting on a candidate-chosen date, so you want recall to peak _that day_, not forever (Cepeda: the ideal spacing gap grows with how long you need to remember) + passing is a threshold (75), not a max, so grinding a known card from 90% to 95% is wasted effort that should go to weak topics --> Ankountant adds a deadline-anchored scheduler: exam date as a first-class object, intervals computed backward from it, desired retention ramping up as the date nears, and recall projected for exam day rather than today.
- ! **SPOV 3:** A topic-named deck hands you the category for free (open the "Leases" deck and you already know it's a lease question), drilling exactly the surface-feature habit that sinks candidates: experts sort by deep principle, novices by surface features (Chi 1981), interleaving crushes blocking (Rohrer 63% vs 20%, still 74% vs 42% at 30 days), and blockers' errors are wrong-_method_ picks, not mis-execution; this bites hardest on FAR + BAR (~42% pass, precisely the "which standard applies?" sections) --> Ankountant makes the _confusion set_ the core primitive: a curated map of classic CPA traps (capitalize vs expense, operating vs finance lease, the rev-rec steps), a label-stripped "which treatment?" gate before any math, mastery scored on discrimination, and topic decks demoted to a reference glossary.
- ! **SPOV 4:** Scoring "readiness" on the same items someone already drilled is just re-measuring recall; real transfer needs a novel surface (Gick & Holyoak: only ~30% spontaneous transfer even after seeing the analog), and since LLMs regurgitate their training data (Ji et al.), a generator that wrote the study cards will leak them into supposedly "new" tests unless the pipelines are firewalled --> Ankountant keeps two pools per topic: normal study cards (the Memory pillar) + a _sealed_, never-studied, same-topic/new-surface bank that exists only to measure; the recall-vs-sealed gap is the honest "feels ready, isn't" signal, and Readiness is a projected 0-99 score _range with a confidence level_ computed only on the firewalled items that _abstains_ when held-out coverage or volume is too thin.
- ! **SPOV 5:** TBSs are ~half of every section's score (three of five testlets, 50/50, or 60/40 for ISC) and they're multi-step _application_ tasks, so the flashcard primitive (one recall + one self-graded button) structurally can't represent them, yet every incumbent just bolts a TBS bank onto a flashcard app --> Ankountant makes TBS a first-class, step-graded review mode with partial credit per step (research sims = cite-lookup drills against embedded FASB/IRC/PCAOB scored on correctness + time, journal-entry + numeric = line-by-line grading, doc-review = reused "which treatment?" calls), grades method-vs-slip instead of one binary lapse (fixing Anki's "fail resets the interval"), and feeds one honest Performance score on a separate data path that keeps the sealed-bank firewall clean.
- ! **SPOV 6:** Becker's dominance is B2B lock-in, not a better product: firms hand each new hire a paid license, so the candidate never makes the purchase call and only shops for an alternative _after_ they've already failed, which makes attacking that channel head-on a ~$10-20M, 3-5-year dead end selling to risk-averse L&D buyers --> Ankountant enters B2C first, aimed at the ~70-80k annual failed attempts (retakers + self-funded international + career-changers) who choose for themselves and where incumbents are structurally weak, selling the honest diagnosis its 3 scores deliver (Memory + Performance + Readiness); the B2B readiness/analytics layer comes _after_ scale, layered on top of existing Becker contracts rather than fighting for the course slot. _(Market figures are vendor estimates, directional not audited.)_

## Experts

- **Henry L. Roediger III** - Retrieval-practice researcher (WashU); his work that active recall-not re-study-drives long-term retention is the core warrant for Ankountant's Memory-pillar scheduling logic.
- **Jeffrey D. Karpicke** - Learning scientist (Purdue); landmark 2008 _Science_ paper showing repeated retrieval outperforms repeated review is the empirical backbone of the testing-effect pillar.
- **Robert A. Bjork & Elizabeth Ligon Bjork** - Coined "desirable difficulties" and the storage/retrieval-strength distinction (UCLA); explains why high in-session fluency is a poor predictor of durable retention.
- **Doug Rohrer** - Interleaved-practice researcher (USF); largest preregistered RCT of interleaving (61% vs. 38%, d = 0.83) directly informs how Ankountant mixes CPA topics to train strategy-selection.
- **John Sweller** - Originator of cognitive load theory (UNSW); his intrinsic/extraneous/germane load framework defines the working-memory constraints Ankountant's card-complexity calibration must respect.
- **Michelene T. H. Chi** - Expert-novice and ICAP researcher (ASU); ICAP engagement-mode taxonomy classifies Ankountant question types and distinguishes passive recognition from active construction.
- **Nate Kornell** - Metacognition researcher (Williams College); demonstrated learners prematurely drop cards because fluency masquerades as durable learning-the failure Ankountant's calibration warnings counteract.
- **David Dunning** - Co-originator of the Dunning-Kruger effect (UMich); calibration research grounds Ankountant's policy of abstaining from score predictions when evidence is too thin.
- **Piotr Woźniak** - Developed SM-2 (1987), the open-standard scheduler adopted by Anki and the baseline against which FSRS is benchmarked; Ankountant's scheduling engine inherits its core parameters.
- **Jarrett Ye (L.M.Sherlock)** - Creator of FSRS, the ML-based scheduler natively integrated into Anki (v23.10+) and the direct upstream of Ankountant's Memory-pillar scheduler.
- **Susan E. Embretson** - Cognitive-psychometric IRT researcher (Georgia Tech); her framework embedding cognitive task analysis into test-item models underpins Ankountant's Readiness-pillar score-range estimation.
- **Thomas M. Haladyna** - Originator of the most-cited MC item-writing taxonomy (ASU emeritus); his guidelines for stem clarity and plausible distractors define the quality bar for Ankountant's AI card generator.
- **AICPA** - Sole authoritative source for the CPA Exam Blueprints, IRT-based scoring (0-99, passing = 75), and quarterly pass-rate data that Ankountant's Readiness-pillar calibrates against.
- **NASBA** - Co-administrator of the Uniform CPA Examination; authoritative source for pass-rate trends, licensing-window rules, and candidate demographics used to contextualize Readiness projections.
- **Damien Elmes** - Creator of Anki (2006); the ankitects/anki repo (28,600+ stars) is the directly upstream engine Ankountant forks, and its AGPL-3.0 license defines Ankountant's legal constraints.

## DOK 3 - Insights

### Memory & Spaced Repetition

- In-session ease is a misleading signal: streaks, review counts, and a fixed ~90% success target all reward fluency, which the metacognition research (Kornell & Bjork, 2008) flags as exactly the cue learners should distrust. Answer latency, which Anki records but discards, is an unused proxy for effort.
- Because an exam is a dated event, FSRS's lifelong-retention objective is the wrong one: the spacing gap should be a function of days-to-exam (Cepeda et al., 2006), letting low-reuse items decay after their last pre-exam touch so the saved minutes go to weak topics.

### Transfer & Desirable Difficulties

- The CPA's failure mode, the novice's mistake in Chi (1981), and the blocked learner's errors in Rohrer (2007) are the same phenomenon: mis-discrimination among confusable deep structures, not forgetting. The hardest, lowest-pass sections (FAR and BAR, ~42%) are precisely the discrimination-heavy ones.
- A topic-labeled deck freezes the novice's surface taxonomy into the interface; stripping labels and forcing a "which method applies?" choice before solving trains the skill the exam actually tests.

### Cognitive Load, Feedback & Study-Feature Design

- A card's format and schedule should depend on its element-interactivity and the learner's expertise - an atomic fact and a twelve-step procedure should not be scheduled identically - yet SM-2 and FSRS are expertise-blind.
- "Fail resets the interval" is a category error for multi-step problems: one arithmetic slip nukes an otherwise-known item, so outcomes should be tracked at the step level (method-correct vs execution-slip), which also yields richer feedback than a single grade.

### Metacognition & Calibration

- Subjective confidence is a poor readiness signal: the dangerous student is the confidently-wrong one who abandons a weak area because it feels fluent, so the overconfidence gap is a leading risk indicator.
- Capturing confidence _before_ the reveal (rather than self-rating after seeing the answer) is what makes that gap measurable in the first place.

### Psychometrics & Score Prediction

- The CPA's 75 is a scaled score on a 0-99 IRT scale, not a percent correct, and the scaling transform is not public - so Readiness should be a projection onto that scale expressed as a range, never a single fabricated point, and it should abstain when the evidence is too thin to support even a range.

### AI Card-Generation Safety & Assessment Validity

- RAG can scale a deck to tens of thousands of cards, but a wrong fact is worse than no card, so the value is in the checker, not the generator. Every generated card needs a traceable source passage and a pass through a gold-set quality gate (correct-and-useful vs wrong vs correct-but-bad-teaching, with the cutoff set before looking) and must beat a simple keyword/vector baseline before it ships.

### CPA Exam Structure & Scoring

- The 2024 shift to a linear exam decouples two things competitors weld together: estimating the student efficiently vs simulating the fixed form to project a score.
- Scoring is 50/50 MCQ/TBS (60/40 for ISC) with open-literature research simulations, so a recall-only deck over-serves the MCQ half and ignores the application half; TBSs, being multi-step tasks rather than recall, need their own step-graded review mode rather than being forced into the flashcard primitive.

### CPA Market & Competitive Landscape

- Becker's dominance is a B2B lock-in rather than a product advantage (the candidate never chose it and only shops after failing), which makes the retaker segment - roughly half of all attempts fail - the one place incumbents are structurally disadvantaged.
- ISC's high pass rate (~68%) means low pain and low willingness to pay, whereas FAR (~42%, taken by every candidate) is where pain, volume, and the honest-measurement thesis converge.

## DOK 2 - Knowledge Tree

### Category 1: Memory & Spaced Repetition

#### Subcategory 1.1: Spacing Effect - Distributed vs. Massed Practice

**Source:** Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer, D. (2006). Distributed practice in verbal recall tasks: A review and quantitative synthesis. _Psychological Bulletin, 132_(3), 354-380.

- **DOK 1 - Facts:**
  - Meta-analysis (**839 assessments / 317 experiments**, verbal recall): **259 of 271** massed-vs.-spaced comparisons (~95.6%) favored spacing.
  - Final-test accuracy **47.3% spaced vs. 36.7% massed** overall, widening to **62.2% vs. 32.8%** at 8-30 day retention; the optimal inter-study gap **grows with the target retention interval** - no single fixed gap is universally optimal.
- **Link:** https://doi.org/10.1037/0033-2909.132.3.354

- ! **DOK 2 - Summary:** spacing study sessions out beats cramming for durable recall (~47% vs ~37% overall, 62% vs 33% at 8-30 days); the longer you need to retain something, the wider the gaps should be --> no single fixed interval is optimal

---

#### Subcategory 1.2: Retrieval Practice (Testing) Effect

**Source:** Roediger, H. L., III, & Karpicke, J. D. (2006). Test-enhanced learning: Taking memory tests improves long-term retention. _Psychological Science, 17_(3), 249-255.

- **DOK 1 - Facts:**
  - Repeated study (SSSS) vs. repeated testing (STTT) on prose passages: at **5 min** study won (**83% vs. 71%**), but at **1 week** it fully reversed - **STTT 61% vs. SSSS 40%** (Cohen's _d_ = 1.26).
  - The study group forgot far more (**52% vs. 14%**) yet grew _more_ confident it would remember - a metacognitive inversion.
- **DOK 2 - Summary:** long-term memory/recall is boosted by more testing blocks compared to study; pure studying creates the dunning-kruger effect --> increased self-perceived confidence
- **Link:** https://doi.org/10.1111/j.1467-9280.2006.01693.x

---

#### Subcategory 1.3: SR Algorithm Lineage - SM-2 → FSRS

**Source:** Woźniak, P. A. (1990). _Optimization of learning_ (Master's thesis, University of Technology in Poznan). [SM-2 algorithm; archived at supermemo.guru / supermemo.com]

- **DOK 1 - Facts:**
  - SM-2 was the **first SR scheduling algorithm** (SuperMemo, 1987): a per-item **ease factor** updated by a **0-5** response rating, with initial intervals of **1 and 6 days** growing multiplicatively.
  - Anki ran on SM-2 from its inception until FSRS support arrived in **Anki 23.10 (2023)**.
- **Link:** https://www-beta.supermemo.com/archives1990-2015/english/ol/sm2

**Source:** Ye, J., Su, J., & Cao, Y. (2022). A stochastic shortest path algorithm for optimizing spaced repetition scheduling. In _Proceedings of the 28th ACM SIGKDD Conference on Knowledge Discovery and Data Mining_ (KDD '22), pp. 4381-4390. ACM. [FSRS foundational paper + Anki 23.10 integration]

- **DOK 1 - Facts:**
  - FSRS trained a memory model on **220M MaiMemo review logs** to minimize total review cost, benchmarking **~12.6% better** than prior methods.
  - Shipped natively in **Anki 23.10** (Oct 31, 2023) as an **opt-in, global-only** alternative to SM-2; default desired retention is **90%** (the manual warns workload balloons above 97%).
- **Link:** https://doi.org/10.1145/3534678.3539081 (paper); https://github.com/ankitects/anki/releases/tag/23.10 (Anki 23.10 release notes); https://docs.ankiweb.net/deck-options.html (Anki manual - FSRS section)

- ! **DOK 2 - Summary:** SM-2 (1987) is the original spaced-repetition scheduler anki was built on; FSRS is the modern ML-trained successor (220M review logs, ~12.6% better) anki now ships opt-in at a default 90% target retention --> SR has moved from hand-tuned heuristics to data-trained scheduling

### Category 2: Transfer of Learning & Desirable Difficulties

---

#### Subcategory 2.1: Expert-Novice Problem Categorization

**Source:** Chi, M. T. H., Feltovich, P. J., & Glaser, R. (1981). Categorization and representation of physics problems by experts and novices. _Cognitive Science_, 5(2), 121-152.

- **DOK 1 - Facts:**
  - **8 experts** (physics PhDs) and **8 novices** each sorted 24 mechanics problems "by how they would be solved."
  - **All 8 novices** grouped by **surface features** (inclined plane, pulley, spring); **6 of 8 experts** grouped by **deep principle** (conservation of energy, F = MA) - "this deep structure is the basis by which experts group the problems."
- **Link:** https://doi.org/10.1207/s15516709cog0502_2

- ! **DOK 2 - Summary:** experts sort problems by deep structure (the underlying principle); novices sort by surface features (the objects in the problem) --> spotting 'which principle applies' is the real skill, not memorizing surface details

---

#### Subcategory 2.2: Analogical Transfer and Schema Induction

**Source:** Gick, M. L., & Holyoak, K. J. (1983). Schema induction and analogical transfer. _Cognitive Psychology_, 15(1), 1-38.

- **DOK 1 - Facts:**
  - On Duncker's radiation problem (base rate ~10%): one analog **plus an explicit hint** yielded **~75%** solutions, but **spontaneous** (no-hint) transfer was only **~30%**.
  - Comparing **two** analogs (describing their similarity) raised spontaneous transfer to **~45%**, and the quality of the abstracted schema strongly predicted transfer - one worked example wasn't enough.
- **Link:** https://doi.org/10.1016/0010-0285(83)90002-6

- ! **DOK 2 - Summary:** people rarely apply a known method to a new-looking problem on their own (~30% even when they've seen the analog); comparing two examples of the same principle is what builds a transferable schema --> one worked example isn't enough

---

#### Subcategory 2.3: Interleaving, Discrimination Training, and Delayed Test Accuracy

**Source:** Rohrer, D., & Taylor, K. (2007). The shuffling of mathematics problems improves learning. _Instructional Science_, 35(6), 481-498.

- **DOK 1 - Facts:**
  - Interleaved/mixed practice beat blocked on a 1-week test - **63% vs. 20%** (d = 1.34) - even though blockers scored higher _during_ practice (89% vs. 60%): a "desirable difficulty."
  - Nearly all blocker errors were **choosing the wrong formula**, not misexecuting it - discrimination is trained only when problem types are mixed.
- **Link:** https://doi.org/10.1007/s11251-007-9015-8

**Source:** Rohrer, D., Dedrick, R. F., & Stershic, S. (2015). Interleaved practice improves mathematics learning. _Journal of Educational Psychology_, 107(3), 900-908.

- **DOK 1 - Facts:**
  - Classroom replication (**N = 126**, 7th grade, ~3 months): interleaved beat blocked **80% vs. 64%** at 1 day and **74% vs. 42%** at 30 days (d = 0.79), despite near-equal practice accuracy.
  - Interleaving gave "near immunity against forgetting" - a 30× longer delay dropped scores only from 80% to 74%.
- **Link:** https://doi.org/10.1037/edu0000001

- ! **DOK 2 - Summary:** interleaved practice is far superior is enhancing long-term recall compared to blocking --> only slight percentage drop-off in recall after 30 days

### Category 3: Cognitive Load, Feedback & Study-Feature Design

---

#### Subcategory 3.1: Cognitive Load Theory - Architecture & Instructional Effects

**Source:** Sweller, J., van Merriënboer, J. J. G., & Paas, F. (2019). Cognitive Architecture and Instructional Design: 20 Years Later. _Educational Psychology Review_, 31(2), 261-292.

- **DOK 1 - Facts:**
  - Three load types: **intrinsic** (element interactivity of the material), **extraneous** (how it's presented), and **germane** (WM devoted to schema-building); working memory is limited **only for novel information** - the limit disappears once it's in long-term memory.
  - **Worked-example effect**: for novices, studying a fully worked solution beats solving from scratch (which consumes all WM, leaving none for schema acquisition).
  - **Expertise-reversal effect**: novice-oriented guidance loses value and can eventually _reverse_, harming performance, as expertise grows.
- **Link:** https://doi.org/10.1007/s10648-019-09465-5

- ! **DOK 2 - Summary:** Worked examples first when learners have little-to-no pre-existing schema to retrieve from; working memory gets bogged down otherwise and cannot properly learn. When the learner can reliably follow and self-explain solutions, drop guidance; self-testing w/o guidance becomes more effective for further learning.

---

#### Subcategory 3.2: Feedback Science - When Feedback Hurts and What Makes It Work

**Source:** Kluger, A. N., & DeNisi, A. (1996). The effects of feedback interventions on performance: A historical review, a meta-analysis, and a preliminary feedback intervention theory. _Psychological Bulletin_, 119(2), 254-284.

- **DOK 1 - Facts:**
  - Meta-analysis (**607 effect sizes**, 131 studies): feedback helped on average (d = .41) but **over a third of interventions made performance _worse_**.
  - Effectiveness drops as attention shifts up from the task toward the **self** - ego/identity-directed feedback is the most likely to hurt.
- **Link:** https://doi.org/10.1037/0033-2909.119.2.254

**Source:** Hattie, J., & Timperley, H. (2007). The power of feedback. _Review of Educational Research_, 77(1), 81-112.

- **DOK 1 - Facts:**
  - Feedback is a top influence on achievement (avg ES **0.79**) and answers three questions - _Feed Up_ / _Feed Back_ / _Feed Forward_ - across four levels: Task, Process, Self-Regulation, Self.
  - It works best at the **task / process / self-regulation** levels; **self-level** feedback (praise at the person) is weak (ES 0.12) and "deflects attention from the task."

- **Link:** https://doi.org/10.3102/003465430298487

- ! **DOK 2 - Summary:** Feedback needs to be centered around the task/process/self-regulation to be effective (FT, FP, FR). Feedback to the self/ego (meta feedback) is ineffective, and can be detrimental

### Category 4: Metacognition & Calibration

#### Subcategory 4.1: Systematic Overconfidence and the Metacognitive Competence Gap

**Source:** Kruger, J., & Dunning, D. (1999). Unskilled and unaware of it: How difficulties in recognizing one's own incompetence lead to inflated self-assessments. _Journal of Personality and Social Psychology_, 77(6), 1121-1134.

- **DOK 1 - Facts:**
  - Across 4 studies, the **bottom quartile** scored at the **12th percentile** but rated themselves at the **62nd** - a ~50-point overestimation.
  - A "dual burden": being unskilled also strips the metacognitive skill needed to notice it; brief training improved self-recognition.
- **Link:** https://doi.org/10.1037/0022-3514.77.6.1121

- ! **DOK 2 - Summary:** the least skilled overestimate themselves the most (bottom quartile scored at the 12th percentile but felt like the 62nd); being bad at something also strips the ability to notice you're bad --> weak students' self-assessments can't be trusted

---

#### Subcategory 4.2: The Fluency Illusion - Feeling-of-Knowing Does Not Equal Retrievability

**Source:** Koriat, A., & Bjork, R. A. (2005). Illusions of competence in monitoring one's knowledge during study. _Journal of Experimental Psychology: Learning, Memory, and Cognition_, 31(2), 187-194.

- **DOK 1 - Facts:**
  - Judgments of learning are systematically inflated because they're made **while the answer is visible** - a condition absent at test - which the authors call a "foresight bias."
  - On backward-associated pairs, predicted recall averaged **75.7%** but actual recall was **60.3%** (~16-point overestimation).
- **Link:** https://doi.org/10.1037/0278-7393.31.2.187

**Source:** Kornell, N., & Bjork, R. A. (2008). Learning concepts and categories: Is spacing the "enemy of induction"? _Psychological Science_, 19(6), 585-592.

- **DOK 1 - Facts:**
  - Learning to classify 12 artists' painting styles: **spaced/interleaved beat massed** (61% vs. 35%, d = 0.99).
  - Yet ~**78-83% rated massing as equal or better** even after seeing their own results - fluency masquerades as learning.
- **Link:** https://doi.org/10.1111/j.1467-9280.2008.02127.x

- ! **DOK 2 - Summary:** feeling fluent while studying does not equal being able to recall later; learners consistently rate the worse method (massing / seeing the answer) as better, and the illusion holds even after they see their own results --> subjective confidence is a bad readiness signal

---

#### Subcategory 4.3: Measuring Calibration - Brier Score and Murphy's Three-Term Decomposition

**Source:** Murphy, A. H. (1973). A new vector partition of the probability score. _Journal of Applied Meteorology_, 12(4), 595-600.

- **DOK 1 - Facts:**
  - The Brier score (mean squared error of probabilistic forecasts; Brier 1950) decomposes into **reliability** (do forecast probabilities match reality?), **resolution** (can you separate hard from easy cases?), and irreducible **uncertainty**.
  - Always forecasting the base rate gives **perfect reliability but zero resolution** - so both must be measured, not calibration alone.
- **Link:** https://journals.ametsoc.org/view/journals/apme/12/4/1520-0450_1973_012_0595_anvpot_2_0_co_2.xml

- ! **DOK 2 - Summary:** you can score how honest a probability is with a brier score, which splits into reliability (do your confidences match reality?) and resolution (can you separate hard from easy?); always forecasting the base rate gives perfect reliability but zero resolution --> measure both, not just calibration

### Category 5: Psychometrics & Score Prediction

#### Subcategory 5.1: Item Response Theory (IRT)

**Source:** Embretson, S. E., & Reise, S. P. (2000). _Item Response Theory for Psychologists_. Lawrence Erlbaum Associates.

- **DOK 1 - Facts:**
  - IRT models the probability of a correct answer as a logistic function of a latent ability **θ** plus item parameters: **difficulty (b)** in the 1PL/Rasch, **+ discrimination (a)** in the 2PL, **+ guessing (c)** in the 3PL.
  - Item parameters and ability estimates are **sample-invariant** (unlike classical test theory), so they sit on a shared scale.
- **Link:** https://doi.org/10.4324/9781410605269

- ! **DOK 2 - Summary:** IRT predicts the chance of a correct answer from a student's latent ability (theta) plus item params - difficulty, discrimination, guessing - estimated on a shared, sample-invariant scale --> the math for projecting a score from question-by-question performance

---

#### Subcategory 5.2: Computerized Adaptive Testing (CAT)

**Source:** van der Linden, W. J., & Glas, C. A. W. (Eds.). (2010). _Elements of Adaptive Testing_. Springer.

- **DOK 1 - Facts:**
  - CAT uses IRT to pick each next item to be **maximally informative** at the current ability estimate (max Fisher information), shrinking the standard error fastest.
  - It can stop on a **fixed length**, a **precision threshold**, or once a **pass/fail decision** is confident enough - a built-in stop/abstain rule.
- **Link:** https://link.springer.com/book/10.1007/978-0-387-85461-8

- ! **DOK 2 - Summary:** adaptive testing picks each next item to be most informative at the current ability estimate, reaching a confident estimate in fewer questions; it can stop on a fixed length, a precision target, or once a pass/fail call is confident enough --> efficient ability estimation + a natural stopping/abstain rule

---

#### Subcategory 5.3: Selective Prediction & Proper Scoring Rules

**Source:** El-Yaniv, R., & Wiener, Y. (2010). On the foundations of noise-free selective classification. _Journal of Machine Learning Research_, 11, 1605-1641.

- **DOK 1 - Facts:**
  - **Selective classification** = "classification with a reject option": the model either predicts or **abstains**, trading **coverage** for lower **risk** on what it does accept.
  - The Bayes-optimal rule (Chow) is to abstain whenever the top class probability falls below a threshold.
- **Link:** https://www.jmlr.org/papers/v11/el-yaniv10a.html

**Source:** Gneiting, T., & Raftery, A. E. (2007). Strictly proper scoring rules, prediction, and estimation. _Journal of the American Statistical Association_, 102(477). DOI: 10.1198/016214506000001437.

- **DOK 1 - Facts:**
  - A **strictly proper** scoring rule uniquely rewards reporting your **true** probabilities (S(Q,Q) ≥ S(P,Q), equality iff P = Q).
  - The **Brier** and **logarithmic** scores are strictly proper; improper rules create perverse incentives to distort forecasts.
- **Link:** https://doi.org/10.1198/016214506000001437

- ! **DOK 2 - Summary:** models can be allowed to abstain (a 'reject option') when unsure, trading coverage for accuracy; and strictly-proper scoring rules (brier, log) only reward reporting your true probability --> the formal basis for 'abstain when unsure' and 'don't fake a number'

### Category 6: AI Card-Generation Safety & Assessment Validity

#### Subcategory 6.1: Multiple-Choice Item Validity

**Source:** Haladyna, T. M., Downing, S. M., & Rodriguez, M. C. (2002). A review of multiple-choice item-writing guidelines for classroom assessment. _Applied Measurement in Education_, 15(3), 309-334.

- **DOK 1 - Facts:**
  - A validated taxonomy of **31 MC item-writing guidelines** (drawn from 27 textbooks + 27 empirical studies).
  - Key rules: put the **central idea in the stem** (the only unanimously endorsed guideline), **~3 good options** is enough, and build **plausible distractors from typical student errors**.
- **Link:** https://doi.org/10.1207/s15324818ame1503_5

- ! **DOK 2 - Summary:** there's a validated set of 31 rules for writing sound multiple-choice items (central idea in the stem, plausible distractors built from real student errors, ~3 good options is enough) --> the quality bar any AI-generated card has to clear

---

#### Subcategory 6.2: Automatic Item Generation (AIG)

**Source:** Gierl, M. J., Lai, H., & Turner, S. R. (2012). Using automatic item generation to create multiple-choice test items. _Medical Education_, 46(8), 757-765.

- **DOK 1 - Facts:**
  - A 3-stage pipeline generated **1,248 unique MC items from one human-built "cognitive model"** - humans own correctness, the machine only varies surface content.
  - Hand-writing high-stakes items runs **~$1,500-2,000 each** (a 2,000-item bank ≈ $3-4M), so AIG's value is scaling variation, not sourcing truth.
- **Link:** https://doi.org/10.1111/j.1365-2923.2012.04289.x

- ! **DOK 2 - Summary:** automatic item generation spins many items from one human-built 'cognitive model' (1,248 from a single model); humans own correctness, the machine only varies surface; hand-writing items is expensive (~$1.5-2k each) --> AI's value is scaling variation, not sourcing truth

---

#### Subcategory 6.3: LLM Hallucination & Prompt Injection Risk

**Source:** Ji, Z., Lee, N., Frieske, R., Yu, T., Su, D., Xu, Y., Ishii, E., Bang, Y., Chen, D., Chan, H. S., Dai, W., Madotto, A., & Fung, P. (2023). Survey of hallucination in natural language generation. _ACM Computing Surveys_, 55(12), Article 248, 1-38.

- **DOK 1 - Facts:**
  - Two hallucination types: **intrinsic** (output contradicts the source) and **extrinsic** (can't be verified against the source) - both poison in an answer key.
  - LLMs can also **memorize and regurgitate** training data (Carlini et al.) - a leakage risk.
- **Link:** https://doi.org/10.1145/3571730

**Source:** OWASP GenAI Security Project. (2025). _OWASP Top 10 for Large Language Model Applications v2025_ - LLM01:2025 Prompt Injection.

- **DOK 1 - Facts:**
  - **Prompt injection is the #1 LLM risk** (OWASP LLM01:2025), including **indirect** injection - hidden instructions buried in documents the model reads.
  - RAG and fine-tuning **do not fully mitigate** it, and "fool-proof prevention methods remain unclear."
- **Link:** https://genai.owasp.org/llmrisk/llm01-prompt-injection/

- ! **DOK 2 - Summary:** LLMs hallucinate (intrinsic = contradicts the source; extrinsic = unverifiable), which is poison in an answer key; prompt injection - especially indirect, hidden inside documents the model reads - is the #1 LLM risk with no fool-proof fix --> RAG-ing over FASB/IRC text is an attack surface, not a safe input

### Category 7: CPA Exam Structure & Scoring

---

#### Subcategory 7.1: Exam Architecture - CPA Evolution Format

**Source:** AICPA (2026). _Uniform CPA Examination Blueprints (effective January 1, 2026)._ Association of International Certified Professional Accountants.

- **DOK 1 - Facts:**
  - CPA Evolution (Jan 2024): **3 Core (AUD/FAR/REG) + 1 chosen Discipline (BAR/ISC/TCP)**, each a **4-hour, 5-testlet** exam (testlets 1-2 MCQ, 3-5 TBS); BEC retired Dec 2023.
  - MCQ/TBS score weight is **50/50** (ISC 60/40); research TBSs use embedded authoritative literature (FASB ASC / IRC / PCAOB & AICPA standards).
- **Link:** https://www.aicpa-cima.com/resources/article/learn-what-is-tested-on-the-cpa-exam

**Source:** AICPA (2023). _Infrastructure Changes to the CPA Exam in 2024._ Association of International Certified Professional Accountants. (Distributed via state CPA societies.)

- **DOK 1 - Facts:**
  - As of Jan 2024, MCQ testlets are **linear (non-adaptive)** - the old two-stage adaptive MST (2004-2023) and the written-communication essay were both removed. ⚠ Many review-course guides still wrongly describe adaptive MCQs.
- **Link:** https://www.ficpa.org/publication/aicpa-announces-2024-infrastructure-changes-cpa-exam

- ! **DOK 2 - Summary:** post-2024 'CPA Evolution' = 3 core sections (AUD/FAR/REG) + 1 chosen discipline (BAR/ISC/TCP), each a 4-hour exam of 5 testlets (2 MCQ then 3 TBS), ~50/50 MCQ/TBS weight (ISC 60/40); MCQs are now LINEAR (adaptive MST killed Jan 2024) and essays are gone --> the format a performance model has to mirror

---

#### Subcategory 7.2: Scoring Mechanics & Section Pass Rates

**Source:** AICPA (2026). _Learn more about CPA Exam scoring and pass rates_ (updated April 20, 2026). AICPA & CIMA.

- **DOK 1 - Facts:**
  - Passing is a **scaled 75 on a 0-99 IRT scale** (not 75% correct) and is not curved.
  - 2025 pass rates ran from **~42% (FAR and BAR, the hardest)** up to **~78% (TCP, the easiest)** - base rates differ sharply by section.
- **Link:** https://www.aicpa-cima.com/resources/article/learn-more-about-cpa-exam-scoring-and-pass-rates

- ! **DOK 2 - Summary:** passing is a scaled 75 on a 0-99 scale (NOT 75% correct), computed via IRT and not curved; 2025 section pass rates run from FAR ~42% (hardest) to TCP ~78% (easiest) --> the real scale readiness projects onto, with base rates that differ a lot by section

---

#### Subcategory 7.3: Credit Window & Licensing Logistics

**Source:** NASBA (2023). _NASBA Announces Historic Rule Amendment Following Record Exposure Draft Response_ (April 24, 2023). National Association of State Boards of Accountancy.

- **DOK 1 - Facts:**
  - NASBA extended the credit window to a rolling **30 months** (up from 18) to pass all 4 sections, starting when the **first passing score is released**.
  - ⚠ It's a **model rule** each of the 55 jurisdictions must adopt on its own - verify locally.
- **Link:** https://nasba.org/blog/2023/04/24/nasba-announces-historic-exam-rule-amendment/

- ! **DOK 2 - Summary:** candidates now get a rolling 30-month window (up from 18) to pass all 4 sections, starting when the first passing score is released - but it's a NASBA model rule each state adopts on its own --> a real deadline to study toward, but jurisdiction-dependent

### Category 8: CPA Market & Competitive Landscape

---

#### Subcategory 8.1: Candidate Volume & Pipeline Trend

**Source:** NASBA (Nov. 2024; Aug. 2025). "2020-2023 CPA Exam Statistics Now Available" and "2024 NASBA Report Released." NASBA.org press releases; data drawn from _The NASBA Report: Candidate Performance on the Uniform CPA Examination_, 2023 and 2024 Editions.

- **DOK 1 - Facts:**
  - Unique candidates fell from **84,980 (2023) to 74,165 (2024)** - down **12.7%**, with new candidates down **32.4%** and final-section completers down **34.8%**.
- **Link:** https://nasba.org/blog/2024/11/27/2020-2023-cpa-exam-statistics-now-available/ ; https://nasba.org/blog/2025/08/18/explore-the-numbers-behind-cpa-exam-success-2024-nasba-report-released/

**Source:** AICPA & CIMA (June 2, 2025). "Accounting Enrollment Increased 12% for Spring Semester." AICPA-CIMA.com; underlying data from the National Student Clearinghouse Research Center.

- **DOK 1 - Facts:**
  - But undergrad accounting **enrollment rose +12%** in spring 2025 (to 266,507) - a third straight semester of growth, hinting at a turnaround.
- **Link:** https://www.aicpa-cima.com/news/article/accounting-enrollment-increased-12-for-spring-semester

- ! **DOK 2 - Summary:** CPA volume is shrinking (~85k candidates in 2023 --> ~74k in 2024, -12.7%, new candidates -32%) but may be turning around (accounting enrollment +12% in spring 2025) --> a contracting-but-maybe-recovering market

---

#### Subcategory 8.2: Market Size

**Source:** Verified Market Reports (2026). "Global CPA Exam Reviews Market Size, Share, Trends & Industry Forecast 2026-2034." VerifiedMarketReports.com.

- **DOK 1 - Facts:**
  - ⚠ Vendor market-size estimates diverge nearly **7×** (~$285M to ~$1.95B), and one report even contradicts itself (global $1.2B in 2025 vs. North America alone $2.5B in 2024).
  - No independently audited revenue figure for CPA review exists publicly.
- **Link:** https://www.verifiedmarketreports.com/product/cpa-exam-reviews-market/

- ! **DOK 2 - Summary:** the CPA-review market is real but un-auditable: vendor size estimates span ~7x ($285M to $1.95B) and one report even contradicts itself --> treat every market-size figure as a rough guess, not a fact

---

#### Subcategory 8.3: Market Concentration & Section Failure Rate

**Source:** AICPA Board of Examiners (Apr. 2024 and subsequent quarters). "24Q1 CPA Exam Pass Rates" and later quarterly releases. AICPA-CIMA.com; full-year 2024 figures aggregated from AICPA quarterly releases by UWorld CPA Review (accounting.uworld.com/cpa-review/cpa-exam/pass-rates/).

- **DOK 1 - Facts:**
  - 2024 section pass rates ran from **BAR 38.1% / FAR 39.6%** (lowest) up to **TCP 73.9%** (highest) - roughly **60% fail** BAR and FAR.
- **Link:** https://www.aicpa-cima.com/certifications/article/24q1-cpa-exam-pass-rates ; https://accounting.uworld.com/cpa-review/cpa-exam/pass-rates/

**Source:** Journal of Accountancy (March 2012). "In memoriam: Newton Becker." JournalOfAccountancy.com.

- **DOK 1 - Facts:**
  - Becker is deeply entrenched - allegedly **~half of US CPAs** used it (400k+ passers by 2012). ⚠ Unverified.
  - ⚠ Claims that Becker + UWorld + NINJA hold **"90%+ of the U.S. market"** have no audited source.
- **Link:** https://www.journalofaccountancy.com/issues/2012/mar/becker/

- ! **DOK 2 - Summary:** becker is entrenched (allegedly ~half of US CPAs used it, though unverified) and ~50% of section attempts fail (BAR/FAR worst) --> a big, motivated retaker pool, and incumbent market-share claims you can't take at face value

---

#### Subcategory 8.4: Section-Attempt Volume & Entry Economics

**Source:** Derived from NASBA candidate counts (Subcat 8.1) + the CPA market analysis (internal deep-research synthesis). ⚠ Derived figures and market estimates, not single audited statistics.

- **DOK 1 - Facts:**
  - ~**148,000 section attempts** in 2024, of which roughly **70,000-80,000 fail per year** - the addressable retaker pool. ⚠ Derived.
  - Building a full institutional competitor is estimated at **~$10-20M and 3-5 years**. ⚠ Estimate, not audited.
- **Link:** https://nasba.org/blog/2025/08/18/explore-the-numbers-behind-cpa-exam-success-2024-nasba-report-released/

- ! **DOK 2 - Summary:** ~70-80k failed section attempts a year --> the retaker pool, and a full head-on competitor to Becker and other B2B companies is ~$10-20M / 3-5yr --> attack retakers, not Becker's B2B channel (grounds SPOV 1)

## References

### Memory & Spaced Repetition

1. Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer, D. (2006). Distributed practice in verbal recall tasks: A review and quantitative synthesis. _Psychological Bulletin, 132_(3), 354-380.\
   https://doi.org/10.1037/0033-2909.132.3.354
2. Roediger, H. L., III, & Karpicke, J. D. (2006). Test-enhanced learning: Taking memory tests improves long-term retention. _Psychological Science, 17_(3), 249-255.\
   https://doi.org/10.1111/j.1467-9280.2006.01693.x
3. Woźniak, P. A. (1990). _Optimization of learning_ (Master's thesis, University of Technology in Poznan). [SM-2 algorithm; archived at supermemo.guru / supermemo.com]\
   https://www-beta.supermemo.com/archives1990-2015/english/ol/sm2
4. Ye, J., Su, J., & Cao, Y. (2022). A stochastic shortest path algorithm for optimizing spaced repetition scheduling. In _Proceedings of the 28th ACM SIGKDD Conference on Knowledge Discovery and Data Mining_ (KDD '22), pp. 4381-4390. ACM. [FSRS foundational paper + Anki 23.10 integration]\
   https://doi.org/10.1145/3534678.3539081 (paper); https://github.com/ankitects/anki/releases/tag/23.10 (Anki 23.10 release notes); https://docs.ankiweb.net/deck-options.html (Anki manual - FSRS section)

### Transfer of Learning & Desirable Difficulties

1. Chi, M. T. H., Feltovich, P. J., & Glaser, R. (1981). Categorization and representation of physics problems by experts and novices. _Cognitive Science_, 5(2), 121-152.\
   https://doi.org/10.1207/s15516709cog0502_2
2. Gick, M. L., & Holyoak, K. J. (1983). Schema induction and analogical transfer. _Cognitive Psychology_, 15(1), 1-38.\
   https://doi.org/10.1016/0010-0285(83)90002-6
3. Rohrer, D., & Taylor, K. (2007). The shuffling of mathematics problems improves learning. _Instructional Science_, 35(6), 481-498.\
   https://doi.org/10.1007/s11251-007-9015-8
4. Rohrer, D., Dedrick, R. F., & Stershic, S. (2015). Interleaved practice improves mathematics learning. _Journal of Educational Psychology_, 107(3), 900-908.\
   https://doi.org/10.1037/edu0000001

### Cognitive Load, Feedback & Study-Feature Design

1. Sweller, J., van Merriënboer, J. J. G., & Paas, F. (2019). Cognitive Architecture and Instructional Design: 20 Years Later. _Educational Psychology Review_, 31(2), 261-292.\
   https://doi.org/10.1007/s10648-019-09465-5
2. Kluger, A. N., & DeNisi, A. (1996). The effects of feedback interventions on performance: A historical review, a meta-analysis, and a preliminary feedback intervention theory. _Psychological Bulletin_, 119(2), 254-284.\
   https://doi.org/10.1037/0033-2909.119.2.254
3. Hattie, J., & Timperley, H. (2007). The power of feedback. _Review of Educational Research_, 77(1), 81-112.\
   https://doi.org/10.3102/003465430298487

### Metacognition & Calibration

1. Kruger, J., & Dunning, D. (1999). Unskilled and unaware of it: How difficulties in recognizing one's own incompetence lead to inflated self-assessments. _Journal of Personality and Social Psychology_, 77(6), 1121-1134.\
   https://doi.org/10.1037/0022-3514.77.6.1121
2. Koriat, A., & Bjork, R. A. (2005). Illusions of competence in monitoring one's knowledge during study. _Journal of Experimental Psychology: Learning, Memory, and Cognition_, 31(2), 187-194.\
   https://doi.org/10.1037/0278-7393.31.2.187
3. Kornell, N., & Bjork, R. A. (2008). Learning concepts and categories: Is spacing the "enemy of induction"? _Psychological Science_, 19(6), 585-592.\
   https://doi.org/10.1111/j.1467-9280.2008.02127.x
4. Murphy, A. H. (1973). A new vector partition of the probability score. _Journal of Applied Meteorology_, 12(4), 595-600.\
   https://journals.ametsoc.org/view/journals/apme/12/4/1520-0450_1973_012_0595_anvpot_2_0_co_2.xml

### Psychometrics & Score Prediction

1. Embretson, S. E., & Reise, S. P. (2000). _Item Response Theory for Psychologists_. Lawrence Erlbaum Associates.\
   https://doi.org/10.4324/9781410605269
2. van der Linden, W. J., & Glas, C. A. W. (Eds.). (2010). _Elements of Adaptive Testing_. Springer.\
   https://link.springer.com/book/10.1007/978-0-387-85461-8
3. El-Yaniv, R., & Wiener, Y. (2010). On the foundations of noise-free selective classification. _Journal of Machine Learning Research_, 11, 1605-1641.\
   https://www.jmlr.org/papers/v11/el-yaniv10a.html
4. Gneiting, T., & Raftery, A. E. (2007). Strictly proper scoring rules, prediction, and estimation. _Journal of the American Statistical Association_, 102(477). DOI: 10.1198/016214506000001437.\
   https://doi.org/10.1198/016214506000001437

### AI Card-Generation Safety & Assessment Validity

1. Haladyna, T. M., Downing, S. M., & Rodriguez, M. C. (2002). A review of multiple-choice item-writing guidelines for classroom assessment. _Applied Measurement in Education_, 15(3), 309-334.\
   https://doi.org/10.1207/s15324818ame1503_5
2. Gierl, M. J., Lai, H., & Turner, S. R. (2012). Using automatic item generation to create multiple-choice test items. _Medical Education_, 46(8), 757-765.\
   https://doi.org/10.1111/j.1365-2923.2012.04289.x
3. Ji, Z., Lee, N., Frieske, R., Yu, T., Su, D., Xu, Y., Ishii, E., Bang, Y., Chen, D., Chan, H. S., Dai, W., Madotto, A., & Fung, P. (2023). Survey of hallucination in natural language generation. _ACM Computing Surveys_, 55(12), Article 248, 1-38.\
   https://doi.org/10.1145/3571730
4. OWASP GenAI Security Project. (2025). _OWASP Top 10 for Large Language Model Applications v2025_ - LLM01:2025 Prompt Injection.\
   https://genai.owasp.org/llmrisk/llm01-prompt-injection/

### CPA Exam Structure & Scoring

1. AICPA (2026). _Uniform CPA Examination Blueprints (effective January 1, 2026)._ Association of International Certified Professional Accountants.\
   https://www.aicpa-cima.com/resources/article/learn-what-is-tested-on-the-cpa-exam
2. AICPA (2023). _Infrastructure Changes to the CPA Exam in 2024._ Association of International Certified Professional Accountants. (Distributed via state CPA societies.)\
   https://www.ficpa.org/publication/aicpa-announces-2024-infrastructure-changes-cpa-exam
3. AICPA (2026). _Learn more about CPA Exam scoring and pass rates_ (updated April 20, 2026). AICPA & CIMA.\
   https://www.aicpa-cima.com/resources/article/learn-more-about-cpa-exam-scoring-and-pass-rates
4. NASBA (2023). _NASBA Announces Historic Rule Amendment Following Record Exposure Draft Response_ (April 24, 2023). National Association of State Boards of Accountancy.\
   https://nasba.org/blog/2023/04/24/nasba-announces-historic-exam-rule-amendment/

### CPA Market & Competitive Landscape

1. NASBA (Nov. 2024; Aug. 2025). "2020-2023 CPA Exam Statistics Now Available" and "2024 NASBA Report Released." NASBA.org press releases; data drawn from _The NASBA Report: Candidate Performance on the Uniform CPA Examination_, 2023 and 2024 Editions.\
   https://nasba.org/blog/2024/11/27/2020-2023-cpa-exam-statistics-now-available/ ; https://nasba.org/blog/2025/08/18/explore-the-numbers-behind-cpa-exam-success-2024-nasba-report-released/
2. AICPA & CIMA (June 2, 2025). "Accounting Enrollment Increased 12% for Spring Semester." AICPA-CIMA.com; underlying data from the National Student Clearinghouse Research Center.\
   https://www.aicpa-cima.com/news/article/accounting-enrollment-increased-12-for-spring-semester
3. Verified Market Reports (2026). "Global CPA Exam Reviews Market Size, Share, Trends & Industry Forecast 2026-2034." VerifiedMarketReports.com.\
   https://www.verifiedmarketreports.com/product/cpa-exam-reviews-market/
4. AICPA Board of Examiners (Apr. 2024 and subsequent quarters). "24Q1 CPA Exam Pass Rates" and later quarterly releases. AICPA-CIMA.com; full-year 2024 figures aggregated from AICPA quarterly releases by UWorld CPA Review (accounting.uworld.com/cpa-review/cpa-exam/pass-rates/).\
   https://www.aicpa-cima.com/certifications/article/24q1-cpa-exam-pass-rates ; https://accounting.uworld.com/cpa-review/cpa-exam/pass-rates/
5. Journal of Accountancy (March 2012). "In memoriam: Newton Becker." JournalOfAccountancy.com.\
   https://www.journalofaccountancy.com/issues/2012/mar/becker/
6. Anki project (ankitects). LICENSE file, ankitects/anki repository, GitHub; Anki FAQs (faqs.ankiweb.net); GNU Affero General Public License v3.0 full text (gnu.org/licenses/agpl-3.0.en.html); VS Code (Code - OSS) LICENSE.txt, microsoft/vscode repository, GitHub.
   https://github.com/ankitects/anki/blob/HEAD/LICENSE ; https://faqs.ankiweb.net/can-i-use-anki-in-a-company-or-school.html ; https://www.gnu.org/licenses/agpl-3.0.en.html ; https://github.com/microsoft/vscode/blob/main/LICENSE.txt
7. NASBA Candidate Performance reports (2023-2024) + CPA market analysis (internal deep-research synthesis). Basis for the ~148k section-attempt volume, the ~70,000-80,000 failed-attempts/year retaker pool, and the ~$10-20M / 3-5-year full-competitor estimate; derived/estimated, not audited.\
   https://nasba.org/blog/2025/08/18/explore-the-numbers-behind-cpa-exam-success-2024-nasba-report-released/
