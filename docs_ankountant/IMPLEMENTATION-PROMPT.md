# One-shot implementation prompt

> Paste the block below into a fresh Agent-mode session at the repo root. It references the four source-of-truth docs and is scoped so a single run can land both the Ledger UI and the one-window Ankountant shell.

---

You are implementing two coupled changes in the Ankountant repo (branch `main`): the **Ledger design system** and a **single-window Ankountant navigation shell**. Four docs are the source of truth — read them fully before editing, and follow them exactly:

1. `docs_ankountant/design-system.md` — the agreed system (the "what/why").
2. `docs_ankountant/design-tokens.json` — canonical token values (the ONLY place hexes/sizes come from).
3. `docs_ankountant/design-system-implementation.md` — exact file-scoped edits for the UI (web + iOS), incl. two confirmed bugs.
4. `docs_ankountant/desktop-single-window-shell.md` — exact plan + prototype for the one-window shell.

## Guardrails

- Never edit anything under `out/` (generated). After token or codegen-affecting edits, run `just check` (it regenerates `out/qt/_aqt/colors.py`/`props.py` from the sass tokens).
- Do NOT invent color/size values — pull every value from `design-tokens.json`.
- Keep meaning-bearing tokens (`state.*`, `flag.*`, `accent.card`) intact.
- Preserve the flat Ankountant route URLs; use a SvelteKit route group `(ankountant)/` for the shared shell (no `mediasrv`/whitelist change).
- Work in the order below; run the per-phase verify before moving on. Do not mark done until `just check` is green.

## Phase 1 — Ledger tokens (web + Qt re-skin)

Per `design-system-implementation.md` §1–§1d: edit `ts/lib/sass/_vars.scss` (neutrals → cool slate + off-black `#0E0F13`; `fg.link`/`border.focus`/`shadow.focus`/`button.primary` → Ink Navy `#1F3A5F`/`#7FA6D4`; flatten `button.gradient.*` and `button.primary.gradient.*` by setting start=end; add `fg.error` and `fg.success`), `elevation.scss` (tint `#0B0D12`, lighter opacities), buttons (de-gradient + hover/active + tinted shadow + translateY(1px)), base font 15→16px, add `--space-*`, radius (control 8 / card 12 / container 16), `--font-sans`/`--font-mono`, and a `.tabular` numerals utility. Ensure Bootstrap `--bs-*` map to the new tokens.
Verify: `just check`; `just run` and confirm light + night-mode chrome looks navy/slate with flat buttons.

## Phase 2 — Ankountant page UI + bug fixes

Per `design-system-implementation.md` §2–§3: apply the type scale + tabular numerals to the three pages; make the score dashboard use neutral-ink scores + a navy Readiness band + an abstain state; fix the two confirmed bugs — `Dashboard.svelte:94/98` (gap-warning row → danger tint `color.feedback.gapWarningBg` + defined `--fg-error`; keep the `.gap-warning` class) and `ConfusionMode.svelte:123/127` (`--fg-success`/`--fg-error`); enforce color-never-alone (icon + label per state).
Verify: `just check`; `just test-ts`.

## Phase 3 — Single-window Ankountant shell

Per `desktop-single-window-shell.md` §4–§5:

- Web: create `ts/routes/(ankountant)/+layout.svelte` (shell top bar: "← Decks" via `bridgeCommand("ankountant:exit")`, three tabs via `goto`, an `onMount` `window.__ankGoto` hook) and move the three `ankountant-*` route folders under `(ankountant)/` (URLs unchanged). Style with Ledger tokens.
- Qt: add `AnkiWebViewKind.ANKOUNTANT_SHELL` + include it in `_profileForPage` API-access tuple (`webview.py`); add `"ankountant"` to the `MainWindowState` Literal (`main.py:85`); create a persistent hidden `self.ankountant_web` in `mainLayout` with `set_bridge_command(self._ankountant_link_handler, self)`; add `_ankountantState(oldState, page="dashboard")` / `_ankountantCleanup` / `_ankountant_link_handler` (exit → `moveToState("deckBrowser")`); hide/show `self.web`+`bottomWeb`+`toolbarWeb` appropriately; repoint `_setup_ankountant_menu` actions to `self.moveToState("ankountant", <page>)`; add an `Esc`→Decks shortcut. Stop the menu from opening the old `QDialog`s.
  Verify: `just check`; `just run` → each menu item switches the main window (no new OS window), tabs switch without reload, "← Decks" returns, backend data still loads.

## Phase 4 — iOS Ledger theme (same source of truth)

Per `design-system-implementation.md` §4: single navy `Palette` (light/dark, add `surfaceInset` + `onAccent` + `stateNew/Learn/Review`, sRGB-pinned hex); collapse `Theme{vivid,muted}` and update `AppearanceSettingsView.swift` + the 3 `AnkountantThemeTests` files; `ThemeManager` → `@Observable @MainActor` (drop `@unchecked Sendable`); move `AnkountantTypography/Spacing/Modifiers` into the `AnkountantTheme` package; add `AnkountantRadius`/`AnkountantElevation`(from `palette.shadow`)/`AnkountantMotion`; Dynamic Type type ramp (tracking on display only) + `.numeric`/`.dataCell`; 8px controls; align widget colors to tokens.
Verify (macOS): `cd ios && swift build` and `swift test`; then `xcodebuild build -project AnkountantApp/AnkountantApp.xcodeproj -scheme AnkountantApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'`.

## Definition of done

All four phases' verifies pass; `just check` green; no `out/` edits; acceptance checklists in `desktop-single-window-shell.md` §8 and the token edits in `design-system-implementation.md` satisfied. Summarize what changed per phase and note anything you could not complete (e.g. iOS if no macOS toolchain in this environment).
