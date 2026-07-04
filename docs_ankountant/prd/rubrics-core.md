# Phase A — Shared-core rubrics (A1–A10)

> Full acceptance criteria for the Phase-A features listed in `../PRD.md`. The Build agent should open this file (and `contracts-and-data.md`) before implementing a feature. Each AC is a testable Given/When/Then with a **verify-by** command. Constants live in one module (see `../PRD.md` FR-4). Proto message shapes: `contracts-and-data.md`. Integration file paths: `contracts-and-data.md`.

---

## A1 — Deadline-anchored scheduler (SPOV 2/3) · P0 · depends: —

**Behavior (pinned):** exam date is written/read through `SchedulerService.SetExamDate` / `GetExamDate` and stored as a hidden `Ankountant Settings` note keyed by `(section, exam.date)`, so it merges as a normal note instead of overwriting the whole `col` config blob. Legacy `ankountant.<section>.exam.date` config is read only as a migration fallback. `desired_retention(d)`, `d = days_to_exam`: `d ≥ 60 → 0.80`; `d ≤ 0 → 0.95`; `0 < d < 60 → 0.80 + 0.15 × (60 − d)/60`; no date → deck/preset configured retention (open-horizon). This value replaces the static one fed to the existing FSRS `next_states` — no new scheduling math. `ComputeExamSchedule` returns the retention + per-card interval preview.

- [ ] AC1 — exam date 90d out → desired_retention == 0.80. _(test-rust, ramp fn)_
- [ ] AC2 — exam date 30d out → 0.875. _(test-rust)_
- [ ] AC3 — exam date 0d/past → 0.95. _(test-rust)_
- [ ] AC4 — no exam date → configured preset value (no dynamic override). _(test-rust)_
- [ ] AC5 — review card, stable interval 60d: `ComputeExamSchedule` with date 90d out (dr=0.80) vs 30d out (dr=0.875) → interval(30d) < interval(90d). _(test-rust)_
- [ ] AC6 — `ComputeExamSchedule`, `SetExamDate`, and `GetExamDate` callable from Python after `just check`. _(test-py)_
- [x] AC7 — exam date round-trips through the sync-safe Settings note, clears cleanly, and does not write the legacy config key; legacy config remains a read fallback. _(test-rust)_
      **Done when:** exam date is a first-class synced object; retention ramps with days-to-exam; open-horizon fallback intact.

---

## A2 — Latency-aware "too-easy" defunding — rote cards only (SPOV 1/2) · P1 · _shipped_ · depends: A6

**Design principle (locked):** latency-defunding is a rote-fluency mechanism only. A2 fires **only** on cards tagged `cog::rote`; `cog::applied` (critical-thinking) cards are never latency-defunded (their readiness is measured on the Performance path, A4). Grounded in Sweller element-interactivity, ICAP, and the Kornell/Bjork fluency illusion.
**Confidence decoupling (fixes the A2↔B1 phase-order bug):** the pre-reveal confidence A2 reads is stored in `card.custom_data` (latest) at answer time. The **reviewer UI (B1) supplies it**, but A2 depends only on the `custom_data` convention (a Phase-A data-model contract), **not** on B1's UI. Phase-A tests **seed** the confidence scalar directly — A2 is fully testable in Phase A with no Phase-B dependency.
**Behavior (pinned):** on a `cog::rote`, stable card (interval ≥ 21d floor; never new/learning), when correct (Good/Easy) AND latest recorded confidence == Confident AND `taken_millis` < 0.5 × baseline → apply a pre-FSRS desired-retention reduction (−0.05, floored 0.70) for that card's `next_states` call (longer interval _through_ FSRS, not a post-hoc multiplier — FSRS has no post-multiply hook) and set `cd.te=1`. Baseline = median of trailing-5 `taken_millis` once ≥3 own reps, else the `ankountant.latency.rote` cohort median (EMA in `col` config). Slow/unconfident/incorrect clears `te`.

- [x] AC1 — `cog::rote` stable card, ≥3 reps (trailing-5 median M), answered Good + confidence Confident in <0.5·M → FSRS desired-retention input reduced (longer next interval than slow-Good) and `custom_data.te==1`. _(test-rust)_
- [x] AC2 — `cog::applied` card, fast+correct+Confident → NO defunding, no flag. _(test-rust)_
- [x] AC3 — new/learning rote card (below 21d floor), fast+correct → no defunding. _(test-rust)_
- [x] AC4 — rote card with <3 own reps → cohort median used as baseline; feature still fires. _(test-rust)_
- [x] AC5 — flagged card, next answer slow/unconfident/Again → `custom_data.te` cleared. _(test-rust)_
- [x] AC6 — `custom_data` stays within 100-byte / 8-byte-key limit. _(test-rust)_
      **Done when:** fast+correct+confident on a stable rote card lengthens its interval through FSRS and is flagged; applied cards provably untouched. _If the night runs short this feature is cut first (see `build-spec.md`); if cut, it is marked `parked` in feature_list.json so it does not gate the contract._

---

## A3 — Confusion-set queue builder (SPOV 4) · P0 · depends: A6, A8

**Behavior (pinned):** new RPC `BuildConfusionQueue(section)` returns a label-stripped, interleaved ordering: (a) mixes items from different `ds::` tags within the same confusion set (never blocks by tag); (b) orders sets by discrimination weakness — lowest per-set accuracy first, computed by grouping Attempt Log notes (mode=confusion) by `confusion_set_id` and taking mean correctness; (c) the client-facing prompt payload omits topic/category/deck labels. CONFUSABLE map in `col` config `ankountant.confusable.FAR`.

- [ ] AC1 — set {operating_lease, finance_lease}: returned queue never places 3+ consecutive items of the same tag. _(test-rust)_
- [ ] AC2 — set X at 40% vs set Y at 80% historical accuracy (seeded Attempt Log) → all X items rank before Y items. _(test-rust)_
- [ ] AC3 — items carry the schema tag internally but the client-facing prompt/DTO has no populated category/deck-label field. _(test-rust on the DTO)_
- [ ] AC4 _(non-gating perf note, not a contract assertion)_ — on the FAR seed (~30 notes) the call returns quickly (<100 ms target); 50k-scale is deferred (no `notes.tags` index yet). Do not gate ship on timing.
      **Done when:** a mixed, weakness-ordered, label-free queue is produced from tagged notes.

---

## A4 — Mastery + gap query (SPOV 5) · P0 · depends: A6, A7, A8

**Behavior (pinned):** new RPC `GetReadiness(section)`. Per topic (confusion set / `ds::` tag): `memory` = recall accuracy over the trailing 30 days on the study pile (0–1; requires ≥5 in-window reps else `null`/"insufficient"); `performance` = accuracy on the **sealed** bank (MCQ correctness + TBS partial-credit, weighted 50/50 for FAR, 0–1); `gap = memory − performance`. Rollup cached in `col` config `ankountant.readiness.FAR`.

- [ ] AC1 — ≥5 trailing-30d study reps + sealed attempts for a topic → returns memory, performance, gap == memory − performance. _(test-rust)_
- [ ] AC2 — performance computed ONLY from sealed-bank (A7) attempts; study-pile items never contribute (seed a study-only topic → performance reflects no leakage). _(test-rust)_
- [ ] AC3 — TBS attempts contribute their partial-credit fraction (not pass/fail) to performance. _(test-rust)_
- [ ] AC4 _(non-gating perf note)_ — whole-section call is fast on the FAR seed (<100 ms target); 50k-scale deferred.
      **Done when:** one call yields per-topic Memory, Performance, and the gap, firewall intact.

---

## A5 — Abstain rule (SPOV 5) · P0 · depends: A4

**Behavior (pinned):** part of `GetReadiness`. **Abstain when** sealed attempts < 20 (strict) OR coverage < 60%, where coverage = (sets with ≥1 sealed attempt) / (sets defined in the CONFUSABLE map) — a zero-attempt set counts against coverage. When not abstaining: readiness = a Wilson 95% interval on sealed Performance accuracy, projected through the ADR 0005 CPA scaled-score transform (0–99, pass line 75). Response fields include `band_low`, `band_high`, `point_estimate`, `confidence`, `coverage`, `generated_at`, and factual `reasons`. The point estimate is only the center of the band; UI must never render it as a standalone score. `confidence` = Med (20–49) / High (≥50); below 20 abstains.

- [ ] AC1 — <20 sealed attempts → `abstain==true`, reason "insufficient volume". _(test-rust)_
- [ ] AC2 — ≥20 attempts but coverage <60% → `abstain==true`, reason "insufficient coverage". _(test-rust)_
- [ ] AC3 — sufficient volume+coverage → `abstain==false`, CPA-scale `band_low < band_high`, `point_estimate`, `coverage`, `generated_at`, factual `reasons`, and confidence level. _(test-rust)_
- [ ] AC4 — fixed accuracy on 40 attempts (≥60% coverage) → CPA band [L₁,H₁]; halve to 20 attempts same accuracy → [L₂,H₂] with (H₂−L₂) > (H₁−L₁). _(test-rust)_
      **Done when:** readiness is a band that abstains honestly under thin evidence.

---

## A6 — Deep-structure + cognitive-demand tags (SPOV 4) · P0 · depends: —

**Behavior (pinned):** two tag namespaces on notes/cards, both sync natively and are queryable:

- `ds::…` — deep-structure/schema tag (e.g. `ds::lease::finance`). `confusion_set_id` is **not** stored per note; it is derived from the tag via the CONFUSABLE map (`col` config `ankountant.confusable.FAR`): `{ "<set_id>": { "tags": ["ds::lease::finance","ds::lease::operating"], "treatments": [...] } }`.
- `cog::rote` | `cog::applied` — cognitive-demand tag on cards (gates A2; this is where A2's gate is defined and grounded).
- [ ] AC1 — seed notes carry `ds::…` tags; a query returns all notes for a given tag. _(test-rust)_
- [ ] AC2 — the CONFUSABLE map resolves each `ds::` tag to exactly one `set_id` (no tag in two sets). _(test-rust)_
- [ ] AC3 — cards carry `cog::rote`/`cog::applied`; a query filters by it. _(test-rust)_
- [ ] AC4 — tags round-trip unchanged through save/reopen (sync-safe). _(test-rust)_
      **Done when:** notes/cards are queryable by deep structure, confusion set, and cognitive demand.

---

## A7 — Sealed performance bank / firewall (SPOV 5) · P0 · depends: —

**Behavior (pinned):** a dedicated deck (e.g. `Ankountant::Sealed::FAR`) whose cards are held permanently in `CardQueue::Suspended` (`queue = -1`). The standard queue-builder already excludes suspended cards, so the firewall is enforced by the existing scheduler, not by convention (verify empirically via AC1, not by pinning a code path). Sealed items are surfaced only via `BuildConfusionQueue` / TBS Performance flows.

- [ ] AC1 — sealed-bank cards never appear in `GetQueuedCards` for normal study. _(test-rust)_
- [ ] AC2 — a sealed item and a study item on the same topic are distinct notes (no shared note id) — physical firewall. _(test-rust)_
- [ ] AC3 — attempts on sealed items feed Performance (A4) but not the FSRS study schedule. _(test-rust)_
      **Done when:** the study scheduler provably cannot serve sealed items.

---

## A8 — Attempt Log note type / sync-safe data path (Option A) · P0 · depends: —

**Behavior (pinned):** a hidden "Attempt Log" note type in a never-queued deck. **Precedent (corrected):** the iOS Reader stores books as ordinary notes (`ReaderBookClient*`) and reading progress as a `col` config manifest (`ReaderProgressSyncClient*`). Option A reuses the notes-as-storage half. One note per attempt; fields: `item_ref` (attempted note id), `confusion_set_id`, `mode` (confusion|tbs), `confidence` (guess|unsure|confident), `latency_ms`, `outcome_json` (per-step credit for TBS; correct/incorrect for MCQ), `ts`. **Replaces the sync-breaking "confidence column on revlog."** Native FSRS revlog still logs recall reps (rating + `taken_millis`). Recall-mode latest confidence mirrors into `card.custom_data` (this is the scalar A2 reads). The 3-score source of truth is the Attempt Log.

- [ ] AC1 — a confusion answer creates one Attempt Log note with confidence, latency_ms, confusion_set_id, outcome. _(test-rust)_
- [ ] AC2 — a TBS attempt creates one Attempt Log note whose `outcome_json` holds per-step credit. _(test-rust)_
- [ ] AC3 — Attempt Log notes never returned by the normal study queue. _(test-rust)_
- [ ] AC4 — `PRAGMA table_info` for notes/cards/revlog is identical before and after writing attempts + save/reopen (no new table/column); attempts remain queryable. _(test-rust)_
      **Done when:** every gated attempt persists as a hidden note; no schema change; the 3 scores read from it. _(Real cross-device sync validation is a Phase 2b gate — no server in Phase 1.)_

---

## A9 — TBS note type, all 4 shapes (SPOV 6) · P0 · depends: —

**Behavior (pinned):** new note type `Ankountant TBS`. Fields: `tbs_type` (research|journal_entry|numeric|doc_review), `prompt`, `exhibits_json`, `steps_json` (ordered array; each step `{ id, answer_key, weight }`, weights default `1/N` equal, sum 1.0 — used for A10 partial credit), `schema_tag`, plus provenance fields `source_passage`, `gen_method`, `checker_status`. **Scope clarity:** provenance fields are **STORED** (in-scope MVP, forward-compat) but remain **UNPOPULATED** — field _population_ by an AI pipeline is Phase 2a (out of scope). The note type structurally holds all four shapes; **journal-entry + numeric are fully playable (B4); research-sim + document-review are storable but their playable surfaces are deferred** (`../PRD-tbs-shapes-future.md`).

- [ ] AC1 — the note type validates & stores a journal-entry TBS (multi-line steps) and a numeric TBS (per-cell steps). _(test-rust/test-py)_
- [ ] AC2 — `steps_json` supports N gradable steps each with answer key + weight. _(test-rust)_
- [ ] AC3 — a `doc_review` and a `research` TBS can be stored (not yet played) without schema change. _(test-rust)_
- [ ] AC4 — provenance fields exist and default empty (stored, unpopulated). _(test-rust)_
      **Done when:** one note type covers all four shapes; JE + numeric fully specified.

---

## A10 — TBS step-grading backend (SPOV 5/6) · P0 · depends: A8, A9

**Behavior (pinned):** new RPC `SubmitPerformanceAttempt(item_note_id, mode, submission_json, confidence, latency_ms)`. Grades against the TBS `steps_json` answer key, returns per-step results + total credit fraction, and persists the Attempt Log note (A8) in the same transaction. `mode=confusion` = single "which treatment?" choice; `mode=tbs` = JE/numeric per-step. JE grading = per-line exact match on (account, debit/credit, amount) with configurable amount tolerance; numeric = per-cell exact/tolerance; total = Σ(step weight × step correct). This is the "real Rust change" alongside the scheduler.

- [ ] AC1 — 4-line JE, equal weights (0.25 each), lines 1–3 match and line 4 amount wrong → `per_step == [ok,ok,ok,wrong]`, `total_credit == 0.75`. _(test-rust)_
- [ ] AC2 — a single wrong amount marks only that line wrong (partial credit), not the whole item. _(test-rust)_
- [ ] AC3 — numeric TBS grades per-cell with configured tolerance. _(test-rust)_
- [ ] AC4 — every `SubmitPerformanceAttempt` call writes exactly one Attempt Log note (A8). _(test-rust)_
- [ ] AC5 — callable from Python + TS after `just check`. _(test-py)_
      **Done when:** TBS/confusion attempts are step-graded, persisted, and feed Performance.

---

## Worked examples (for the Build generator)

- **A10 AC1 — TBS partial credit.** Input: `steps_json` = 4 JE lines, weight 0.25 each; `submission_json` matches lines 1–3, line 4 amount wrong. Output: `{ steps:[{id,correct:true,weight:0.25}×3, {id,correct:false,weight:0.25}], total_credit: 0.75, attempt_note_id: <n> }`; one Attempt Log note written (`mode=tbs`, per-step array, confidence, latency).
- **A5 — abstain→band.** 12 sealed attempts → `{abstain:true, reason:"insufficient volume", coverage, reasons}`. Add to 25 attempts across ≥60% of sets → `{abstain:false, band_low, band_high, point_estimate, confidence:"Med", coverage, reasons}` on the CPA 0–99 scale. Doubling attempts narrows the band.
- **A1 — ramp.** days_to_exam 90 → 0.80; 60 → 0.80; 30 → 0.875; 0 → 0.95; none → configured preset (e.g. 0.90).
