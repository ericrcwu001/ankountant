# 0002. Web-based BSP tiling workspace for study surfaces

Status: Accepted
Date: 2026-07-01

2026-07-06 status update: superseded in part. The workspace now hosts
web-native Browse, Add, Stats, Literature, Research, and Doc Review panes in
addition to Dashboard, Confusion, and TBS. Classic Qt dialogs may still exist for
edge cases; Review remains the main classic runtime not mounted as a pane.

## Context

The desktop app let users "split screen" by dragging the Qt workspace tabs
(Add / Browse / Stats / Ankountant) into `QMainWindow` dock splits. That
experience was unsatisfying and had concrete gaps:

- A pane dragged out of the North tab strip into its own split region had
  **neither a tab nor a title bar** (`WorkspaceDock` set an empty
  `setTitleBarWidget(QWidget())` and only `DockWidgetMovable`), so there was
  **no way to close it**.
- Splitting was effectively top/bottom only and offered no nesting control; the
  native Qt drop-zone UX cannot be restyled to feel premium.

Separately, the Ankountant study surfaces (Readiness / Confusion / TBS) were
three full-page routes reached through a shared top-tab shell — you could view
one at a time, never side by side.

Constraints that shaped the decision:

- A web pane can only host a **web** surface; the Qt-native tools (Browser, Add,
  Stats) are `QWidget`s and cannot render inside a webview pane.
- The design system (`docs_ankountant/design-tokens.json`) was defined but the
  web UI only partially consumed it — no semantic type scale, legacy beveled
  buttons, hardcoded shadows.

## Decision

Deliver premium tiling **in the web layer, for the study surfaces**, and
separately **repair** (not premium-ify) the Qt dock behaviour for the legacy
tools.

**1. Design-token foundation** (`ts/lib/sass/_vars.scss`, `base.scss`,
`_button-mixins.scss`): add a semantic type scale (`--type-<role>-*`) + `.t-*`
utilities, theme-aware `--elevation-e1..e3`, and remove the legacy
`impressed-shadow` bevel from the global button base (flat fill + tinted shadow

- `translateY(1px)` press).

**2. BSP tiling workspace** at `ts/routes/(ankountant)/ankountant-workspace/`:

- `layout.ts` — a pure, DOM-free binary tree (`leaf{surface}` | `split{dir,
  ratio, a, b}`) with **path-based** immutable operations (`splitAt`, `closeAt`,
  `setSurfaceAt`, `setRatioAt`), a `MAX_PANES = 4` cap, and localStorage
  serialize/deserialize with repair. Unit-tested in `layout.test.ts`.
- Recursive `TileView` → `Pane` / `Resizer`. Splitting is **button-driven**
  (split-left/right, split-top/bottom) plus drag-to-resize; each pane has a
  surface switcher and a **close** button; the sibling reclaims the space on
  close. This reproduces "left pane, right column split top/bottom" without the
  finicky drag-and-drop that made the old flow frustrating.
- Surfaces are the **existing prop-driven components** (`Dashboard`,
  `ConfusionMode`, `TbsSurface`) mounted through thin self-loading pane wrappers
  (`panes/*Pane.svelte`) that replicate each route's `+page.ts` loader. The
  standalone routes remain for deep-linking + tests.
- Hosted by opening the `ankountant-workspace` route in the existing Ankountant
  webview (`Ankountant → Study Workspace`); the shared shell's tab bar is
  suppressed on that route.

**3. Qt dock repair** (`qt/aqt/workspace.py`): closable tool docks get
`DockWidgetClosable`, and `_sync_title_bars()` restores Qt's **native title bar
(with a close button) when a pane is untabbed**, stripping it again when
re-tabbed. This is deliberately native, not premium.

## Consequences

- Study surfaces can now be arranged freely (up to four), resized, closed, and
  swapped — the premium tiling the Qt docks could not provide.
- The layout model is pure and tested, decoupled from Svelte; adding a surface
  is a registry entry (`surfaces.ts`) + a pane wrapper.
- Qt-native tools (Browser/Add/Stats) still tile only via Qt docks (now
  closable), and are **not** hostable in web panes. A **Review** surface is not
  yet wired (it needs the reviewer runtime). Drag-a-surface-onto-an-edge drop
  zones are a deferred enhancement; splitting is button-driven for now.
- The token foundation (type scale + elevation) is shared, so future re-skins of
  any web surface consume it rather than hardcoding.
