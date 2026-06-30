# Features to Build in the Anki Fork

### Rust Engine (rslib) - the real changes
- **Deadline-anchored scheduler (SPOV 3):** Extend the FSRS scheduling code to take an `exam_date` + a per-section target retention, compute intervals backward from the date, ramp desired retention up as the date nears. New protobuf message (e.g. `ComputeExamSchedule`) callable from Python. This is the core engine change for the assignment.
- **Effort / latency-aware grading (SPOV 2):** Anki already logs answer time → use fast-correct to mark a rep "too easy", auto-jump its interval or flag it for a harder probe. Add an effort/latency field to the review log + a hook in the answer-card path.
- **Confusion-set queue builder (SPOV 4):** Backend query that takes topic-weakness + a `CONFUSABLE` map → returns a label-stripped, interleaved queue ordered by discrimination weakness. Needs a deep-structure/schema tag on notes + an index to stay fast.
- **Mastery + gap query (SPOV 5):** One fast backend call → per topic: memory score (recall on study pile) vs performance score (locked pile) + the gap. Has to be fast on 50k cards (also knocks out the assignment's "mastery query" challenge).
- **Abstain rule (SPOV 5):** Backend returns "no readiness yet" when held-out coverage/volume is under a set threshold.
### Data Model (SQLite / note types)
- Deep-structure / schema tag per note (SPOV 4).
- A sealed "performance bank" note type or deck that the scheduler **never** queues for study (SPOV 5). This is the firewall in code, not just convention.
- Confidence value stored per review (SPOV 2).
- Provenance fields on every AI-made card: cited source passage + generation method + checker pass/fail. (Assignment rule: any AI output with no traceable source zeroes that section.)
### Frontend (aqt + reviewer HTML/JS)
- **Attempt-before-reveal + confidence capture (SPOV 2):** Change the reviewer flow so the student commits an answer + a confidence *before* the back shows.
- **"Which treatment applies?" gate (SPOV 4):** A pre-step that requires picking the method/standard before computing anything.
- **3-score dashboard (SPOV 5 + SPOV 3):** Memory / Performance / Readiness, with the gap shown and the abstain message when data is thin. Readiness shown as the exam-day projection (as a range, not a point), not "today."
### AI Content Pipeline (Python add-on or separate service, offline-safe)
- **RAG card generator:** Pull from source docs (textbook chapters, notes, FASB/IRC) → generate full Q&A flashcards at scale, targeting the 50k deck. Every card stores the source passage it came from. (Assignment rule: AI output with no traceable source zeroes that section.)
- **Quality checker:** A gold set of known-correct Q&A; run generated cards through it, report 3 counts (correct+useful / wrong / correct-but-bad-teaching). Set the passing cutoff *before* looking; auto-block anything that fails. "A wrong fact is worse than no card."
- **Beat a baseline:** Show the RAG pipeline outperforms plain keyword/vector search on the eval (assignment requirement).
- **Leakage check:** Scan generated cards so none are near-copies of the sealed performance bank (keeps SPOV 5's firewall) or of the held-out test set.
- Treat ingested FASB/IRC text as untrusted (prompt-injection surface), but that is a guardrail, not a reason to limit generation.
- **Runs AI-off:** The deck is pre-generated, so study + scheduling + scoring never call a model live.
### Review Modes (3 modes - only one is a flashcard)
- **Recall flashcards** : Classic Anki loop: front → reveal → self-rate. Atomic facts only. 
- **Confusion-set / "which treatment?"**: Label-stripped, scored on discrimination not recall. 
- **TBS task review** (SPOV 6): Multi-step interactive task, graded objectively with partial credit. Not a flip-and-self-rate. 

**Why a TBS cannot be a flashcard:** Anki's loop = one recall + one self-graded button (Again / Hard / Good / Easy), and FSRS eats that single grade. A TBS is a multi-step task with an objective partial-credit result - you don't "self-rate" whether your journal entry balanced.

**The 4 TBS types, each its own mini-mode:**
- **Research sim:** A lit-search pane (FASB ASC / IRC / PCAOB embedded); find + submit the cite, graded on correctness and time. Navigation skill, not recall - drill the lookup, don't memorize the codification.
- **Journal-entry sim** (most common FAR/BAR): A JE grid; enter the lines, graded line-by-line with partial credit.
- **Numeric / option-list:** Input cells / dropdowns, graded per cell.
- **Document-review sim** (heaviest AUD): Exhibits + a doc with blanks; each blank is a "which treatment?" call - reuses the SPOV 4 confusion-set logic per blank.

**How it plugs into the pillars:**
- The sealed performance bank (SPOV 5) should be mostly TBS, not MCQs - a TBS on a never-seen scenario is the sharpest transfer test.
- Grading is step-level (method vs slip), not one binary lapse; partial credit per step feeds the performance score.
- Memory/FSRS still runs underneath for the atomic facts a TBS leans on, but the TBS itself is not on the recall schedule.
- Readiness weights MCQ vs TBS like the real section (50/50, ISC 60/40) and tracks a separate TBS number per section.

**What this forces onto the build:**
- A TBS note type holding multiple gradable steps/blanks + exhibits, separate from the MCQ note type.
- A TBS review surface (new screen), not the card reviewer.
- A backend that accepts a structured / partial-credit score (a candidate for the assignment's real Rust change alongside the scheduler).
- RAG must generate TBS items (JE / research / numeric); start with research + numeric (cleanly checkable), document-review later.
- Interface-fluency sim: mimic the real exam's dual-skill environment (content + split-screen software with exhibits, a spreadsheet, and lit search) so candidates are not cold on the UI.