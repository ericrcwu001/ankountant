# Desktop single-window Ankountant shell

> Status: **Implemented** · Owner: eric · Last updated: 2026-07-03
>
> The desktop app now launches into one PyQt main window with an embedded Ankountant SvelteKit shell. The shell matches the summit-dashboard direction: a navy app rail, white countdown/readiness rail, and FAR topographic mastery canvas.

## Current shape

- `qt/aqt/main.py` still owns the classic Anki state machine for Decks, Overview, and Review.
- `qt/aqt/workspace.py` wraps the classic home webviews and tool dialogs in a single docked workspace.
- The Ankountant shell is one persistent `AnkiWebView(kind=ANKOUNTANT_SHELL)` dock named `AnkountantShell`.
- `set_ankountant_fullscreen(True)` hides the native menubar, the top toolbar, and the dock tab strip so the shell fills the app window.
- `Ctrl+Shift+D` toggles back to the classic deck-management chrome.
- `Ctrl+Shift+H` returns to the Ankountant Home shell.

## Web routes

The flat public URLs are preserved because `qt/aqt/mediasrv.py` whitelists by first path segment:

- `/ankountant-home`
- `/ankountant-dashboard`
- `/ankountant-confusion`
- `/ankountant-tbs`
- `/ankountant-research`
- `/ankountant-doc-review`
- `/ankountant-stats`
- `/ankountant-workspace`

All of these live under `ts/routes/(ankountant)/`, so they share `+layout.svelte` without changing URLs. The layout provides the navy sidebar and registers `window.__ankGoto` so the existing shell webview can navigate client-side.

## Sidebar behavior

The sidebar is not decorative. It maps to existing features:

| Item       | Target                                                                |
| ---------- | --------------------------------------------------------------------- |
| Dashboard  | `/ankountant-home`                                                    |
| Study      | `/ankountant-workspace`                                               |
| Practice   | `/ankountant-confusion`                                               |
| Review     | `/ankountant-tbs`                                                     |
| Analytics  | `/ankountant-stats`                                                   |
| Bookmarks  | `/ankountant-workspace?initial=browse&mode=notes&search=tag%3Amarked` |
| Notes      | `/ankountant-workspace?initial=browse&mode=notes`                     |
| Flashcards | `/ankountant-workspace?initial=browse&mode=cards`                     |
| Settings   | `bridgeCommand("ankountant:prefs")` → `AnkiQt.onPrefs()`              |

`BrowsePane.svelte` reads `mode` and `search` launch parameters only for initial state. Once mounted, it keeps the same browser behavior: backend search, card/note mode, row actions, inline editing, find/replace, tags, flags, suspend, and delete.

## Qt bridge commands

Handled in `Workspace._ankountant_bridge()`:

- `ankountant:exit` raises the classic home dock.
- `ankountant:review` selects `Ankountant::Study::FAR` and enters the normal overview/review flow.
- `ankountant:stats` opens the existing stats tool.
- `ankountant:prefs` opens existing Preferences.
- `ankountant:nav:<page>` opens or navigates the shell to a known Ankountant route.

## Visual contract

The reference direction is implemented in:

- `ts/routes/(ankountant)/+layout.svelte` for the navy app rail and app-level navigation.
- `ts/routes/(ankountant)/ankountant-home/Home.svelte` for the white countdown/readiness rail and FAR mastery page.
- `ts/routes/(ankountant)/ankountant-home/SummitTopographic.svelte` and `topo.ts` for the topographic mountain map. The renderer uses layered SVG peak silhouettes, clipped contour paths, foreground/background depth ordering, and pass-line flags while keeping each topic tied to the live FAR readiness data.
- Topic detail cards are hover-toggled from the SVG flags. The map must not render a permanent default topic pop-up; leaving the flag clears the card.
- `ts/routes/(ankountant)/ankountant-home/far-topics.ts` for the live FAR topic projection onto the map.
- `ts/lib/sass/_vars.scss`, `_root-vars.scss`, `base.scss`, and button/elevation SCSS for Ledger tokens.

The main mastery area is intentionally unframed on the light canvas. The countdown/readiness rail remains a raised panel, and the mountain range should read as a layered topographic illustration, matching the supplied summit-topographic reference rather than a generic chart.

## Verification

Use project recipes only:

```bash
just test-ts
just test-e2e
just check
just run
```

After `just run`, visually inspect the full PyQt app, not only a browser render:

1. Confirm the launch surface is the Ankountant shell, not the classic Decks tab.
2. Confirm the dark sidebar, white metric rail, topographic map, pass line, flags, and legend match the summit reference.
3. Hover a topic flag and confirm its detail card appears; move off the flag and confirm the card disappears.
4. Click Dashboard, Study, Practice, Review, Analytics, Bookmarks, Notes, Flashcards, and Settings.
5. Confirm Study/Review still enter the existing collection-driven flows.
6. Toggle `Ctrl+Shift+D` to verify classic Decks/Add/Browse/Stats access is still available.
