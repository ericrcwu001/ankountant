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

- **Attempt-before-reveal + confidence capture (SPOV 2):** Change the reviewer flow so the student commits an answer + a confidence _before_ the back shows.
- **"Which treatment applies?" gate (SPOV 4):** A pre-step that requires picking the method/standard before computing anything.
- **3-score dashboard (SPOV 5 + SPOV 3):** Memory / Performance / Readiness, with the gap shown and the abstain message when data is thin. Readiness shown as the exam-day projection (as a range, not a point), not "today."

### AI Content Pipeline → Phase 2 (deferred; see Phase 2a)

All AI card-generation work lives in **Phase 2a**. It's a **build-time batch tool**, not a runtime app feature — the study loop never calls a model live — so the MVP ships on hand-authored / seed content and doesn't depend on it (the 1A "decouple build-time from runtime" split).

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
- The TBS note type must accommodate all four TBS shapes up front — research / journal-entry / numeric / document-review — even if only some are authored initially (RAG _generation_ of TBS items is Phase 2a).
- Interface-fluency sim: mimic the real exam's dual-skill environment (content + split-screen software with exhibits, a spreadsheet, and lit search) so candidates are not cold on the UI.

**⚠️ Sync constraint — where TBS attempt data lives (chosen: Option A; flagged, not yet built):**
Three items above quietly assume schema changes: "add an effort/latency field to the review log" (SPOV 2, Rust Engine), "Confidence value stored per review" (Data Model), and "a backend that accepts a structured / partial-credit score" (this section). Done as new SQLite columns or a `tbs_attempts` table, **they would break sync between iOS and desktop over AnkiWeb.** AnkiWeb only transports a fixed, hardcoded set of standard objects — notes, cards, notetypes, decks, deck configs, tags, revlog, and the `col` config JSON. It has _no_ mechanism to sync a custom table; the collection schema is force-downgraded to V18 on upload (so extra columns on `cards`/`notes`/`revlog` get stripped); and the sync protocol is capped at v11. Anything outside that fixed set is silently not replicated across devices.

- **Option A (chosen) — store each TBS attempt as its own hidden note.** Encode one attempt — its per-step partial credit, per-step latency, and the pre-reveal confidence — into the fields of a dedicated "TBS attempt log" note type, in a deck the scheduler **never** queues. This is the same trick the iOS Reader already uses to keep books/chapters as ordinary Anki notes, so it's proven to round-trip through AnkiWeb. Notes sync object-by-object with per-object USN tracking, so two devices merge cleanly (no last-writer-wins clobbering you'd get from cramming everything into one config blob). SPOV 5's "separate data path" then becomes a _logical_ separation — a distinct note type + tag, queried apart from the recall pile — not a physically separate table that breaks sync.
- **Where the small stuff rides along:** a couple of per-card scheduler scalars can go in `card.custom_data` (hard-limited to ~100 bytes, 8-byte keys); aggregate Memory / Performance / Readiness rollups can go in the `col` config JSON under a namespaced key (e.g. `ankountant.readiness.*`), the same channel the Reader uses for reading progress.
- **TOS caveat — decide before relying on AnkiWeb:** the model above keeps sync _technically_ working, but AnkiWeb's Terms do **not** permit third-party / unofficial clients (it recommends AnkiConnect for local access) and it reserves the right to suspend accounts. An Ankountant fork pointed at AnkiWeb is offside on policy even when the bytes flow fine. The sanctioned path for a custom client is a **self-hosted Anki sync server** (open-source, identical protocol). Using AnkiWeb specifically is a policy risk to clear, not an engineering one.

## Phase 2 (deferred) — AI content pipeline + cross-device sync & accounts

**Not MVP — build these only after the core study experience works** (deadline scheduler, the 3 review modes incl. TBS, the 3-score dashboard). Phase 1 ships on hand-authored / seed content and is local-first (one device studies fine with no server). Two Phase-2 workstreams follow — the AI content pipeline (2a) and cross-device sync + accounts (2b). Phase 1 is still built _under the sync-safe constraint above_ (Option A: TBS attempts as hidden notes; scores in `col` config JSON), so switching sync on later needs **no data-model rework** — the whole reason to hold the constraint now and defer the server.

### Phase 2a — AI content pipeline (offline, build-time batch tool)

The full RAG generation pipeline, deferred whole. Decoupled from the study loop by design (**Runs AI-off**): a build-time batch tool that pre-generates the deck; study / scheduling / scoring never call a model live — which is exactly why it can wait (the MVP studies pre-made / hand-authored cards).

> **📋 Fully planned:** the 50,000-card scale-up is specified in
> **[`rag/README.md`](rag/README.md)** (a cross-referenced doc set: sources &
> licensing, blueprint-driven taxonomy/allocation, the RAG stack, the generation
> pipeline, the quality/eval/baseline protocol, and provenance/output/ops).
> **Chosen stack (build-time Python batch, `tools/cardgen/`):** ingest
> public-domain / CC-licensed corpora (OpenStax, IRC, IRS pubs, PCAOB/SEC/GAO,
> AICPA Blueprints as taxonomy) → **LanceDB** (embedded vector + BM25) with
> **Voyage AI** embeddings → generate with **Anthropic Claude** (Sonnet bulk /
> Opus for hard TBS + flagged) → **independent LLM judge + human gold set**
> (3-bucket gate) → **Ragas** faithfulness + a **BM25/vector/RAG baseline A/B/C**
> → emit **ordinary Anki notes** (provenance fields populated) as an `.apkg`.
> Copyrighted standards (FASB ASC, GASB, AICPA questions) are **cited, never
> ingested** — the licensing firewall that keeps provenance defensible.

- **RAG card generator:** Pull from source docs (textbook chapters, notes, FASB/IRC) → generate full Q&A flashcards at scale, targeting the 50k deck. Every card stores the source passage it came from. (Assignment rule: AI output with no traceable source zeroes that section.)
- **RAG generates TBS items** — start with research + numeric (cleanly checkable), document-review later. _(TBS note-type coverage is a Phase 1 data-model item; generation lives here — the 2A split.)_
- **Quality checker:** A gold set of known-correct Q&A; run generated cards through it, report 3 counts (correct+useful / wrong / correct-but-bad-teaching). Set the passing cutoff _before_ looking; auto-block anything that fails. "A wrong fact is worse than no card."
- **Beat a baseline:** Show the RAG pipeline outperforms plain keyword/vector search on the eval (assignment requirement).
- **Leakage check:** Scan generated cards so none are near-copies of the sealed performance bank (keeps SPOV 5's firewall) or of the held-out test set.
- Treat ingested FASB/IRC text as untrusted (prompt-injection surface), but that is a guardrail, not a reason to limit generation.

> ⚠️ Assignment timing: several bullets cite assignment requirements/rules, so deferring the whole pipeline means those graded gates land in Phase 2 too. If the assignment has a deadline, confirm this ordering fits — this is the trade-off vs the earlier thin-slice option.

### Phase 2b — Cross-device cloud sync + accounts

Cloud sync is an ops/infra project, not core learning value, so it waits. **Two planes, two stacks (the deliberate split):**

- **Sync plane — self-hosted `anki-sync-server` on Oracle Cloud Always Free.** We already ship the server (the `anki-sync-server` crate in `rslib/sync/`, built from our own fork), so this is ops, not new code. Run it on an Oracle **Always Free** ARM VM (~2 OCPU / 12 GB RAM / 200 GB disk as of mid-2026 — genuinely free, not a 90-day trial), with **Caddy** in front for automatic Let's Encrypt TLS (a free DuckDNS subdomain or a cheap domain), because the iOS client's ATS requires valid HTTPS. Both clients already have the endpoint UI — desktop's custom sync URL, and iOS **Settings → Sync Server** — so pointing them at it is configuration, not code. Chosen over AnkiWeb because **AnkiWeb's TOS bars third-party / forked clients** (account-suspension risk); self-hosting is the sanctioned path and also lifts AnkiWeb's payload cap. Note: the self-hosted server still runs the standard protocol (v11 / schema V18), so it buys _policy_ freedom, not _schema_ freedom — Option A above still stands.
- **Accounts plane — Firebase.** User accounts / auth (and optionally the 3-score dashboard + analytics data) live on **Firebase**, separate from the sync server. The split is deliberate and required: Firebase is a fine accounts/auth backend but **cannot host the sync server** — it can't hold per-user SQLite on a persistent disk or keep the in-memory, multi-request sync session alive (a serverless-vs-stateful mismatch). So the stateful sync engine stays on the Oracle VM, and Firebase handles only the accounts layer the app also talks to.

**Scaling caveat (revisit before any public launch):** the built-in server authenticates against static `SYNC_USER1=user:pass` env vars on one small free VM — fine for personal use and a small pilot, but it does **not** scale to the thousands of B2C retakers the market SPOVs target. Real multi-tenant provisioning, per-user storage quotas, backups of `SYNC_BASE`, and abuse handling are a later infra step beyond this Phase 2 MVP-sync.
