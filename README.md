# Ankountant

**A CPA-exam study app, forked from [Anki](https://apps.ankiweb.net), rebuilt around three honest signals: _Memory_, _Performance_, and _Readiness_.**

Ankountant ships two clients on one shared Rust core — a cross-platform desktop app (PyQt) and a native iOS app (Swift) — both driving the same forked `rslib/` engine.

## The problem

Passing a dated, high-stakes exam is not the same problem as remembering something forever.

Anki is the best spaced-repetition tool ever built, but its scheduler (FSRS) is trained to minimize _lifelong_ review cost at a fixed ~90% retention target. It has no finish line, no exam date, and it rewards exactly the behavior that makes candidates fail: comfortable, high-frequency review that _feels_ like progress. Decades of learning science say fluency is a misleading signal — the confidently-wrong student who drops a weak topic because it feels easy is the one who fails.

The CPA exam makes this concrete. It's one four-hour sitting on a date you choose inside a 30-month window; passing is a scaled **75 on a 0–99 scale** (not 75% correct), and roughly **half of all section attempts fail every year**. The hardest sections (FAR, BAR, ~42% pass) are precisely the ones that test _which standard applies_, not raw recall — and task-based simulations, which a flashcard can't represent, are ~half of every section's score.

## What Ankountant does differently

Ankountant separates three things every candidate conflates, and measures each one honestly:

### 1. Memory — _can you recall the fact?_

A **deadline-anchored scheduler**: the exam date is a first-class object, and intervals are computed _backward_ from it so recall peaks on the day that counts, not indefinitely. Every review captures an **answer and a confidence before the reveal** (rewarding effortful retrieval over streaks), and uses answer latency — a signal Anki records but ignores — to push genuinely easy cards out hard and reclaim those minutes for weak topics. Effort early, consolidation late; the single dial is days-to-exam.

### 2. Performance — _can you apply it to a question you've never seen?_

Topic decks hand you the category for free — open the "Leases" deck and you already know it's a lease question. Ankountant replaces the deck with the **confusion set** as its core primitive: label-stripped _"which treatment applies?"_ gates that train discrimination among confusable standards. **Task-based simulations become a first-class, step-graded review mode** with partial credit per step, instead of being forced into the one-recall/one-button flashcard model.

### 3. Readiness — _what would you score today?_

Scoring readiness on cards you already drilled is just measuring recall again. Ankountant firewalls a **sealed, never-studied item bank** per topic and reports Readiness as a **calibrated score range with a confidence level** on the real 0–99 scale — and it **abstains** when the evidence is too thin to support even a range. A confident number with nothing behind it is not a prediction.

## Current UI

The desktop home screen is now a summit-style CPA dashboard: a navy app rail, a white countdown/readiness rail, and a five-section readiness range for FAR, AUD, REG, TCP, and ISC with topic drill-ins for the active section. The desktop workspace also mounts the Readiness dashboard, confusion practice, the four-shape TBS shell, research simulation, document review, authoritative literature, stats, add, and browse panes.

The iOS companion mirrors the same CPA flow natively with Summit Home, native review, Simulations, Reader/dictionary, Browse and note editing including image occlusion, Analytics, Sync/import, Settings, and WidgetKit due-count widgets. Review opens as a full-screen flow from Home or deck detail; the bottom navigation is Home, optional Reader, Browse, Analytics, and More.

## Grounding

Every design decision above traces to peer-reviewed cognitive and psychometric research — the testing effect, spacing, interleaving, cognitive load, calibration, item-response theory, and selective prediction. The full research foundation, spiky points of view, and source tree live in **[`docs_ankountant/brainlift.md`](./docs_ankountant/brainlift.md)**.

## AI: grounded card generation and optional feedback

Ankountant's shipped CPA question-bank content is generated only by a **build-time** pipeline — never live during grading, scheduling, or readiness scoring. It's the honest way to reach exam-scale coverage without hand-authoring 50,000 cards.

The runtime study loop remains deterministic for correctness, scheduling, and Readiness. Optional **Learning Feedback** may call OpenAI during review or simulations when configured with a user API key, but it is tutoring feedback only: it does not decide correctness, change scores, or alter scheduling.

**What we built.** A 12-stage retrieval-augmented generation (RAG) tool (`tools/cardgen/`, isolated from the app): ingest public/licensed CPA sources → chunk + quality-filter → embed into LanceDB (vector + BM25) → hybrid retrieve + rerank → generate with OpenAI `gpt-5-mini` **constrained to the retrieved passage** → deterministic self-check → an **independent 3-bucket judge** (a different provider/model — Cursor subagents — from the generator) → leakage + dedup gates → emit ordinary Anki notes (`.apkg`). Every shipped card carries provenance: the verbatim `source_passage`, its `source_id`/`locator` citation, the full `gen_method` (model, prompt version, retrieval config, index hash, seed), and a `checker_status`.

**Why.** Two rules drive it: _provenance or it doesn't count_, and _a wrong fact is worse than no card_. Grounding every card in a named source makes it traceable; the independent judge blocks wrong cards **before** a student sees them (cutoff fixed in advance — ship only `correct + useful`), and the judge is itself **calibrated against a gold set** — the build halts if it can't catch planted-wrong cards; a pre-registered A/B/C shows hybrid retrieval **beats** plain keyword and vector search. Because it's build-time only, the app runs fully with **AI switched off**, and cards are just data — no new tables, so they sync unchanged to the phone.

**What we skipped (on purpose).** No runtime/live card generation, no chatbot, and no model-driven grading: TBS/MCQ correctness stays deterministic and rule-based. `proof3` is the bounded live RAG proof; `tmpl4` is the current importable template deck; a full **unique** 50k grounded bank is still deferred until the corpus is much larger. The repo does include a sharded **stress-test** pack that duplicates the current bank to 51k+ notes for loader/performance testing; it is not new study material.

**Current cardgen artifacts.** RAG proof (`proof3`): 300 targeted → 263 generated (37 declined rather than fabricate) → judged **181 correct+useful / 70 wrong / 12 bad-teaching** → **161 vetted cards shipped** after leakage (0 leaks) + dedup. Beat-the-baseline **PASS**: hybrid faithfulness 0.742 vs BM25 0.608 / vector 0.592 (n=120). Judge calibration: **100% of 182 gold positives passed, 100% of 36 planted negatives caught**. Importable template deck (`tmpl4`): **325 shipped**, 1 wrong blocked, 0 leakage. Scale-test pack: `just cardgen-stress` writes `stress_bank_part*.apkg` shards tagged `stress` / `dup::<n>` for the desktop "50k Stress Test" loader. Full write-up: **[`docs_ankountant/rag/RAG_RUN_RESULTS.md`](./docs_ankountant/rag/RAG_RUN_RESULTS.md)** · template deck: **[`docs_ankountant/rag/TEMPLATE_DECK_RESULTS.md`](./docs_ankountant/rag/TEMPLATE_DECK_RESULTS.md)** · visual report: **[`docs_ankountant/rag/rag-ai-card-generation.html`](./docs_ankountant/rag/rag-ai-card-generation.html)** · design rationale: **[ADR 0009](./docs_ankountant/adr/0009-rag-cardgen-lean-stack-cursor-judge-tier-b.md)**.

## Architecture

`proto/anki/*.proto` is the single contract every client dispatches into.

- **`rslib/`** — Rust core (collection, notes, decks, search, sync, media, scheduling). Ankountant domain logic lives in `rslib/src/ankountant/`, with scheduler integration under `rslib/src/scheduler/`.
- **`pylib/` + `qt/aqt/`** — Python API over a PyO3 bridge and the PyQt desktop GUI.
- **`ts/`** — Svelte/TypeScript pages served to the embedded webviews.
- **`ios/`** — native SwiftUI client consuming a compiled `.xcframework` build of `rslib/` over a C FFI.

## Install

Want to just run Ankountant? Prebuilt desktop apps and iOS build instructions are in **[INSTALL.md](./INSTALL.md)**:

- **Desktop (macOS)** — download the `.dmg` from the [Releases page](https://github.com/ericrcwu001/ankountant/releases), including how to open the unsigned build past Gatekeeper (right-click → Open, or Privacy & Security → Open Anyway).
- **iOS** — build and run on your iPhone with Xcode, signed with your own Apple ID / development team.

## Getting started

Every task — building, running, testing, linting, formatting — is a [`just`](https://github.com/casey/just) recipe. Run `just --list` to see them all.

```bash
just run       # build pylib + qt and launch the desktop app
just check     # format, build, and run the full checks (do this before shipping)
just test-rust # run the Rust test suite
```

See [Development](./docs/development.md) for details, and the [Contribution Guidelines](./docs/contributing.md) to contribute.

## Built on Anki

Ankountant is a fork of [Anki](https://github.com/ankitects/anki) by Damien Elmes and contributors. We inherit its engine, its cross-device sync, and its AGPL-3.0 license. Enormous credit to the upstream project and everyone in [CONTRIBUTORS](./CONTRIBUTORS).

## License

Distributed under the same license as Anki: [LICENSE](./LICENSE).
