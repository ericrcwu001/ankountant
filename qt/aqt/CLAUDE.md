# qt/aqt — PyQt6 desktop GUI

Read before editing qt/aqt. This is the PyQt6 desktop app that embeds the
Svelte/TypeScript web components and drives the collection via typed operations.

## What lives here

- `__init__.py` — app entry: `run()` → `_run()` builds `AnkiApp`/`AnkiQt`; dialog manager.
- `main.py` — `AnkiQt(QMainWindow)`: UI setup, profile load, state machine (`moveToState`: deckBrowser/overview/review).
- `webview.py` — `AnkiWebView`/`AnkiWebPage` (QWebEngine): bridge script (`pycmd`), `AnkiWebViewKind`, `load_sveltekit_page()`, `load_ts_page()`.
- `mediasrv.py` — Flask + waitress HTTP server: serves bundled web assets, legacy pages, SvelteKit pages, media; `PageContext` security policy.
- `operations/` — `CollectionOp` (undoable mutations) and `QueryOp` (read-only async) in `__init__.py`; per-domain ops in `card.py`, `deck.py`, `note.py`, `tag.py`, `scheduling.py`, `notetype.py`, `collection.py`.
- `browser/` — `browser.py` dialog; `table/` (`model.py`, `state.py`, `table.py` — Card/Note state machine); `sidebar/` (`tree.py` drag-drop deck/tag hierarchy).
- `editor.py`, `toolbar.py`, `reviewer.py`, `deckoptions.py` — major web-embedding views.
- `forms/` — 42 `.ui` Qt Designer XML files, each with a checked-in `.py` shim re-exporting the generated module (see codegen below).
- `data/web/` — Qt legacy web assets: SCSS (`css/`), TypeScript page handlers (`js/`: toolbar.ts, deckbrowser.ts, reviewer-bottom.ts, webview.ts), images, vendored JS.

## Entry points

- `aqt.run()` → `_run()` → `AnkiQt.setupUI()`.
- Dialogs via `aqt.dialogs.open("Browser", parent)`.
- `CollectionOp(parent, op_fn).success(cb).run_in_background()` for mutations.
- `QueryOp(parent=..., op=..., success=...).run_in_background()` for async reads.
- JS→Python: `pycmd(cmd, cb)` over the QWebChannel bridge.

## Gotchas

- Forms import from the synthetic `_aqt.forms.<name>_qt6` (e.g. `qt/aqt/forms/about.py` is just `from _aqt.forms.about_qt6 import *`). `_aqt` is generated into `out/` for namespace isolation — it does not exist until the build runs.
- Codegen (forms, hooks, colors/props) is mandatory before type checking: `just lint`/`just check-py` fail until the build has produced `out/qt/_aqt/`. Run `just check` to trigger it.
- `CollectionOp` runs its op in a background thread — do NOT touch UI or call `browser.selectedCards()` inside the op.
- `AnkiWebViewKind` controls QWebEngineProfile routing and which views may reach the backend API — check the kind before expecting API access.
- Styling is injected post-load after the `domDone` signal; pages serve from `http://127.0.0.1:{port}/_anki/...` (port from `ANKI_API_PORT`).
- `mediasrv.PageContext` (e.g. untrusted media → `UNTRUSTED_MEDIA_CSP`) gates CSP and API access — user-content pages must use the untrusted context.
- Browser table redraws fully on the notes-mode flag change; `state.py` abstracts Card vs Note.

## Cross-references

- `operations/*` → `anki.collection` `OpChanges` protobuf types (from `proto/`).
- `mediasrv` web routes consume backend API types from `out/ts/lib/generated/` (protobuf-derived).
- `out/qt/_aqt/forms/*_qt6.py` ← `qt/aqt/forms/*.ui` via `qt/tools/build_ui.py`.
- `out/qt/_aqt/hooks.py` ← `qt/tools/genhooks_gui.py` (`gui_hooks.py` API).
- `out/qt/_aqt/colors.py`, `props.py` ← `ts/sass/_root-vars.scss` via `qt/tools/extract_sass_vars.py`.
- All of the above orchestrated by `build/configure/src/aqt.rs` (Ninja generator).

## Ankountant work

Standard Anki fork — no ankountant-specific changes here yet. Add new collection
mutations as a `CollectionOp` in `operations/` (use `QueryOp` for read-only async).
New dialogs: either a `.ui` form + generated code, or embed an `AnkiWebView`
SvelteKit page and register its route/`PageContext` in `mediasrv.py`. After `.proto`
or codegen-affecting changes, run a full `just check` before type checking.
