Read before editing ts.

The Svelte/TypeScript web frontend. Pages render client-side and are served by
the Qt/Anki backend at http://localhost:40000/_anki/pages/ (e.g.
deck-options.html). This is where new ankountant study UI lands.

## What lives here

- `routes/` — SvelteKit routes, one dir per page: `congrats/`, `deck-options/`,
  `graphs/`, `image-occlusion/`, `change-notetype/`, `import-csv/`,
  `import-anki-package/`, `import-page/`, `card-info/`, plus Ankountant pages
  under `routes/(ankountant)/` (`ankountant-home`, `ankountant-dashboard`,
  `ankountant-workspace`, `ankountant-confusion`, `ankountant-tbs`,
  `ankountant-research`, `ankountant-doc-review`, `ankountant-sync`,
  `ankountant-settings`, `ankountant-stats`).
- `reviewer/` — review session runtime (`index.ts`, `answering.ts`,
  `preload.ts`, `images.ts`); the card display loop, hooks, and state API.
- `editor/` — note field editor (NoteEditor, EditorField, contenteditable,
  toolbar, cloze buttons).
- `editable/` — contenteditable abstraction (ContentEditable.svelte, MathJax,
  frame-element) powering field editing.
- `html-filter/` — sanitize/parse card HTML before display (prevents XSS).
- `lib/components/` — reusable Svelte UI components (modals, buttons, inputs,
  containers).
- `lib/sveltelib/` — low-level composition helpers (event-store,
  dynamic-slotting, modal-closing, lifecycle-hooks).
- `lib/tslib/` — shared utilities (bridgecommand, i18n, nightmode, dom,
  shortcuts, platform), aliased as `@tslib`.
- `lib/generated/post.ts` — `postProto<T>()` backend bridge.
- `vite.config.ts`, `svelte.config.js`, `bundle_svelte.mjs` — build config.

## Entry points

- SvelteKit routes load via `routes/+layout.ts` (sets up i18n + nightmode).
- Legacy pages also export a `setupFn()` from their `index.ts`
  (`setupCongrats()`, `setupDeckOptions(deckId)`) for Qt embedding.
- `reviewer/index.ts` and `editor/index.ts` are bundled separately for Qt.

## Gotchas

- SSR/prerender are off (`ssr = false`, `prerender = false` in `+layout.ts`):
  routes are client-only. The static adapter emits JS/CSS to `../out/sveltekit`,
  not standalone HTML.
- Dual bundling: routes use the SvelteKit static adapter; legacy pages
  (congrats, deck-options, graphs) are also bundled via `bundle_svelte.mjs`
  (esbuild + SCSS) to `out/ts/`, and must keep working in both contexts.
- `bridgeCommand()` (`@tslib/bridgecommand`) is Qt-only — a no-op/throws in a
  plain browser. E2e tests gate on a supported flag.
- Reviewer hooks are mutable global arrays (`onUpdateHook`, `onShownHook` in
  `reviewer/index.ts`); they are cleared and repopulated on each Q/A.
- `preload.ts` waits up to ~800ms for fonts/stylesheets before revealing the
  card; MathJax renders after images load.

## Cross-references

- Backend RPC: `postProto<T>()` POSTs binary protobuf to `/_anki/{method}`
  against the Rust backend in `rslib/`. The `@generated/backend` module is
  codegen'd from `proto/` into `out/ts/lib/generated/` — rebuild after editing
  `.proto`. The `@generated` alias points at `../out/ts/lib/generated`.
- Qt: `qt/aqt/webview.py` loads bundled pages from `out/` and injects the
  bridgeCommand stub; `bridgeCommand()` routes through PyQt to Rust.
- Translations: `ftl/core` strings reach TS via auto-generated i18n types in
  `out/ts/lib/generated`. SCSS in `sass/` is shared with Qt.

## Ankountant work

Ankountant study UI lives in `routes/(ankountant)/`: the summit Home/readiness
map, Readiness dashboard, tiled workspace, confusion practice, TBS shell,
research simulation, document review, literature/search surfaces, sync,
settings, and stats. The pre-reveal confidence gate is implemented in
`reviewer/ankountant_confidence.ts`, exposed from `reviewer/index.ts`, persists
through `mutateNextCardStates` in `reviewer/answering.ts`, and is driven by
`qt/aqt/reviewer.py`. New RPCs come through `@generated/backend` / `postProto()`
from `proto/`.

## Dev loop

- `just web-watch` — monitors ts/, sass/, qt/aqt/data/web/ and auto-rebuilds.
- `just rebuild-web` — one-off rebuild + hot-reload of a running instance.
- `just test-ts` — TS/Svelte unit checks; `just lint` runs check:svelte +
  check:typescript.
- `just test-e2e` — Playwright e2e (`tests/e2e/`, e.g. `sanity.test.ts`)
  against a temporary Anki instance.
