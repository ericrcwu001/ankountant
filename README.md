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

## Grounding

Every design decision above traces to peer-reviewed cognitive and psychometric research — the testing effect, spacing, interleaving, cognitive load, calibration, item-response theory, and selective prediction. The full research foundation, spiky points of view, and source tree live in **[`docs_ankountant/brainlift.md`](./docs_ankountant/brainlift.md)**.

## Architecture

`proto/anki/*.proto` is the single contract every client dispatches into.

- **`rslib/`** — Rust core (collection, notes, decks, search, sync, media, scheduling). The deadline-anchored scheduler work lives under `rslib/src/scheduler/`.
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
