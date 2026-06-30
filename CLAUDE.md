# Claude Code Configuration

> **Note:** Every command you need — building, running, testing, linting,
> formatting — is defined as a recipe in the project `justfile`. Run
> `just --list` to see them. Do not invoke `./ninja`, `./run`, or scripts
> under `./tools` directly — use the `just` recipes instead.

## Project Overview

Anki is a spaced repetition flashcard program with a multi-layered architecture. Main components:

- Web frontend: Svelte/TypeScript in ts/
- PyQt GUI, which embeds the web components in aqt/
- Python library which wraps our rust Layer (pylib/, with Rust module in pylib/rsbridge)
- Core Rust layer in rslib/
- Protobuf definitions in proto/ that are used by the different layers to
  talk to each other.

## Architecture Map

Anki is layered: a **Rust core** (`rslib/`) holds all collection/scheduling/sync
logic; **Python** (`pylib/anki/`) wraps it over a PyO3 FFI bridge and the
**PyQt6 desktop GUI** (`qt/aqt/`) drives it; the **Svelte/TypeScript frontend**
(`ts/`) renders study/editor/config pages embedded in Qt webviews; and
**`proto/`** is the Protobuf contract that wires all three together.

Each subsystem has a nested `CLAUDE.md` — read it before working in that area:

- **`rslib/`** — Rust core: collection, notes, decks, search, sync, media.
  Scheduling lives in `rslib/src/scheduler/` → read
  **`rslib/src/scheduler/CLAUDE.md`** when touching queues, due dates, FSRS, or
  `answer_card`.
- **`proto/`** — RPC + message definitions (`proto/anki/*.proto`), the source of
  truth for all layers → read **`proto/CLAUDE.md`** before adding/changing any
  service, method, or message.
- **`pylib/anki/`** — Python API: `Collection`, scheduler, managers; `_backend.py`
  is the FFI bridge → read **`pylib/anki/CLAUDE.md`** when adding backend-backed
  Python methods or DB access.
- **`qt/aqt/`** — desktop GUI: main window, webview embedding, `operations/`
  (CollectionOp/QueryOp), `mediasrv.py`, browser, editor → read
  **`qt/aqt/CLAUDE.md`** for dialogs, hooks, `.ui` forms, or undoable mutations.
- **`ts/`** — Svelte/TS pages (`routes/`, `reviewer/`, `editor/`) served at
  `localhost:40000/_anki/pages/` → read **`ts/CLAUDE.md`** for frontend
  components, the backend bridge, or e2e tests.

### Cross-language data flow

`proto/anki/*.proto` is the single contract. Editing a `.proto` regenerates, in
lockstep: the Rust service dispatch (compiled into `rslib/src/services.rs`), the
Python wrappers (`out/pylib/anki/_backend_generated.py`, surfaced via the
hand-written `pylib/anki/_backend.py`), and the TS callers
(`out/ts/lib/generated/backend.ts`, imported as `@generated/backend`). Generated
code lives under `out/` — never edit it. Because the layers index into generated
dispatch by service/method order, a `.proto` change needs a full **`just check`**;
`cargo check` alone regenerates only Rust and leaves Python/TS stale.

## Running Anki

To build and run Anki in development mode:

```
just run
```

This builds pylib and qt, then launches Anki with debugging enabled. Web
views are served at http://localhost:40000/_anki/pages/ (e.g.,
deckconfig.html). Use `just run-optimized` for a release-optimized build.
For live-reloading during web development, run `just web-watch` in a
separate terminal — it monitors ts/, sass/, and qt/aqt/data/web/ and
auto-rebuilds on changes (`just rebuild-web` triggers a one-off rebuild).

## Building/checking

`just check` will format the code and run the main build & checks.
Please do this as a final step before marking a task as completed.

Run `just` (or `just --list`) to see all available commands.

## Quick iteration

During development, you can build/check subsections of our code:

- Rust: `cargo check`
- Python: `just lint` (runs mypy/ruff), and if wheel-related, `just wheels`
- TypeScript/Svelte: `just lint` (includes check:svelte and check:typescript)

Language-specific tests are also available: `just test-rust`, `just test-py`,
`just test-ts`. Use `just fmt` / `just fix-fmt` for formatting and
`just fix-lint` to auto-fix lint issues.

TypeScript/Svelte browser e2e tests live in `ts/tests/e2e/` and run with
`just test-e2e`. The harness launches a temporary Anki instance and drives
mediasrv pages with Playwright's Chromium.

Be mindful that some changes (such as modifications to .proto files) may
need a full build with `just check` first.

## Build tooling

`just` recipes wrap our build system (implemented in build/), which takes
care of downloading required deps and invoking our build steps. See the
project `justfile` for the full set of recipes.

## Translations

ftl/ contains our Fluent translation files. We have scripts in rslib/i18n
to auto-generate an API for Rust, TypeScript and Python so that our code can
access the translations in a type-safe manner. Changes should be made to
ftl/core or ftl/qt. Except for features specific to our Qt interface, prefer
the core module. When adding new strings, confirm the appropriate ftl file
first, and try to match the existing style.

## Protobuf and IPC

Our build scripts use the .proto files to define our Rust library's
non-Rust API. pylib/rsbridge exposes that API, and \_backend.py exposes
snake_case methods for each protobuf RPC that call into the API.
Similar tooling creates a @generated/backend TypeScript module for
communicating with the Rust backend (which happens over POST requests).

## Fixing errors

When dealing with build errors or failing tests, invoke 'check' or one
of the quick iteration commands regularly. This helps verify your changes
are correct. To locate other instances of a problem, run the check again -
don't attempt to grep the codebase.

## Ignores

The files in out/ are auto-generated. Mostly you should ignore that folder,
though you may sometimes find it useful to view out/{pylib/anki,qt/\_aqt,ts/lib/generated} when dealing with cross-language communication or our other generated sourcecode.

## Installer

The code for our Briefcase-based installer is in qt/installer, with
separate templates for each platform (mac-template/, linux-template/,
windows-template/).

## Rust dependencies

Prefer adding to the root workspace, and using dep.workspace = true in the individual Rust project.

## Rust utilities

rslib/{process,io} contain some helpers for file and process operations,
which provide better error messages/context and some ergonomics. Use them
when possible.

## Rust error handling

in rslib, use error/mod.rs's AnkiError/Result and snafu. In our other Rust modules, prefer anyhow + additional context where appropriate. Unwrapping
in build scripts/tests is fine.

## Individual preferences

See @.claude/user.md

## grill-me skill

When using the grill-me skill in this repo, store ADRs in `docs_ankountant/adr/` (not `docs/adr/`). Store `CONTEXT.md` at the repo root as usual.
