## Purpose

To establish a research-backed, first-principles foundation for **Ankountant** - an Anki-forked desktop + mobile study app for the accounting **CPA exam**. Helping CPA candidates pass the exam will require the app to keep the following in mind:

- **Memory** - can the student *recall* a taught fact? (Anki's FSRS handles raw recall well, but it optimizes open-ended retention rather than peaking on a fixed exam date; the scheduler needs reworking for that - see the deadline-scheduling SPOV.)
- **Performance** - can the student answer a *new, exam-style* question that uses that fact, including ones never seen? (the memory → transfer bridge.)
- **Readiness** - what would the student *score today*, expressed as a *range with a confidence level*, abstaining when evidence is insufficient? (the performance → score bridge.)

This brainlift grounds product design in cognitive/learning science rather than basic assumptions. 

> *NOTE:* AI was used to find the list of EXperts, DOK1s, sources, and brainstormed the "Features to Build in the Anki Fork" section based off of the DOK4s. 

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
- ! **SPOV 1:** Anki rewards comfortable, high-frequency review - not effortful retrieval that actually builds durable memory -> Ankountant weights gates every review with answer + confidence before the reveal and uses answer latency to flag easy cards and push their intervals out hard.
  - **Elaboration:** Anki and FSRS reward streaks and raw review count and target ~90% success, so most reps are easy by design - but effortful retrieval, not comfortable review, is what builds durable memory. Roediger & Karpicke (2006) found repeated testing beat repeated study 61% to 40% on a one-week delayed test (d = 1.26), and the restudy group both forgot far more (52% vs 14%) and grew *more* confident while doing worse. Kornell & Bjork (2008) showed learners keep preferring the easier (massed) condition even after seeing the harder one work better. So Ankountant should capture an answer and a confidence *before* the reveal, reward effortful reps over volume, and use answer latency (a signal Anki records but ignores) to detect a too-easy card and either push its interval out hard or swap in a harder transfer probe. Crucially, difficulty is *time-relative*: effortful retrieval is the regime far from the exam, when there is runway to struggle and recover; in the final stretch the scheduler shifts toward consolidation, raising the retention target so material reliably peaks on exam day. The single dial is days-to-exam (see SPOV 3). Boundary: you cannot withhold the answer for material never taught (worked-example effect), so "defund easy" only fires once an item is genuinely stable.
- ! **SPOV 2:** FSRS has no concept of an exam date - it targets open-ended retention with no finish line -> Ankountant introduces a deadline-anchored scheduler that computes intervals backward from the exam date so recall peaks on the day that counts
  - **Elaboration:** FSRS was trained to minimize lifelong review cost at a fixed ~90% retention target (Ye et al., 2022, on 220M MaiMemo logs) and has no concept of a deadline - its retention knob is even global, not per-deck. But a CPA section is one four-hour sitting on a candidate-chosen date inside a 30-month window, so the goal is maximum recall *on that day*, not indefinite maintenance. Cepeda et al. (2006) established that the optimal inter-study gap grows with the target retention interval (the spacing advantage was largest at 8-30 days, 62% vs 33%), which means the right gap is a function of days-to-exam - exactly the variable FSRS never sees. And because passing is a threshold (75), not a maximum, there is no payoff for driving a known card from 90% to 95%; those minutes should be reclaimed for weak topics. Ankountant therefore needs a deadline-anchored scheduler: exam date as a first-class object, intervals computed backward from it, desired retention ramping up as the date nears, and recall projected for exam day rather than today. This is the core change to Anki's Rust engine, and it unifies with SPOV 2: effort weighted early, consolidation late, dialed by days-to-exam. Boundary: early Core knowledge resurfaces later (FAR concepts reappear in BAR), so only section-idiosyncratic, low-reuse items should be allowed to decay, and the scheduler falls back to an open-horizon default when no date is set.
- ! **SPOV 3:** Topic decks hand the candidate the category before they answer - training the surface-feature habit that kills candidates on FAR and BAR (the FAR and BAR are CPA test categories) -> Ankountant replaces the deck with the *confusion set* as its core primitive and scores discrimination ("which standard applies?") instead of rote recall.
  - **Elaboration:** A topic-named deck hands the student the category for free - open the "Leases" deck and you already know it is a lease question - which rehearses exactly the wrong habit. Chi, Feltovich & Glaser (1981) found all 8 novices sorted problems by surface features while 6 of 8 experts sorted by the deep principle; a plain flashcard trains the novice move. Rohrer & Taylor (2007) found interleaved practice beat blocked 63% to 20% on a one-week test, and the blockers' errors were choosing the *wrong* procedure, not mis-executing it - discrimination is trained only when confusable items are mixed (Rohrer et al., 2015 showed it persists at 30 days, 74% vs 42%). This bites hardest where the CPA is hardest: FAR and BAR have the lowest pass rates (~42%) and are precisely the "which standard applies" sections. So Ankountant should make the confusion set its core practice primitive - a curated map of classic CPA traps (capitalize vs expense, operating vs finance lease, the revenue-recognition steps), a label-stripped "which treatment?" gate before any computation, and mastery scored on cross-item discrimination - while topic decks are demoted to a reference glossary. Boundary: rank beginners need a brief blocked introduction first (expertise reversal), and only genuinely confusable categories should be interleaved.
- ! **SPOV 4:** Scoring readiness on items the student already drilled is just measuring recall again -> Ankountant firewalls a sealed, never-studied item bank per topic and reports Readiness as a calibrated score range that abstains when evidence is too thin to trust.
  - **Elaboration:** Scoring "performance" on items built from the same source the student studied is just measuring recall again. Gick & Holyoak (1983) showed transfer requires novel surface (spontaneous transfer was only ~30% even when the analog had been seen), and language models regurgitate their training data (Ji et al., 2023), so a generator that wrote the study cards will leak them into supposedly novel tests unless the pipelines are firewalled. Ankountant therefore keeps two pools per topic: study cards revised normally (the Memory pillar - no topic goes unstudied) and a separate *sealed* bank of same-topic, new-surface items that are never shown for study and exist only to measure. The memory-to-performance gap (recall on the study pile vs accuracy on the sealed pile) is the honest transfer signal; a large gap is the operational form of "feels ready, isn't." Readiness is then a projected score on the real 0-99 scale, expressed as a *range with a confidence level*, computed only on the firewalled items, and it *abstains* (the give-up rule) when held-out coverage or volume is too thin - a confident number with nothing behind it is not a prediction. Boundary: new-surface-same-method items are still *near* transfer, a single item is noise (several, difficulty-equated, are needed), and the sealed bank must pass a leakage check against the study cards to stay honest.
- ! **SPOV 5:** TBSs (non MCQs, multistep quesdtions) are roughly half of every section's score, but the flashcard loop structurally cannot represent them - every incumbent just bolts a TBS bank onto a flashcard app -> Ankountant makes TBS a first-class, step-graded review mode with partial credit per step that feeds one honest Performance score on a separate data path.
  - **Elaboration:** TBSs are roughly half of every section's score (three of the five testlets; weighted 50/50, or 60/40 MCQ/TBS for ISC) and they are multi-step *application* tasks, so the flashcard primitive (one recall, one self-graded button) structurally cannot represent them. Ankountant should treat review as three distinct modes, only one of which is a flashcard: recall flashcards (Memory/FSRS) for atomic facts, confusion-set discrimination (the Performance MCQ mode of SPOV 4), and a dedicated TBS task surface. Each TBS type is handled on its own terms: research simulations as a navigation drill against the embedded FASB Codification / IRC / PCAOB literature (find and cite, scored on correctness and time), journal-entry and numeric simulations as procedural tasks graded line-by-line with partial credit, and document-review simulations as a set of "which treatment?" sub-decisions reusing the confusion-set logic. Grading is step-level (method vs slip) rather than one binary lapse - the right fix for Anki's "fail resets the interval" model - and TBS attempts feed Performance and Readiness on a separate data path from flashcard recall, which keeps the sealed-bank firewall clean. This is where differentiation is sharpest: every incumbent and every Anki-based CPA deck bolts a TBS bank onto a flashcard app, whereas making TBS a first-class, step-graded review mode that feeds one honest Performance number is the actual product.
- ! **SPOV 6:** Becker's (Biggest CPA test prep comp.) dominance is B2B lock-in, not product superiority - attacking that channel head-on is a $10-20M dead end -> Ankountant enters B2C as the honest diagnosis tool for the ~70-80k annual retakers who already failed with an incumbent, then layers a readiness-and-analytics offer onto firms after scale.
  - **Elaboration:** Becker's dominance is a B2B lock-in, not a product advantage: firms hand each new hire a paid Becker license, so the candidate never makes the purchase decision and only shops for an alternative once they have already failed. Attacking that channel head-on is a capital and time sink (a full institutional competitor is estimated near $10-20M and 3-5 years, sold to risk-averse L&D buyers on multi-year cycles). The accessible opening is B2C, aimed first at the people who choose for themselves: the roughly half of section attempts that fail each year (about 70,000-80,000 failed attempts), where incumbents are structurally *disadvantaged* because the candidate already used them and still failed; plus the self-funded international and career-changer cohorts outside the employer-sponsorship system. These buyers do not need another full course, they need an honest diagnosis of what to fix, which is exactly what Ankountant's three scores (Memory, Performance, Readiness) deliver. The move to B2B comes *after* scale, not instead of it: once the product has real outcome and calibration data plus brand trust from B2C users, the defensible enterprise offer is the readiness/analytics layer sold to firms on top of their existing Becker contracts, rather than a rival course fighting for the standard-course slot. (Market-size and market-share figures here are vendor estimates, so treat them as directional, not audited.)

## Experts

- **Henry L. Roediger III** - Retrieval-practice researcher (WashU); his work that active recall-not re-study-drives long-term retention is the core warrant for Ankountant's Memory-pillar scheduling logic.
- **Jeffrey D. Karpicke** - Learning scientist (Purdue); landmark 2008 *Science* paper showing repeated retrieval outperforms repeated review is the empirical backbone of the testing-effect pillar.
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
- Capturing confidence *before* the reveal (rather than self-rating after seeing the answer) is what makes that gap measurable in the first place.

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

**Source:** Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer, D. (2006). Distributed practice in verbal recall tasks: A review and quantitative synthesis. *Psychological Bulletin, 132*(3), 354-380.
- **DOK 1 - Facts:**
  - Meta-analysis identified **839 assessments** of distributed practice drawn from **317 experiments** in **184 articles**; all studies used verbal recall tasks (paired associates, list recall, paragraph recall, etc.) with recall - not recognition - as the performance measure. (Note: Ebbinghaus, 1885/1964, is cited in the introduction as the historical origin of the distributed-practice literature.)
  - Of **271 massed-vs.-spaced comparisons**, only **12** showed no effect or a negative effect for spacing; **259 comparisons (≈95.6%)** favored spaced over massed presentations.
  - Across all retention intervals combined, mean final-test accuracy was **47.3% (spaced)** vs. **36.7% (massed)**; *t*(540) = 6.6, *p* < .001.
  - For retention intervals of **8-30 days**, the advantage was largest: spaced = **62.2%** vs. massed = **32.8%** correct.
  - Key joint finding: the interstudy interval (ISI) producing maximal retention **increased as the target retention interval increased** - longer desired retention requires proportionally wider spacing gaps. The optimal ISI is non-linear with respect to the retention goal; no single fixed gap is universally optimal.
- **Link:** https://doi.org/10.1037/0033-2909.132.3.354

- ! **DOK 2 - Summary:** spacing study sessions out beats cramming for durable recall (~47% vs ~37% overall, 62% vs 33% at 8-30 days); the longer you need to retain something, the wider the gaps should be --> no single fixed interval is optimal

---

#### Subcategory 1.2: Retrieval Practice (Testing) Effect

**Source:** Roediger, H. L., III, & Karpicke, J. D. (2006). Test-enhanced learning: Taking memory tests improves long-term retention. *Psychological Science, 17*(3), 249-255.
- **DOK 1 - Facts:**
  - Two experiments; students studied prose passages and were assigned to one of three conditions: four study periods (SSSS), three study + one test (SSST), or one study + three tests (STTT); final recall tested at 5 min, 2 days, or 1 week.
  - At the **5-min** final test, repeated study outperformed repeated testing: SSSS = **83%** vs. STTT = **71%** correct - an immediate performance advantage for studying.
  - At the **1-week** final test, the pattern fully reversed: STTT = **61%** vs. SSSS = **40%** correct - a **21 percentage-point** advantage for the testing condition; Cohen's *d* = 1.26 for the STTT vs. SSSS comparison.
  - Proportional forgetting from initial recall to the 1-week final test: SSSS group forgot **52%** of material; STTT group forgot only **14%**.
  - Despite lower delayed retention, repeated studying **increased students' expressed confidence** in their ability to remember the material - a metacognitive inversion: students predicted the wrong condition would win on the delayed test.
- **DOK 2 - Summary:** long-term memory/recall is boosted by more testing blocks compared to study; pure studying creates the dunning-kruger effect --> increased self-perceived confidence
- **Link:** https://doi.org/10.1111/j.1467-9280.2006.01693.x

---

#### Subcategory 1.3: SR Algorithm Lineage - SM-2 → FSRS

**Source:** Woźniak, P. A. (1990). *Optimization of learning* (Master's thesis, University of Technology in Poznan). [SM-2 algorithm; archived at supermemo.guru / supermemo.com]
- **DOK 1 - Facts:**
  - SM-2 was the **first computer algorithm** for computing optimum review schedules in spaced repetition; first implemented in **SuperMemo 1.0 for DOS on December 13, 1987**. Named "SM-2" after SuperMemo 2.0 (released as freeware in 1991); there was never an "SM-1."
  - SM-2 assigns each item a per-item **ease factor (E-Factor)** updated via a **0-5 quality-of-response rating** after each review; initial intervals are **1 day** and **6 days**, growing multiplicatively by the E-Factor on each subsequent review.
  - During Woźniak's first year using SM-2 to learn English vocabulary (1987-1988): **10,255 items memorized** at an average of **41 minutes/day**, achieving overall retention of **89.3%** (92% when excluding items with intervals below 3 weeks).
  - Anki's scheduling algorithm was based on SM-2 from its inception and remained so until FSRS support was added in Anki 23.10 (2023). 
- **Link:** https://www-beta.supermemo.com/archives1990-2015/english/ol/sm2

**Source:** Ye, J., Su, J., & Cao, Y. (2022). A stochastic shortest path algorithm for optimizing spaced repetition scheduling. In *Proceedings of the 28th ACM SIGKDD Conference on Knowledge Discovery and Data Mining* (KDD '22), pp. 4381-4390. ACM. [FSRS foundational paper + Anki 23.10 integration]
- **DOK 1 - Facts:**
  - Ye et al. trained a Markov-property memory model on **220 million students' memory behavior logs** collected from the MaiMemo language-learning app; the scheduler was designed to minimize total review cost.
  - The resulting scheduler achieved a **12.6% performance improvement** over state-of-the-art methods in the paper's benchmarks; deployed to production in MaiMemo "to help millions of students."
  - FSRS (Free Spaced Repetition Scheduler) was **natively integrated into Anki starting with version 23.10**, released **October 31, 2023** (GitHub release tag 23.10); prior to that version, FSRS required a custom-scheduling add-on.
  - FSRS is an **opt-in alternative** to SM-2 in Anki; per Anki's official manual (as of June 2026): "When you turn on FSRS, some new options become available, and SM-2 specific options, such as Graduating interval, Easy bonus, etc. are hidden. This option is shared by all presets." FSRS can only be enabled globally; it cannot be enabled for individual deck presets.
  - FSRS's default desired-retention target is **90%**; the manual notes that "above 97% the workload can be overwhelming" and that workload increases non-linearly with retention target above the default.
- **Link:** https://doi.org/10.1145/3534678.3539081 (paper); https://github.com/ankitects/anki/releases/tag/23.10 (Anki 23.10 release notes); https://docs.ankiweb.net/deck-options.html (Anki manual - FSRS section)

- ! **DOK 2 - Summary:** SM-2 (1987) is the original spaced-repetition scheduler anki was built on; FSRS is the modern ML-trained successor (220M review logs, ~12.6% better) anki now ships opt-in at a default 90% target retention --> SR has moved from hand-tuned heuristics to data-trained scheduling

### Category 2: Transfer of Learning & Desirable Difficulties

---

#### Subcategory 2.1: Expert-Novice Problem Categorization

**Source:** Chi, M. T. H., Feltovich, P. J., & Glaser, R. (1981). Categorization and representation of physics problems by experts and novices. *Cognitive Science*, 5(2), 121-152.
- **DOK 1 - Facts:**
  - 8 advanced PhD physics students (experts) and 8 undergraduates who had completed an introductory mechanics course (novices) each sorted 24 problems drawn from Halliday and Resnick's introductory mechanics textbook "based on similarities in how they would be solved"; conducted across 4 experiments using sorting tasks and verbal protocols.
  - All 8 novices grouped surface-feature problems together (e.g., "blocks on incline [inclined plane]," "rotational things [rotation]"); 6 of 8 experts grouped the same problems by underlying physics principle instead.
  - Expert sorts clustered around deep physics principles: Law of Conservation of Energy, Newton's Second Law (F = MA); novice sorts clustered around literal surface features (inclined plane, spring, rotation, pulley).
  - Expert verbal protocols immediately named the applicable physics principle and the conditions under which it applies; novice protocols focused on surface objects and keywords, rarely mentioning physics principles-and when mentioned, did not link them to solution procedures.
  - Direct quote from paper: "If 'deep structure' is defined as the underlying physics law applicable to a problem; then, clearly, this deep structure is the basis by which experts group the problems."
- **Link:** https://doi.org/10.1207/s15516709cog0502_2

- ! **DOK 2 - Summary:** experts sort problems by deep structure (the underlying principle); novices sort by surface features (the objects in the problem) --> spotting 'which principle applies' is the real skill, not memorizing surface details

---

#### Subcategory 2.2: Analogical Transfer and Schema Induction

**Source:** Gick, M. L., & Holyoak, K. J. (1983). Schema induction and analogical transfer. *Cognitive Psychology*, 15(1), 1-38.
- **DOK 1 - Facts:**
  - All experiments used Duncker's (1945) "radiation problem" (convergence solution) as the target transfer task; base rate ≈ 10% (established across multiple control replications with no prior analog).
  - With one appropriate military story analog, providing an explicit hint to use it yielded ~75% convergence solutions; without any hint (spontaneous transfer only): ~30%-paper states "only a third or less of the subjects who could potentially apply the analogy spontaneously noticed it."
  - Part I (Experiments 1-3): separate attempts to promote schema abstraction from a single analog using summarization instructions, a verbal statement of the underlying principle, or a diagrammatic representation-"none of these devices achieved a notable degree of success."
  - Part II experiments: with two prior story analogs whose similarities subjects were asked to describe, spontaneous (no-hint) transfer rose from ~30% to ~45%, and total solution frequency (including hint-prompted) rose from ~75% to ~80%.
  - Schema quality-rated from subjects' written descriptions of the similarities between the two analogs-was strongly predictive of subsequent transfer performance: G²(4) = 15.8, p < .005.
- **Link:** https://doi.org/10.1016/0010-0285(83)90002-6

- ! **DOK 2 - Summary:** people rarely apply a known method to a new-looking problem on their own (~30% even when they've seen the analog); comparing two examples of the same principle is what builds a transferable schema --> one worked example isn't enough

---

#### Subcategory 2.3: Interleaving, Discrimination Training, and Delayed Test Accuracy

**Source:** Rohrer, D., & Taylor, K. (2007). The shuffling of mathematics problems improves learning. *Instructional Science*, 35(6), 481-498.
- **DOK 1 - Facts:**
  - Two experiments with college undergraduates learning novel math procedures (Exp. 1: permutations; Exp. 2: volumes of 4 geometric solids); total number of practice problems held constant across conditions.
  - Experiment 1 (N = 66; spaced vs. massed practice; 1-week delayed test): spacers 74% (SE = 8%) vs. massers 49% (SE = 10%) and light massers 46% (SE = 7%); F(2, 57) = 3.59, p < .05, ηp² = .11; null effect of overlearning-massers vs. light massers not significantly different (p = .8).
  - Experiment 2 (N = 18; mixed/interleaved vs. blocked practice; 1-week delayed test): mixers 63% (SE = 12%) vs. blockers 20% (SE = 9%); d = 1.34; paper states "test performance improved 250% when practice problems of different types were mixed together and not blocked by type."
  - During practice in Experiment 2, the reverse held: blockers (89%, SE = 4%) outscored mixers (60%, SE = 7%), d = 1.06, p < .01; paper labels this a "desirable difficulty"-"learning strategy which provides superior test performance is not necessarily the one that optimizes practice performance."
  - Post-hoc analysis (Experiment 2): virtually all blocker errors at test involved selecting the wrong formula (not inability to execute after selecting it); paper concludes "students received the necessary discrimination training only when practice problems were mixed by type."
- **Link:** https://doi.org/10.1007/s11251-007-9015-8

**Source:** Rohrer, D., Dedrick, R. F., & Stershic, S. (2015). Interleaved practice improves mathematics learning. *Journal of Educational Psychology*, 107(3), 900-908.
- **DOK 1 - Facts:**
  - Classroom experiment (N = 126 seventh-grade students; ~3-month study; 10 practice assignments); same graph-equation and slope problems arranged as interleaved or blocked; practice-assignment accuracy approximately equal: blocked 81% vs. interleaved 84% (note: students self-corrected assignments before submission-paper treats these as compliance measures, not learning measures).
  - 1-day delayed unannounced test: interleaved 80% (SD = 33%) vs. blocked 64% (SD = 42%); t(62) = 2.39, p = .02, d = 0.42, 95% CI [0.07, 0.77].
  - 30-day delayed unannounced test: interleaved 74% (SD = 39%) vs. blocked 42% (SD = 43%); t(62) = 4.54, p < .001, d = 0.79, 95% CI [0.43, 1.15]; main effect of practice schedule: F(1, 124) = 24.43, p < .001, ηp² = .165.
  - Direct quote: "interleaved practice provided near immunity against forgetting, as the 30-fold increase in test delay reduced test scores by less than a tenth (from 80% to 74%)."
  - Laboratory interleaving studies uniformly produced larger effects (d = 1.34, d = 1.21; ηp² = .32) than this classroom study (d = 0.42 and 0.79), consistent with typical lab-to-classroom attenuation; paper notes this is "not a violation" of the expected pattern.
- **Link:** https://doi.org/10.1037/edu0000001

- ! **DOK 2 - Summary:** interleaved practice is far superior is enhancing long-term recall compared to blocking --> only slight percentage drop-off in recall after 30 days 

### Category 3: Cognitive Load, Feedback & Study-Feature Design

---

#### Subcategory 3.1: Cognitive Load Theory - Architecture & Instructional Effects

**Source:** Sweller, J., van Merriënboer, J. J. G., & Paas, F. (2019). Cognitive Architecture and Instructional Design: 20 Years Later. *Educational Psychology Review*, 31(2), 261-292.
- **DOK 1 - Facts:**
  - CLT was first fully described in Sweller (1988), "Cognitive Load During Problem Solving: Effects on Learning," *Cognitive Science*, 12, 275-285; the 1998 update (Sweller et al., *Educational Psychology Review*, 10, 251-296) has over 5,000 Google Scholar citations.
  - Three categories of cognitive load: **intrinsic** (element interactivity relative to the learner's existing knowledge - can only be changed by changing the material or the learner's expertise), **extraneous** (load imposed by how information is presented - can be reduced by changing instructional procedures), and **germane** (the redistribution of working memory resources away from extraneous activities toward processing intrinsic content; the 2019 paper revises the 1998 definition: germane load redistributes rather than adds to total load).
  - Working memory is strictly limited in capacity and duration *only for novel information*; once information is stored in long-term memory, these limits effectively disappear.
  - **Worked example effect**: first reported by Sweller & Cooper (1985) in algebra; studying a fully worked solution facilitates knowledge construction and transfer performance more than solving an equivalent problem, because problem-solving from scratch consumes all working memory and leaves none for schema acquisition.
  - **Expertise reversal effect**: instructional procedures designed for novices (e.g., worked examples, detailed guidance) first decrease in benefit, then disappear in benefit, and can eventually *reverse* - harming performance - as learner expertise increases (Kalyuga et al., 2003, cited in paper).
  - The 1998 article described 7 CLT instructional effects; the 2019 review reports 8 additional effects (for 15 total in Table 1), including the element interactivity, expertise reversal, guidance-fading, and transient information effects.
- **Link:** https://doi.org/10.1007/s10648-019-09465-5

- ! **DOK 2 - Summary:** Worked examples first when learners have little-to-no pre-existing schema to retrieve from; working memory gets bogged down otherwise and cannot properly learn. When the learner can reliably follow and self-explain solutions, drop guidance; self-testing w/o guidance becomes more effective for further learning.

---

#### Subcategory 3.2: Feedback Science - When Feedback Hurts and What Makes It Work

**Source:** Kluger, A. N., & DeNisi, A. (1996). The effects of feedback interventions on performance: A historical review, a meta-analysis, and a preliminary feedback intervention theory. *Psychological Bulletin*, 119(2), 254-284.
- **DOK 1 - Facts:**
  - Meta-analysis scope: 131 studies, **607 effect sizes**, 23,663 observations.
  - Feedback interventions (FIs) improved performance on average (d = .41), but **over one-third of FIs decreased performance** (commonly cited as ~38% of effect sizes were negative); this finding cannot be explained by sampling error or feedback sign alone.
  - The authors proposed Feedback Intervention Theory (FIT): FIs change the locus of attention among three hierarchically organized levels - task learning, task motivation, and meta-tasks (including self-related processes).
  - FIT central finding: **FI effectiveness decreases as attention moves up the hierarchy closer to the self and away from the task**; feedback aimed at the self (ego/identity) is the most likely to decrease performance.
- **Link:** https://doi.org/10.1037/0033-2909.119.2.254

**Source:** Hattie, J., & Timperley, H. (2007). The power of feedback. *Review of Educational Research*, 77(1), 81-112.
- **DOK 1 - Facts:**
  - Meta-synthesis scope: 12 meta-analyses encompassing 196 studies and 6,972 effect sizes; average effect size for feedback = **0.79** (described as "twice the average effect," placing feedback in the top 5-10 influences on achievement).
  - Effective feedback answers **three questions**: *Feed Up* ("Where am I going?" - goals), *Feed Back* ("How am I going?" - progress relative to goals), *Feed Forward* ("Where to next?" - next actions to close the gap); the paper states feed-forward "can have some of the most powerful impacts on learning."
  - Feedback operates at **four levels**: Task (FT - how well the task is performed), Process (FP - strategies used to complete the task), Self-Regulation (FR - self-monitoring and directing of actions), and Self (FS - personal evaluations of the learner as a person).
  - Feedback at the self level (e.g., praise directed at the person) is typically ineffective and often counterproductive: teacher praise meta-analysis (Wilkinson, 1981; 14 studies) yielded ES = 0.12; self-level feedback "deflects attention from the task" and is "too diluted, too often unrelated to performance."
  - Feedback at the process and self-regulation levels is more effective than task-level feedback; task-level feedback is most powerful when it corrects faulty interpretations rather than supplies missing information.

- **Link:** https://doi.org/10.3102/003465430298487

- ! **DOK 2 - Summary:** Feedback needs to be centered around the task/process/self-regulation to be effective (FT, FP, FR). Feedback to the self/ego (meta feedback) is ineffective, and can be detrimental
### Category 4: Metacognition & Calibration

#### Subcategory 4.1: Systematic Overconfidence and the Metacognitive Competence Gap

**Source:** Kruger, J., & Dunning, D. (1999). Unskilled and unaware of it: How difficulties in recognizing one's own incompetence lead to inflated self-assessments. *Journal of Personality and Social Psychology*, 77(6), 1121-1134.
- **DOK 1 - Facts:**
  - Across 4 studies using tests of humor, grammar, and logical reasoning, participants in the bottom quartile scored at the 12th percentile on average but estimated their own ability at the 62nd percentile - an overestimation gap of approximately 50 percentile points.
  - The authors identify a "dual burden": incompetence not only causes poor performance but simultaneously robs learners of the metacognitive capacity to recognize their own errors (a self-compounding deficit).
  - Several analyses linked miscalibration specifically to deficits in metacognitive skill - the capacity to distinguish accurate from erroneous responses - rather than to global self-serving bias.
  - Improving participants' skills via brief training (e.g., in logical reasoning) led to markedly better recognition of the limitations of their prior performance, confirming that metacognitive calibration tracks competence level.
- **Link:** https://doi.org/10.1037/0022-3514.77.6.1121

- ! **DOK 2 - Summary:** the least skilled overestimate themselves the most (bottom quartile scored at the 12th percentile but felt like the 62nd); being bad at something also strips the ability to notice you're bad --> weak students' self-assessments can't be trusted

---

#### Subcategory 4.2: The Fluency Illusion - Feeling-of-Knowing Does Not Equal Retrievability

**Source:** Koriat, A., & Bjork, R. A. (2005). Illusions of competence in monitoring one's knowledge during study. *Journal of Experimental Psychology: Learning, Memory, and Cognition*, 31(2), 187-194.
- **DOK 1 - Facts:**
  - JOLs (Judgments of Learning) - predictions of future recall made during study - are systematically inflated because they are formed while the target/answer is visible, a condition absent at test; the authors term this a "foresight bias."
  - The driving mechanism is the distinction between *a priori* relatedness (the probability a cue word alone elicits the target, which governs actual recall) and *a posteriori* relatedness (the perceived association when cue and target appear together, which governs JOLs).
  - Using backward-associated word pairs (e.g., cue "cheese" → target "cheddar," where the dominant association runs opposite to the study direction): JOLs averaged 75.7% while actual recall was 60.3% - a ~16 percentage-point overestimation; forward-associated control pairs showed near-perfect calibration (JOLs ~78.1%, recall ~78.7%).
  - Purely a posteriori pairs - word pairs with zero a priori cue-to-target association but high perceived relatedness when seen together - consistently produced marked illusions of competence across experiments.
  - The illusion reflects a mismatch inherent to standard educational practice: answers are present during study but absent at test, so the learner cannot easily adopt the examinee's perspective when judging their own future recall.
- **Link:** https://doi.org/10.1037/0278-7393.31.2.187

**Source:** Kornell, N., & Bjork, R. A. (2008). Learning concepts and categories: Is spacing the "enemy of induction"? *Psychological Science*, 19(6), 585-592.
- **DOK 1 - Facts:**
  - In 3 experiments where participants (Ns = 120, 72, and 80 UCLA undergraduates) studied paintings by 12 different artists, interleaved/spaced presentation produced significantly better inductive classification on a later test than massed (blocked) presentation - contrary to the researchers' own prior expectation.
  - On the first (feedback-uncontaminated) test block of Experiment 1a, spaced outperformed massed: 61% vs 35% correct artist attribution, Cohen's d = 0.99.
  - 78% of participants performed better in the spaced condition, yet 78% judged massing as equally effective or better - a direct inversion of metacognitive judgment relative to actual performance.
  - Across Experiments 1a and 2 combined, 85% of participants performed at least as well in the spaced condition; 83% nonetheless rated massed as equally or more effective.
  - The authors attribute the preference for massing to processing fluency: consecutive presentations of the same artist's paintings feel highly fluent, generating a misleading impression of having learned the style.
  - Participants' post-test metacognitive judgments were based on subjective study-phase experience (fluency) rather than on their own test outcomes - the illusion persisted even after participants had observed their results.
- **Link:** https://doi.org/10.1111/j.1467-9280.2008.02127.x

- ! **DOK 2 - Summary:** feeling fluent while studying does not equal being able to recall later; learners consistently rate the worse method (massing / seeing the answer) as better, and the illusion holds even after they see their own results --> subjective confidence is a bad readiness signal

---

#### Subcategory 4.3: Measuring Calibration - Brier Score and Murphy's Three-Term Decomposition

**Source:** Murphy, A. H. (1973). A new vector partition of the probability score. *Journal of Applied Meteorology*, 12(4), 595-600.
- **DOK 1 - Facts:**
  - Murphy decomposes the Brier (probability) score into three independent terms: (1) **uncertainty** - the inherent variability of event outcomes, equal to the Brier score if one always forecasts the sample base rate (irreducible by the forecaster); (2) **reliability** - how closely the issued forecast probabilities match observed outcome frequencies (the calibration component; lower is better); (3) **resolution** - the forecaster's ability to assign different probabilities on occasions with different actual outcome rates (higher is better).
  - Reliability and resolution are separable properties: a forecaster can achieve perfect reliability (zero miscalibration) by always issuing the climatological base-rate probability, yet have zero resolution - contributing no discriminative skill beyond knowing the base rate.
  - The total Brier score (lower = better) decreases by reducing reliability (removing miscalibration) and/or by increasing resolution (better discrimination between easy and hard cases); the uncertainty term is fixed by the event base rate and cannot be improved by the forecaster.
  - The paper introduces this decomposition as an improvement over Murphy's 1972 partition because reliability and resolution here are not linearly equivalent to their counterparts in the earlier partition, providing cleaner geometric interpretation.
  - The Brier score itself was defined by Brier (1950) as the mean squared error between forecast probabilities and binary outcomes: BS = (1/N) Σ(fₜ − oₜ)², where 0 = perfect accuracy and 1 = maximally inaccurate for binary events (*Monthly Weather Review*, 78(1), 1-3; doi: 10.1175/1520-0493(1950)078<0001:VOFEIT>2.0.CO;2).
- **Link:** https://journals.ametsoc.org/view/journals/apme/12/4/1520-0450_1973_012_0595_anvpot_2_0_co_2.xml

- ! **DOK 2 - Summary:** you can score how honest a probability is with a brier score, which splits into reliability (do your confidences match reality?) and resolution (can you separate hard from easy?); always forecasting the base rate gives perfect reliability but zero resolution --> measure both, not just calibration

### Category 5: Psychometrics & Score Prediction

#### Subcategory 5.1: Item Response Theory (IRT)

**Source:** Embretson, S. E., & Reise, S. P. (2000). *Item Response Theory for Psychologists*. Lawrence Erlbaum Associates.
- **DOK 1 - Facts:**
  - IRT models the probability of a correct response as a logistic function of (1) a continuous latent ability parameter θ (theta) and (2) item-specific parameters; the standard scaling constant 1.7 is used so the logistic curve approximates the normal ogive.
  - The one-parameter logistic (1PL) / Rasch model estimates only item difficulty (b) per item; all items share a fixed, constant discrimination; under the Rasch model the total raw score is a sufficient statistic for θ.
  - The two-parameter logistic (2PL) model adds an item discrimination parameter (a), producing item characteristic curves (ICCs) with different slopes; items with higher *a* values differentiate ability more sharply near their difficulty level b.
  - The three-parameter logistic (3PL) model adds a lower-asymptote parameter (c), representing the probability of a correct response at very low ability (pseudo-guessing); the three item parameters are difficulty (b), discrimination (a), and guessing (c).
  - IRT item parameters are theoretically sample-invariant and person ability estimates are item-set-invariant (the local invariance property), a property not shared by classical test theory (CTT) statistics such as item difficulty p-values or point-biserial correlations.
  - The book covers polytomous IRT models (for rating-scale data) alongside dichotomous models (pass/fail), and includes a chapter on CAT and DIF applications (Chapter 11).
- **Link:** https://doi.org/10.4324/9781410605269

- ! **DOK 2 - Summary:** IRT predicts the chance of a correct answer from a student's latent ability (theta) plus item params - difficulty, discrimination, guessing - estimated on a shared, sample-invariant scale --> the math for projecting a score from question-by-question performance

---

#### Subcategory 5.2: Computerized Adaptive Testing (CAT)

**Source:** van der Linden, W. J., & Glas, C. A. W. (Eds.). (2010). *Elements of Adaptive Testing*. Springer.
- **DOK 1 - Facts:**
  - CAT uses pre-estimated IRT item parameters to adapt item selection in real time: after each response the ability estimate θ̂ is updated and the next item is chosen to be maximally informative at the new θ̂.
  - Maximum Fisher information at the current θ̂ is the predominant item selection criterion in CAT; selecting the item with the highest information function value at θ̂ maximizes the rate at which the standard error of estimation (SEE) decreases.
  - The book identifies three standard CAT termination criteria: (a) a fixed test length, (b) a target SEE threshold (test stops when SEE falls below a preset value), and (c) adaptive mastery/classification rules that stop once a pass/fail decision can be made with sufficient confidence.
  - Multistage adaptive testing (MST) is described as a CAT variant in which pre-assembled testlet panels (groups of items) replace individual items; MST allows review of content before delivery and supports pretesting of item sets within live administrations.
  - Item-pool design is identified as a critical operational concern in CAT programs: pool size, item exposure control, and content balancing must be jointly managed to ensure security and construct coverage.
- **Link:** https://link.springer.com/book/10.1007/978-0-387-85461-8

- ! **DOK 2 - Summary:** adaptive testing picks each next item to be most informative at the current ability estimate, reaching a confident estimate in fewer questions; it can stop on a fixed length, a precision target, or once a pass/fail call is confident enough --> efficient ability estimation + a natural stopping/abstain rule

---

#### Subcategory 5.3: Selective Prediction & Proper Scoring Rules

**Source:** El-Yaniv, R., & Wiener, Y. (2010). On the foundations of noise-free selective classification. *Journal of Machine Learning Research*, 11, 1605-1641.
- **DOK 1 - Facts:**
  - Selective classification is formally defined as "classification with a reject option": the learner outputs either a class label or abstains (rejects) for any given input.
  - The core tradeoff is named the risk-coverage (RC) tradeoff: coverage Φ(f,g) = E[g(X)] (fraction of inputs the model accepts); risk R(f,g) = conditional error rate on accepted inputs only.
  - A selective classifier is a pair (f, g), where f is the base classifier and g: X → {0, 1} is a deterministic selection function; g(x) = 1 means classify, g(x) = 0 means abstain.
  - The paper traces the reject option to Chow (1957, 1970), who proved that the Bayes-optimal rejection rule is to abstain whenever the maximum a posteriori class probability falls below a threshold, yielding a monotone error-reject tradeoff.
  - For noise-free (realizable) settings, the paper proves that "perfect learning" - zero risk with non-trivial coverage - is achievable; tight upper and lower bounds on achievable RC tradeoffs are established for general hypothesis classes.
- **Link:** https://www.jmlr.org/papers/v11/el-yaniv10a.html

**Source:** Gneiting, T., & Raftery, A. E. (2007). Strictly proper scoring rules, prediction, and estimation. *Journal of the American Statistical Association*, 102(477). DOI: 10.1198/016214506000001437.
- **DOK 1 - Facts:**
  - A scoring rule S is **strictly proper** if S(Q, Q) ≥ S(P, Q) for all P, Q, with equality if and only if P = Q; this property uniquely incentivizes a forecaster to report their true predictive distribution rather than any distorted one.
  - Strictly proper scoring rules are characterized by strictly convex generalized entropy functions G: a regular scoring rule is (strictly) proper if and only if it corresponds to a (strictly) convex function on the space of predictive distributions.
  - The Brier score - S(P, x) = Σᵢ(pᵢ − 𝟙{x=i})² - is identified as a strictly proper scoring rule; the paper credits its introduction to Brier (1950), who published it in *Monthly Weather Review*, 78(1), 1-3.
  - The logarithmic score S(P, x) = log p(x) is also strictly proper; the paper shows that maximum likelihood estimation is a special case of optimum score estimation using the logarithmic rule.
  - The paper notes that an improper scoring rule can produce perverse incentives (forecaster's expected score is maximized by reporting a distribution other than their true belief), illustrated by a case study on probabilistic weather forecasts.
- **Link:** https://doi.org/10.1198/016214506000001437

- ! **DOK 2 - Summary:** models can be allowed to abstain (a 'reject option') when unsure, trading coverage for accuracy; and strictly-proper scoring rules (brier, log) only reward reporting your true probability --> the formal basis for 'abstain when unsure' and 'don't fake a number'

### Category 6: AI Card-Generation Safety & Assessment Validity

#### Subcategory 6.1: Multiple-Choice Item Validity

**Source:** Haladyna, T. M., Downing, S. M., & Rodriguez, M. C. (2002). A review of multiple-choice item-writing guidelines for classroom assessment. *Applied Measurement in Education*, 15(3), 309-334.
- **DOK 1 - Facts:**
  - Validated a taxonomy of 31 multiple-choice (MC) item-writing guidelines using two independent evidence sources: (1) consensus from 27 educational testing textbooks, and (2) results of 27 empirical research studies and reviews published since 1990.
  - Taxonomy is organized into 5 structural categories: Content Concerns (8 guidelines), Formatting Concerns (2), Style Concerns (3), Writing the Stem (4), Writing the Choices (14, of which Guideline 28 has 6 sub-variations dealing with clues to the right answer).
  - Guideline 15 ("include the central idea in the stem rather than the choices") was cited and endorsed in 100% of the 27 textbooks reviewed - the only guideline achieving unanimous textbook citation.
  - Guideline 18 states: "Develop as many effective choices as you can, but research suggests three [options] is adequate."
  - Guideline 17: word the stem positively; avoid negatives such as NOT or EXCEPT; if used, capitalize and boldface the negative word.
  - Guideline 29: make all distractors plausible; Guideline 30: use typical student errors to write distractors.
- **Link:** https://doi.org/10.1207/s15324818ame1503_5

- ! **DOK 2 - Summary:** there's a validated set of 31 rules for writing sound multiple-choice items (central idea in the stem, plausible distractors built from real student errors, ~3 good options is enough) --> the quality bar any AI-generated card has to clear

---

#### Subcategory 6.2: Automatic Item Generation (AIG)

**Source:** Gierl, M. J., Lai, H., & Turner, S. R. (2012). Using automatic item generation to create multiple-choice test items. *Medical Education*, 46(8), 757-765.
- **DOK 1 - Facts:**
  - Presents a three-stage AIG methodology: Stage 1 - content specialists build a cognitive model structure (3 hours); Stage 2 - item models are derived from the cognitive model (2 hours); Stage 3 - computer software (IGOR, Item GeneratOR, a Java-based program) combines content elements subject to constraints to generate items (1 hour). Total development time in the illustrative example: 6 hours.
  - Using this methodology on one surgery medical licensure item model, the method generated 1,248 unique multiple-choice items.
  - An "item model" is defined as a prototypical representation of a test item in which content elements are systematically varied by computer to produce unique new items; unlike human-authored items, each new item is generated algorithmically from a pre-validated template.
  - Rudner (cited) estimated the cost of developing a single item for a high-stakes licensure examination at US$1,500 to US$2,000.
  - Breithaupt et al. (cited) estimated a minimum of 2,000 items needed for a 40-item computerized adaptive test (CAT) with two annual administrations; at Rudner's per-item cost, building that item bank would require US$3,000,000-$4,000,000.
  - AIG is proposed as a scalable alternative to fully manual item development; however, the paper notes that AIG items must still "adhere to the highest standards of quality through the use of rigorous guidelines and item development practices."
- **Link:** https://doi.org/10.1111/j.1365-2923.2012.04289.x

- ! **DOK 2 - Summary:** automatic item generation spins many items from one human-built 'cognitive model' (1,248 from a single model); humans own correctness, the machine only varies surface; hand-writing items is expensive (~$1.5-2k each) --> AI's value is scaling variation, not sourcing truth

---

#### Subcategory 6.3: LLM Hallucination & Prompt Injection Risk

**Source:** Ji, Z., Lee, N., Frieske, R., Yu, T., Su, D., Xu, Y., Ishii, E., Bang, Y., Chen, D., Chan, H. S., Dai, W., Madotto, A., & Fung, P. (2023). Survey of hallucination in natural language generation. *ACM Computing Surveys*, 55(12), Article 248, 1-38.
- **DOK 1 - Facts:**
  - Two primary hallucination categories are defined: (1) **Intrinsic hallucination** - generated output contradicts the source content (e.g., stating "the first Ebola vaccine was approved in 2021" when the source says 2019); (2) **Extrinsic hallucination** - generated output can neither be supported nor contradicted by the source content.
  - Extrinsic hallucination is not always factually wrong (it may draw on correct background knowledge) but is "treated with caution because its unverifiable aspect of the additional information increases the risk from a factual safety perspective."
  - Three related terms are clarified: *hallucination* (unfaithful or nonsensical generated text), *faithfulness* (antonym - staying consistent with the provided source), and *factuality* (being based on fact, where "fact" may mean source content or world knowledge depending on definition).
  - In high-stakes domains the survey authors note that "a hallucinatory summary generated from a patient information form could pose a risk to the patient" and that hallucinatory machine-translated medicine instructions "may provoke a life-threatening incident."
  - Carlini et al. (2020), cited in the survey, demonstrated that language models can be prompted to recover sensitive personal information (e-mail address, phone/fax number, physical address) from the training corpus - a form of hallucination the survey terms *memorization*.
  - The survey covers six NLG downstream tasks: abstractive summarization, dialogue generation, generative question answering, data-to-text generation, machine translation, and visual-language generation; a section on hallucinations in large language models (LLMs) was added in January 2024.
- **Link:** https://doi.org/10.1145/3571730

**Source:** OWASP GenAI Security Project. (2025). *OWASP Top 10 for Large Language Model Applications v2025* - LLM01:2025 Prompt Injection.
- **DOK 1 - Facts:**
  - Prompt Injection is ranked **LLM01:2025** - the #1 critical vulnerability in the OWASP Top 10 for LLM Applications 2025 list.
  - Official definition: "A Prompt Injection Vulnerability occurs when user prompts alter the LLM's behavior or output in unintended ways. These inputs can affect the model even if they are imperceptible to humans, therefore prompt injections do not need to be human-visible/readable, as long as the content is parsed by the model."
  - Two sub-types: (a) **Direct injection** - user input directly and intentionally alters model behavior; (b) **Indirect injection** - hidden instructions embedded in external content (documents, websites, e-mails) that the LLM processes alter its behavior without user awareness.
  - OWASP states that both Retrieval Augmented Generation (RAG) and fine-tuning "aim to make LLM outputs more relevant and accurate" but "research shows that they do not fully mitigate prompt injection vulnerabilities."
  - OWASP acknowledges a fundamental limitation: "Given the stochastic nature of generative AI, fool-proof prevention methods remain unclear."
- **Link:** https://genai.owasp.org/llmrisk/llm01-prompt-injection/

- ! **DOK 2 - Summary:** LLMs hallucinate (intrinsic = contradicts the source; extrinsic = unverifiable), which is poison in an answer key; prompt injection - especially indirect, hidden inside documents the model reads - is the #1 LLM risk with no fool-proof fix --> RAG-ing over FASB/IRC text is an attack surface, not a safe input

### Category 7: CPA Exam Structure & Scoring

---

#### Subcategory 7.1: Exam Architecture - CPA Evolution Format

**Source:** AICPA (2026). *Uniform CPA Examination Blueprints (effective January 1, 2026).* Association of International Certified Professional Accountants.
- **DOK 1 - Facts:**
  - CPA Evolution format (effective January 10, 2024): all candidates must pass 3 Core sections - Auditing and Attestation (AUD), Financial Accounting and Reporting (FAR), and Taxation and Regulation (REG) - plus exactly 1 chosen Discipline section from Business Analysis and Reporting (BAR), Information Systems and Controls (ISC), or Tax Compliance and Planning (TCP). BEC (Business Environment and Concepts) testing officially ended December 2023.
  - Each of the 6 sections is 4 hours long and divided into exactly 5 testlets: testlets 1-2 contain multiple-choice questions (MCQs); testlets 3-5 contain task-based simulations (TBSs).
  - Per-section question counts (Blueprint effective January 1, 2026): AUD 78 MCQs / 7 TBSs; FAR 50 / 7; REG 72 / 8; BAR 50 / 7; ISC 82 / 6; TCP 68 / 7.
  - Score weighting of MCQs vs. TBSs: 50% / 50% for all sections except ISC, which is 60% MCQs / 40% TBSs.
  - Research TBSs use embedded authoritative literature specific to each section: FAR and BAR → FASB Accounting Standards Codification; REG and TCP → Internal Revenue Code (and Treasury Regulations); AUD → auditing and attestation standards (including PCAOB Auditing Standards and AICPA Auditing Standards).
- **Link:** https://www.aicpa-cima.com/resources/article/learn-what-is-tested-on-the-cpa-exam

**Source:** AICPA (2023). *Infrastructure Changes to the CPA Exam in 2024.* Association of International Certified Professional Accountants. (Distributed via state CPA societies.)
- **DOK 1 - Facts:**
  - Effective January 2024: multistage adaptive testing (MST) was eliminated from MCQ testlets; MCQ testlets now use a **linear (non-adaptive) design**. ⚠ NOTE: multiple review-course guides (written before or without awareness of this change) still describe adaptive MCQ testlets - this is outdated for the current (CPA Evolution) exam.
  - Prior MCQ design (2004-2023): two-stage adaptive - all candidates received a medium-difficulty testlet 1, then were routed to either a medium-difficulty or a difficult testlet 2 based on testlet 1 performance; harder questions carried more score weight.
  - BEC's Written Communication Task (essay question) was eliminated effective January 2024; the current CPA Evolution exam has no written essays.
  - MST was in place from CPA Exam computerization in 2004 through December 2023 (approximately 20 years); removal motivated by reduced MCQ count per form (2 testlets, down from 3 pre-2017), heavier TBS emphasis, and operational efficiency under the new driver software.
- **Link:** https://www.ficpa.org/publication/aicpa-announces-2024-infrastructure-changes-cpa-exam

- ! **DOK 2 - Summary:** post-2024 'CPA Evolution' = 3 core sections (AUD/FAR/REG) + 1 chosen discipline (BAR/ISC/TCP), each a 4-hour exam of 5 testlets (2 MCQ then 3 TBS), ~50/50 MCQ/TBS weight (ISC 60/40); MCQs are now LINEAR (adaptive MST killed Jan 2024) and essays are gone --> the format a performance model has to mirror

---

#### Subcategory 7.2: Scoring Mechanics & Section Pass Rates

**Source:** AICPA (2026). *Learn more about CPA Exam scoring and pass rates* (updated April 20, 2026). AICPA & CIMA.
- **DOK 1 - Facts:**
  - Passing score: 75 on a scale of 0-99; this is a scaled score, not a percent-correct; a score of 75 does not mean 75% of questions were answered correctly. Scores are not curved; no quotas.
  - Scaled scores are calculated using Item Response Theory (IRT): each question's contribution to the score reflects both correctness and the relative difficulty of that question.
  - 2025 full-year cumulative pass rates (official AICPA, all 4 quarters): AUD 48.21%; FAR 42.12%; REG 63.12%; BAR 41.94%; ISC 67.79%; TCP 77.65%.
  - FAR had the lowest cumulative pass rate of all 6 sections in 2025 (42.12%); TCP had the highest (77.65%).
  - Elijah Watt Sells Award: candidates must achieve a cumulative average above 95.50 across all 4 sections and must have passed all 4 on the first attempt; the AICPA contacts eligible candidates the following spring.
- **Link:** https://www.aicpa-cima.com/resources/article/learn-more-about-cpa-exam-scoring-and-pass-rates

- ! **DOK 2 - Summary:** passing is a scaled 75 on a 0-99 scale (NOT 75% correct), computed via IRT and not curved; 2025 section pass rates run from FAR ~42% (hardest) to TCP ~78% (easiest) --> the real scale readiness projects onto, with base rates that differ a lot by section

---

#### Subcategory 7.3: Credit Window & Licensing Logistics

**Source:** NASBA (2023). *NASBA Announces Historic Rule Amendment Following Record Exposure Draft Response* (April 24, 2023). National Association of State Boards of Accountancy.
- **DOK 1 - Facts:**
  - NASBA UAA Model Rule 5-7 was amended on April 21, 2023: candidates now have a rolling **30-month** window to pass all 4 required sections, extended from the prior 18-month limit that had been in place since CPA Exam computerization in 2004.
  - The 30-month rolling period begins on the date the first passing score is released by NASBA (not the exam date); if all 4 sections are not passed within 30 months of that date, credit for any section passed outside the window expires and the section must be retaken.
  - The NASBA exposure draft initially proposed a 24-month extension; the NASBA Board of Directors elected to approve the longer 30-month period.
  - ⚠ The UAA Model Rules are recommendations to state boards, not mandatory law; each of the 55 U.S. jurisdictions must independently adopt the amendment. NASBA states: "Current Exam candidates remain under existing rules until, if and when, the board to which they applied makes changes." Verify the rule in your specific jurisdiction.
- **Link:** https://nasba.org/blog/2023/04/24/nasba-announces-historic-exam-rule-amendment/

- ! **DOK 2 - Summary:** candidates now get a rolling 30-month window (up from 18) to pass all 4 sections, starting when the first passing score is released - but it's a NASBA model rule each state adopts on its own --> a real deadline to study toward, but jurisdiction-dependent

### Category 8: CPA Market & Competitive Landscape

---

#### Subcategory 8.1: Candidate Volume & Pipeline Trend

**Source:** NASBA (Nov. 2024; Aug. 2025). "2020-2023 CPA Exam Statistics Now Available" and "2024 NASBA Report Released." NASBA.org press releases; data drawn from *The NASBA Report: Candidate Performance on the Uniform CPA Examination*, 2023 and 2024 Editions.
- **DOK 1 - Facts:**
  - 84,980 unique candidates sat for the Uniform CPA Examination in 2023; 41,415 were new candidates; 20,036 completed their final section.
  - 74,165 unique candidates sat in 2024; 27,994 were new candidates; 13,070 completed their final section.
  - Total candidate volume fell by 10,815 (−12.7%) from 2023 to 2024; new candidates fell by 13,421 (−32.4%); candidates completing their final section fell by 6,966 (−34.8%).
  - NASBA paused publication of its annual Candidate Performance Book during the CPA Evolution transition; the 2020-2023 editions were released together in November 2024 and the 2024 edition in August 2025.
- **Link:** https://nasba.org/blog/2024/11/27/2020-2023-cpa-exam-statistics-now-available/ ; https://nasba.org/blog/2025/08/18/explore-the-numbers-behind-cpa-exam-success-2024-nasba-report-released/

**Source:** AICPA & CIMA (June 2, 2025). "Accounting Enrollment Increased 12% for Spring Semester." AICPA-CIMA.com; underlying data from the National Student Clearinghouse Research Center.
- **DOK 1 - Facts:**
  - Total undergraduate accounting enrollment for spring 2025: 266,507 students - an increase of 29,312 students (+12%) vs. spring 2024.
  - Spring 2025 marked the third consecutive semester of enrollment growth and the second consecutive semester of double-digit percentage increases.
  - 2-year institution enrollment rose 24% to 77,936 students; 4-year institution enrollment rose 11% to 188,571 students.
- **Link:** https://www.aicpa-cima.com/news/article/accounting-enrollment-increased-12-for-spring-semester

- ! **DOK 2 - Summary:** CPA volume is shrinking (~85k candidates in 2023 --> ~74k in 2024, -12.7%, new candidates -32%) but may be turning around (accounting enrollment +12% in spring 2025) --> a contracting-but-maybe-recovering market

---

#### Subcategory 8.2: Market Size

**Source:** Verified Market Reports (2026). "Global CPA Exam Reviews Market Size, Share, Trends & Industry Forecast 2026-2034." VerifiedMarketReports.com.
- **DOK 1 - Facts:**
  - ⚠ Global CPA Exam Reviews market stated at USD 1.2 billion (2025 base year), projected to reach USD 2.5 billion by 2034 at a CAGR of 9.2% (forecast window 2026-2034). Non-audited commercial projection; methodology not disclosed publicly.
  - ⚠ The same report page states North America alone at USD 2.5 billion in 2024 - a figure larger than the report's own stated global figure of USD 1.2 billion for 2025, indicating internal inconsistency in the vendor data.
  - ⚠ Competing vendors give widely divergent 2024 base-year estimates for the same market: Verified Market Research (a different firm, verifiedmarketresearch.com) values it at USD 285 million with CAGR 6.5%; WiseGuy Reports values it at USD 1.95 billion with CAGR 5.4%. The spread across vendors spans nearly 7× from low to high.
  - No independently audited revenue figure for the CPA exam review sector is publicly available; AICPA does not publish industry revenue data.
- **Link:** https://www.verifiedmarketreports.com/product/cpa-exam-reviews-market/

- ! **DOK 2 - Summary:** the CPA-review market is real but un-auditable: vendor size estimates span ~7x ($285M to $1.95B) and one report even contradicts itself --> treat every market-size figure as a rough guess, not a fact

---

#### Subcategory 8.3: Market Concentration & Section Failure Rate

**Source:** AICPA Board of Examiners (Apr. 2024 and subsequent quarters). "24Q1 CPA Exam Pass Rates" and later quarterly releases. AICPA-CIMA.com; full-year 2024 figures aggregated from AICPA quarterly releases by UWorld CPA Review (accounting.uworld.com/cpa-review/cpa-exam/pass-rates/).
- **DOK 1 - Facts:**
  - 2024 full-year cumulative pass rates by section: AUD 45.79%; FAR 39.59%; REG 62.61%; BAR 38.08%; ISC 58.00%; TCP 73.91%.
  - Derived failure rates (100% − pass rate): FAR ~60.4%; BAR ~61.9%; AUD ~54.2%; REG ~37.4%; ISC ~42.0%; TCP ~26.1%.
  - BAR (38.08%) had the lowest pass rate of any section in 2024; TCP (73.91%) had the highest.
  - AICPA's Board of Examiners noted in its 24Q1 announcement that TCP candidates were "generally better prepared to take TCP than the BAR candidates were to take BAR and ISC candidates were to take ISC."
- **Link:** https://www.aicpa-cima.com/certifications/article/24q1-cpa-exam-pass-rates ; https://accounting.uworld.com/cpa-review/cpa-exam/pass-rates/

**Source:** Journal of Accountancy (March 2012). "In memoriam: Newton Becker." JournalOfAccountancy.com.
- **DOK 1 - Facts:**
  - "It's been estimated that as many as half the CPAs in the United States passed the exam with the help of his [Becker's] course." ⚠ The source of this underlying estimate is unnamed in the obituary; the claim predates 2012 and the 2024 CPA Evolution format change; it cannot be independently verified from primary data.
  - As of early 2012, more than 400,000 people who completed Becker's course had passed the exam and become licensed CPAs.
  - ⚠ The claim that Becker + UWorld + NINJA together hold "90%+ of the U.S. market": no primary or independently audited source was found; treat as an unverified industry estimate.
- **Link:** https://www.journalofaccountancy.com/issues/2012/mar/becker/

- ! **DOK 2 - Summary:** becker is entrenched (allegedly ~half of US CPAs used it, though unverified) and ~50% of section attempts fail (BAR/FAR worst) --> a big, motivated retaker pool, and incumbent market-share claims you can't take at face value
---

#### Subcategory 8.4: Section-Attempt Volume & Entry Economics

**Source:** Derived from NASBA candidate counts (Subcat 8.1) + the CPA market analysis (internal deep-research synthesis). ⚠ Derived figures and market estimates, not single audited statistics.
- **DOK 1 - Facts:**
  - ~148,000 total section attempts were taken in 2024 (candidates sit up to 4 sections; retakes are roughly half of all attempts). ⚠ Derived from NASBA candidate counts, not a separately published figure.
  - With section pass rates averaging ~45-50%, roughly **70,000-80,000 section attempts fail per year** in the U.S. - the addressable retaker pool. ⚠ Derived estimate.
  - Building a full institutional competitor (all sections, ~5,000+ items per section, video lectures, TBS tooling, authoritative-literature integration, and a B2B sales motion) is estimated at **~$10-20M and 3-5 years** to institutional credibility. ⚠ Market-analysis estimate, not audited.
- **Link:** https://nasba.org/blog/2025/08/18/explore-the-numbers-behind-cpa-exam-success-2024-nasba-report-released/

- ! **DOK 2 - Summary:** ~70-80k failed section attempts a year --> the retaker pool, and a full head-on competitor to Becker and other B2B companies is ~$10-20M / 3-5yr --> attack retakers, not Becker's B2B channel (grounds SPOV 1)

## References

### Memory & Spaced Repetition
1. Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer, D. (2006). Distributed practice in verbal recall tasks: A review and quantitative synthesis. *Psychological Bulletin, 132*(3), 354-380.  
   https://doi.org/10.1037/0033-2909.132.3.354
2. Roediger, H. L., III, & Karpicke, J. D. (2006). Test-enhanced learning: Taking memory tests improves long-term retention. *Psychological Science, 17*(3), 249-255.  
   https://doi.org/10.1111/j.1467-9280.2006.01693.x
3. Woźniak, P. A. (1990). *Optimization of learning* (Master's thesis, University of Technology in Poznan). [SM-2 algorithm; archived at supermemo.guru / supermemo.com]  
   https://www-beta.supermemo.com/archives1990-2015/english/ol/sm2
4. Ye, J., Su, J., & Cao, Y. (2022). A stochastic shortest path algorithm for optimizing spaced repetition scheduling. In *Proceedings of the 28th ACM SIGKDD Conference on Knowledge Discovery and Data Mining* (KDD '22), pp. 4381-4390. ACM. [FSRS foundational paper + Anki 23.10 integration]  
   https://doi.org/10.1145/3534678.3539081 (paper); https://github.com/ankitects/anki/releases/tag/23.10 (Anki 23.10 release notes); https://docs.ankiweb.net/deck-options.html (Anki manual - FSRS section)

### Transfer of Learning & Desirable Difficulties
1. Chi, M. T. H., Feltovich, P. J., & Glaser, R. (1981). Categorization and representation of physics problems by experts and novices. *Cognitive Science*, 5(2), 121-152.  
   https://doi.org/10.1207/s15516709cog0502_2
2. Gick, M. L., & Holyoak, K. J. (1983). Schema induction and analogical transfer. *Cognitive Psychology*, 15(1), 1-38.  
   https://doi.org/10.1016/0010-0285(83)90002-6
3. Rohrer, D., & Taylor, K. (2007). The shuffling of mathematics problems improves learning. *Instructional Science*, 35(6), 481-498.  
   https://doi.org/10.1007/s11251-007-9015-8
4. Rohrer, D., Dedrick, R. F., & Stershic, S. (2015). Interleaved practice improves mathematics learning. *Journal of Educational Psychology*, 107(3), 900-908.  
   https://doi.org/10.1037/edu0000001

### Cognitive Load, Feedback & Study-Feature Design
1. Sweller, J., van Merriënboer, J. J. G., & Paas, F. (2019). Cognitive Architecture and Instructional Design: 20 Years Later. *Educational Psychology Review*, 31(2), 261-292.  
   https://doi.org/10.1007/s10648-019-09465-5
2. Kluger, A. N., & DeNisi, A. (1996). The effects of feedback interventions on performance: A historical review, a meta-analysis, and a preliminary feedback intervention theory. *Psychological Bulletin*, 119(2), 254-284.  
   https://doi.org/10.1037/0033-2909.119.2.254
3. Hattie, J., & Timperley, H. (2007). The power of feedback. *Review of Educational Research*, 77(1), 81-112.  
   https://doi.org/10.3102/003465430298487

### Metacognition & Calibration
1. Kruger, J., & Dunning, D. (1999). Unskilled and unaware of it: How difficulties in recognizing one's own incompetence lead to inflated self-assessments. *Journal of Personality and Social Psychology*, 77(6), 1121-1134.  
   https://doi.org/10.1037/0022-3514.77.6.1121
2. Koriat, A., & Bjork, R. A. (2005). Illusions of competence in monitoring one's knowledge during study. *Journal of Experimental Psychology: Learning, Memory, and Cognition*, 31(2), 187-194.  
   https://doi.org/10.1037/0278-7393.31.2.187
3. Kornell, N., & Bjork, R. A. (2008). Learning concepts and categories: Is spacing the "enemy of induction"? *Psychological Science*, 19(6), 585-592.  
   https://doi.org/10.1111/j.1467-9280.2008.02127.x
4. Murphy, A. H. (1973). A new vector partition of the probability score. *Journal of Applied Meteorology*, 12(4), 595-600.  
   https://journals.ametsoc.org/view/journals/apme/12/4/1520-0450_1973_012_0595_anvpot_2_0_co_2.xml

### Psychometrics & Score Prediction
1. Embretson, S. E., & Reise, S. P. (2000). *Item Response Theory for Psychologists*. Lawrence Erlbaum Associates.  
   https://doi.org/10.4324/9781410605269
2. van der Linden, W. J., & Glas, C. A. W. (Eds.). (2010). *Elements of Adaptive Testing*. Springer.  
   https://link.springer.com/book/10.1007/978-0-387-85461-8
3. El-Yaniv, R., & Wiener, Y. (2010). On the foundations of noise-free selective classification. *Journal of Machine Learning Research*, 11, 1605-1641.  
   https://www.jmlr.org/papers/v11/el-yaniv10a.html
4. Gneiting, T., & Raftery, A. E. (2007). Strictly proper scoring rules, prediction, and estimation. *Journal of the American Statistical Association*, 102(477). DOI: 10.1198/016214506000001437.  
   https://doi.org/10.1198/016214506000001437

### AI Card-Generation Safety & Assessment Validity
1. Haladyna, T. M., Downing, S. M., & Rodriguez, M. C. (2002). A review of multiple-choice item-writing guidelines for classroom assessment. *Applied Measurement in Education*, 15(3), 309-334.  
   https://doi.org/10.1207/s15324818ame1503_5
2. Gierl, M. J., Lai, H., & Turner, S. R. (2012). Using automatic item generation to create multiple-choice test items. *Medical Education*, 46(8), 757-765.  
   https://doi.org/10.1111/j.1365-2923.2012.04289.x
3. Ji, Z., Lee, N., Frieske, R., Yu, T., Su, D., Xu, Y., Ishii, E., Bang, Y., Chen, D., Chan, H. S., Dai, W., Madotto, A., & Fung, P. (2023). Survey of hallucination in natural language generation. *ACM Computing Surveys*, 55(12), Article 248, 1-38.  
   https://doi.org/10.1145/3571730
4. OWASP GenAI Security Project. (2025). *OWASP Top 10 for Large Language Model Applications v2025* - LLM01:2025 Prompt Injection.  
   https://genai.owasp.org/llmrisk/llm01-prompt-injection/

### CPA Exam Structure & Scoring
1. AICPA (2026). *Uniform CPA Examination Blueprints (effective January 1, 2026).* Association of International Certified Professional Accountants.  
   https://www.aicpa-cima.com/resources/article/learn-what-is-tested-on-the-cpa-exam
2. AICPA (2023). *Infrastructure Changes to the CPA Exam in 2024.* Association of International Certified Professional Accountants. (Distributed via state CPA societies.)  
   https://www.ficpa.org/publication/aicpa-announces-2024-infrastructure-changes-cpa-exam
3. AICPA (2026). *Learn more about CPA Exam scoring and pass rates* (updated April 20, 2026). AICPA & CIMA.  
   https://www.aicpa-cima.com/resources/article/learn-more-about-cpa-exam-scoring-and-pass-rates
4. NASBA (2023). *NASBA Announces Historic Rule Amendment Following Record Exposure Draft Response* (April 24, 2023). National Association of State Boards of Accountancy.  
   https://nasba.org/blog/2023/04/24/nasba-announces-historic-exam-rule-amendment/

### CPA Market & Competitive Landscape
1. NASBA (Nov. 2024; Aug. 2025). "2020-2023 CPA Exam Statistics Now Available" and "2024 NASBA Report Released." NASBA.org press releases; data drawn from *The NASBA Report: Candidate Performance on the Uniform CPA Examination*, 2023 and 2024 Editions.  
   https://nasba.org/blog/2024/11/27/2020-2023-cpa-exam-statistics-now-available/ ; https://nasba.org/blog/2025/08/18/explore-the-numbers-behind-cpa-exam-success-2024-nasba-report-released/
2. AICPA & CIMA (June 2, 2025). "Accounting Enrollment Increased 12% for Spring Semester." AICPA-CIMA.com; underlying data from the National Student Clearinghouse Research Center.  
   https://www.aicpa-cima.com/news/article/accounting-enrollment-increased-12-for-spring-semester
3. Verified Market Reports (2026). "Global CPA Exam Reviews Market Size, Share, Trends & Industry Forecast 2026-2034." VerifiedMarketReports.com.  
   https://www.verifiedmarketreports.com/product/cpa-exam-reviews-market/
4. AICPA Board of Examiners (Apr. 2024 and subsequent quarters). "24Q1 CPA Exam Pass Rates" and later quarterly releases. AICPA-CIMA.com; full-year 2024 figures aggregated from AICPA quarterly releases by UWorld CPA Review (accounting.uworld.com/cpa-review/cpa-exam/pass-rates/).  
   https://www.aicpa-cima.com/certifications/article/24q1-cpa-exam-pass-rates ; https://accounting.uworld.com/cpa-review/cpa-exam/pass-rates/
5. Journal of Accountancy (March 2012). "In memoriam: Newton Becker." JournalOfAccountancy.com.  
   https://www.journalofaccountancy.com/issues/2012/mar/becker/
6. Anki project (ankitects). LICENSE file, ankitects/anki repository, GitHub; Anki FAQs (faqs.ankiweb.net); GNU Affero General Public License v3.0 full text (gnu.org/licenses/agpl-3.0.en.html); VS Code (Code - OSS) LICENSE.txt, microsoft/vscode repository, GitHub.
   https://github.com/ankitects/anki/blob/HEAD/LICENSE ; https://faqs.ankiweb.net/can-i-use-anki-in-a-company-or-school.html ; https://www.gnu.org/licenses/agpl-3.0.en.html ; https://github.com/microsoft/vscode/blob/main/LICENSE.txt
7. NASBA Candidate Performance reports (2023-2024) + CPA market analysis (internal deep-research synthesis). Basis for the ~148k section-attempt volume, the ~70,000-80,000 failed-attempts/year retaker pool, and the ~$10-20M / 3-5-year full-competitor estimate; derived/estimated, not audited.  
   https://nasba.org/blog/2025/08/18/explore-the-numbers-behind-cpa-exam-success-2024-nasba-report-released/
