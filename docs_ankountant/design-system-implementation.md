# Ledger design system — implementation build spec (web + iOS)

> Status: **Implemented for Ankountant summit UI surfaces; broader token migration remains a reference spec** · Owner: eric · Last updated: 2026-07-03
> Turns the agreed system into exact, file-scoped edits. Values come from **`design-tokens.json`** (do not invent hexes); rationale is in **`design-system.md`**.
> Accent = **Ink Navy** `#1F3A5F` (light) / `#7FA6D4` (dark). Single identity + light/dark. 8px controls. System-native type. Tabular numerals. Tinted elevation. Cool-slate neutrals.

## 2026-07-03 summit UI overhaul

Implemented surfaces:

- Desktop `ankountant-home`: navy app rail, white metric rail, sync-safe exam-date control, abstain-aware readiness gauge with range, live strong/attention topics, and active-section topic mastery map.
- Desktop topographic renderer: active-section topics remain data-bound to backend readiness, with layered foreground/background SVG mountains, clipped contours, pass-line flags, hover-toggled topic detail cards, and the existing topic drill-down links.
- iOS `Home`: native summit hero, topic list, topic detail screen with Memory/Performance ranges and Gap, exam-date control backed by the sync-safe backend RPCs, and phase-aware review/confusion actions.
- iOS `Review`: pre-reveal confidence gate is now a required card-style panel before answer reveal.
- iOS shell: bottom navigation is Home, optional Reader, Browse, Analytics, and More; Review opens full-screen from Home or deck detail.
- iOS `Analytics`: Progress summary card added above the existing detailed charts.

Verification:

- `just test-ts` passes.
- `just test-e2e` passes for the desktop web surfaces.
- `just rebuild-web` hot-reloads the running PyQt shell.
- Full desktop visual QA is performed with `just run` in the live PyQt app, not a browser-only render.

---

## 0. How the pipeline works (verified)

`ts/lib/sass/_color-palette.scss` (raw ramps) + `_vars.scss` (`$vars` semantic map) → `_root-vars.scss` emits CSS custom properties for `:root` (light) and `.night-mode` (dark). **The same tokens are also extracted for Qt**: `qt/tools/extract_sass_vars.py` → `out/qt/_aqt/colors.py` / `props.py`, consumed by e.g. `qt/aqt/theme.py` (`FG_LINK`), `stylesheets.py` (`BORDER_FOCUS`), `switch.py`.

**Consequence: editing token _values_ in `_vars.scss` re-skins BOTH the web views and the Qt desktop chrome after `just check`.** Components mostly consume `var(--token)`, so this is low-churn. Keep the map structure; change values + add a few tokens.

---

## 1. Web — `ts/lib/sass/_vars.scss` (primary re-skin)

Change these `$vars` entries to the `design-tokens.json` values (each has a `light` + `dark`). Map:

| `$vars` path                                    | Token source (design-tokens.json)           | Note                                                            |
| ----------------------------------------------- | ------------------------------------------- | --------------------------------------------------------------- |
| `colors.fg.default`                             | `color.neutral.fg`                          | off-black `#0E0F13` / `#ECEEF2` (retire near-`#000` `#020202`)  |
| `colors.fg.subtle`                              | `color.neutral.fgSecondary`                 |                                                                 |
| `colors.fg.faint`                               | `color.neutral.fgTertiary`                  | keep ≥4.5:1                                                     |
| `colors.fg.link`                                | `color.brand.accent`                        | **navy** `#1F3A5F` / `#7FA6D4` (retire blue)                    |
| `colors.canvas.default`                         | `color.neutral.bg`                          | `#EEF0F4` / `#0F1216`                                           |
| `colors.canvas.elevated`                        | `color.neutral.surface` / `surfaceElevated` | card vs floating                                                |
| `colors.canvas.inset`                           | `color.neutral.surfaceInset`                |                                                                 |
| `colors.border.default`                         | `color.neutral.border`                      |                                                                 |
| `colors.border.subtle`                          | `color.neutral.borderSubtle`                |                                                                 |
| `colors.border.strong`                          | `color.neutral.borderStrong`                |                                                                 |
| `colors.border.focus`                           | `color.brand.focusRing`                     | **navy** (retire blue-5)                                        |
| `colors.shadow.focus`                           | `color.brand.accent`                        | **navy** (retire indigo `#6366f1`)                              |
| `colors.button.primary.bg`                      | `color.brand.fill`                          | navy `#1F3A5F` / `#274B75`                                      |
| `colors.button.gradient.start` / `.end`         | set BOTH = `colors.button.bg`               | **flat** (kill default-button gradient with no call-site churn) |
| `colors.button.primary.gradient.start` / `.end` | set BOTH = `color.brand.fill`               | **flat** primary                                                |
| `colors.selected.bg` (dark)                     | brand-navy alpha                            | cohesion (optional)                                             |
| **NEW** `colors.fg.error`                       | `color.feedback.fgError`                    | `#B0322F` / `#F7625A` — fixes undefined `--fg-error` (see §3)   |
| **NEW (optional)** `colors.fg.success`          | `color.state.positive.textLight` / `dark`   | fixes `--fg-success` in ConfusionMode (see §3)                  |

Keep unchanged (meaning-bearing): `colors.state.*` (new/learn/review/buried/suspended/marked), `colors.flag.*` (1-7), `colors.accent.*` (card=blue stays), `highlight`, `selected` (light).

Semantic-state note: `design-system.md` §1.4 tempers the raw hues. If you retune `state.*`, use `color.state.*` values; otherwise leave the current Anki hues (acceptable — they already carry meaning and pass with icon+label).

## 1a. Web — `_color-palette.scss` (secondary, optional)

Retint the `lightgray`/`darkgray` ramps to cool slate so ramp-derived values match the neutrals in §1. **Optional**: the semantic tokens in `_vars.scss` already carry exact hexes, so the ramp retint is polish. If you do it, keep the 0-9 index structure (every `palette(lightgray,n)` call must still resolve).

## 1b. Web — `elevation.scss`

- Default shadow `$color: #141414` → **`#0B0D12`** (cool-tinted ink).
- Reduce opacities `0.20/0.14/0.12` → **`0.16/0.10/0.08`** (lighter, precise). Prefer hairline + low level over heavy drops (`design-system.md` §3).

## 1c. Web — buttons (`_button-mixins.scss`, `buttons.scss`, `base.scss`)

- With `button.gradient.start = end` (from §1) the `linear-gradient(180deg, start, end)` becomes flat automatically. Add `--button-hover-bg` / `--button-primary-hover-bg` (navy ~6% darker = `color.brand.hover`) for hover.
- Primary: flat navy fill + tinted shadow `0 1px 2px rgba(31,58,95,.24)`.
- Active feedback: `&:active { transform: translateY(1px); }`.
- `base.scss` `button:hover { background: var(--button-gradient-start) }` → `var(--button-hover-bg)`.
- Ensure Bootstrap `--bs-*` (body bg/color, `--bs-font-sans-serif`) map to the new tokens so `bootstrap-reboot` doesn't reintroduce the generic look.

## 1d. Web — type, spacing, radius, numerals (new tokens)

Add to `props` in `_vars.scss` (emitted as `--*` by `_root-vars.scss`):

- `--font-sans` / `--font-mono` = `typography.family.*`.
- Base font-size 15px → **16px** (`props.font.size.default`) per a11y floor C1.
- `--space-*` from `space` (2..64).
- Radius: `props.border-radius.default 5px → 8px` (**control**), keep `medium 12px` (**card**), `large 15px → 16px` (**container**); retire "pill button" usage (pills = chips only).
- Add a `.tabular` utility (or apply on data nodes): `font-variant-numeric: tabular-nums lining-nums;`.
- Motion: `props.transition` already 180/500/1000ms; drop 1000ms usage; keep 180 (`base`), add 100/160/240 if used. Gate large motion behind `prefers-reduced-motion` in components.

---

## 2. Web — the three Ankountant pages (`ts/routes/(ankountant)/…`)

(Paths reflect the route group added in `desktop-single-window-shell.md` §4.1; if that shell work is done separately, the pre-move paths are `ts/routes/ankountant-*/`.)

- **Tabular numerals** on all scores/percentages/bands/JE cells: add `.tabular` (§1d) to those nodes.
- **Type scale**: replace ad-hoc sizes (e.g. `Dashboard.svelte` `.range { font-size: 1.4em }`, bare `<h1>/<h2>`) with the scale roles from `design-system.md` §2.
- **Score dashboard color logic** (`Dashboard.svelte`): three scores in neutral ink (`--fg`), tabular; **Readiness band = navy** (`--accent`) graded/faded; abstain = neutral dashed + "Not enough data yet"; **gap** = severity-tinted (warning), not color-only (add icon + label).
- **Color-never-alone**: every card-state / correct / incorrect / partial chip pairs color with an icon + text label (`design-system.md` §1.5).

---

## 3. Web — confirmed bugs to fix (verified)

- **`ts/routes/ankountant-dashboard/Dashboard.svelte:94`** — gap-warning row `background: var(--flag-1, #ffdddd)` (saturated flag red) and **:98** `color: var(--fg-error, #c00)` where `--fg-error` is **undefined**. Fix: row background → **danger tint** (`color.feedback.gapWarningBg`); text → the new `--fg-error` (§1). Keep a `.gap-warning` class (B5-D3 relies on it).
- **`ts/routes/ankountant-confusion/ConfusionMode.svelte:123/127`** — undefined `--fg-success` / `--fg-error`. Fix: define `--fg-success` (§1) + `--fg-error`; pair with icon+label.

---

## 4. iOS — SwiftUI theme (`ios/`)

2026-07-06 audit update: the shared iOS/widget theme package now exists at
`ios/AnkountantUI/Sources/AnkountantTheme/`. Future token changes should update
that package, its tests, and the app/widget consumers. The notes below are kept
as implementation history and cleanup guidance, not as a wholly unstarted plan.

Map `design-tokens.json` → Swift. The current package exports the shared app and
widget theme surface:

| Token area | Current source |
| --- | --- |
| Palettes and state colors | `Palette.swift`, `PaletteEnvironment.swift` |
| Theme and persistence | `Theme.swift`, `ThemeManager.swift`, `UserDefaults+AppGroup.swift` |
| Typography and numeric styles | `AnkountantTypography.swift` |
| Spacing, radius, elevation, motion | `AnkountantSpacing.swift`, `AnkountantRadius.swift`, `AnkountantElevation.swift`, `AnkountantMotion.swift` |
| Reusable modifiers and ShapeStyles | `AnkountantModifiers.swift`, `PaletteShapeStyle.swift` |

Widgets import `AnkountantTheme`, so app and WidgetKit views share palette,
typography, spacing, radius, elevation, motion, and card-state tokens. Remaining
cleanup should be documented against concrete direct-token escapes in current
views, not as a package migration.

---

## 5. Build / verify

- **Web + Qt:** `just check` (formats, builds, regenerates `out/qt/_aqt/colors.py`/`props.py` from the sass tokens, runs checks). Then `just run` and eyeball light + night-mode. `just test-ts` / `just test-e2e` for the ankountant pages.
- **iOS:** `cd ios && ./scripts/build-xcframework.sh` (only if proto changed — not here), then `swift build` (macOS lib targets) and `xcodebuild ... -scheme AnkountantApp` (full). `swift test` for the theme tests you updated.
- **Do not edit `out/`** — it is generated.

## 6. Order (low-risk)

1. `_vars.scss` values + new `fg.error`/`fg.success` (re-skins web + Qt) → `just check`, verify light + dark.
2. Buttons de-gradient + hover/active + focus ring.
3. Type/spacing/radius tokens + base 16px + tabular numerals.
4. Ankountant page fixes (§2, §3).
5. iOS §4 (Palette → Theme collapse + blast radius → package move → Dynamic Type → radius/elevation/motion).
