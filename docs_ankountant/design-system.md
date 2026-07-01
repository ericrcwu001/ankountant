# Ankountant Design System — "Ledger" v1

> Status: **Agreed v1** · Owner: eric · Last updated: 2026-07-01
> One premium design language shared by the **desktop app** (PyQt + Svelte/TS, SCSS → CSS custom properties, light + `night-mode`) and the **iOS app** (SwiftUI, light + dark).
>
> This spec is a **cross-synthesis** of four skill-driven reviews (each grounded in the real token files):
> - Visual language / anti-slop — `design-taste-frontend`
> - Existing-implementation audit + migration — `redesign-existing-projects`
> - iOS SwiftUI theme review — `swiftui-pro`
> - Evidence base (what makes good UI for adult learners) — learning-science research
>
> **Decisions locked (2026-07-01):** accent = **Ink Navy**; **one** identity + light/dark (beige `muted` theme retired); **8px rounded** controls (no pills except chips); **system-native** type (SF / system-ui) + mono for ledgers; a generated **`design-tokens.json`** is the single source of truth (see `design-tokens.json`).

---

## 0. North star

**Design read:** a cross-platform study-and-measurement **instrument** for a time-pressured, anxious, competent adult (the CPA "Retaker"), with a **calm, credible, data-honest** language — professional/fintech, not playful, not consumer-craft, not generic SaaS. Every pixel either helps effortful retrieval or reports an honest number.

**Two governing forces (from the learning-science brief):**
1. **Protect working memory & self-efficacy** — cut extraneous load; one focused thing per screen; honest but kind.
2. **Be an instrument, not a game** — restraint, precision, tabular numbers, no gamified pressure.

**Three dials** (baseline 8/6/4 → overridden for a trust-first tool):

| Dial | Value | Why |
|---|---|---|
| `DESIGN_VARIANCE` | **3** | Predictable aligned grids; numbers line up; zero novelty tax. |
| `MOTION_INTENSITY` | **3** | Motion is feedback only (reveal, score change, press). No ambient motion. |
| `VISUAL_DENSITY` | **5, bimodal** | Review surfaces breathe (~3); dashboard/TBS/browse pack (~6–7) with hairlines + tabular figures. |

---

## 1. Color

### 1.1 The firewall (resolves the brand-vs-state collision)

A study app permanently spends four hues on **meaning**: green = correct/review, red = incorrect/learn, amber = warning/gap, blue = new/info. So:

- **Brand accent lives on chrome only** — primary actions, links, focus, selection, active nav/tab, and the Readiness honesty moment.
- **Semantic hues live on data/state only** — card-state chips, graphs, ledger validation, gap severity.
- They never cross. Because they occupy different surfaces *and* different contexts, they cannot be confused, even where the brand shares a hue family with a state (see §1.2).

### 1.2 Brand accent — **Ink Navy**

Deep, desaturated navy (~hue 212°). Classic finance/trust color, extremely legible (light navy on white ≈ 10:1), and clearly not brass, not AI-purple, not bright SaaS-blue.

| Token | Light | Dark | Notes |
|---|---|---|---|
| `brand` (text/icon/stroke/focus) | `#1F3A5F` | `#7FA6D4` | Light ≈ 10:1 on white ✓ (AAA) |
| `brand-fill` (button bg) | `#1F3A5F` | `#274B75` | White label: L ≈ 10:1 / D ≈ 7:1 ✓ |
| `brand-hover` | `#172C48` | `#2F5888` | |
| `brand-tint` (selected/active bg) | `#E7ECF3` | `rgba(127,166,212,0.14)` | |
| `on-brand` | `#FFFFFF` | `#FFFFFF` | |

**Navy ↔ new-blue proximity (the one caveat, mitigated):** navy is the same hue *family* as the semantic `new` blue. It is kept unambiguous by (a) the **chrome-only rule** — navy is never a card state; (b) keeping `new`/`info` a **brighter, more saturated** blue (`#2E6FD6`), so state-blue and brand-navy differ by lightness + saturation; (c) every state also carries an icon + label (§1.5). The Readiness band uses navy deliberately as the brand honesty-moment, disambiguated by its large "Readiness" label + hero numeral.

### 1.3 Neutrals — cool slate (harmonized to the navy brand)

One temperature everywhere (warm = the consumer-craft direction we reject; the undertone is a faint cool slate that pairs with the navy accent). Off-black, never `#000`; off-white, never `#fff`. Replaces both the current pure-neutral Tailwind grays (web) and the warm-beige iOS `muted` ramp.

| Role | Light | Dark |
|---|---|---|
| `bg` (app canvas) | `#EEF0F4` | `#0F1216` |
| `surface` (card / reading) | `#FBFBFC` | `#171B21` |
| `surface-elevated` (menu/modal) | `#FFFFFF` | `#1F242C` |
| `surface-inset` (input) | `#FFFFFF` | `#12151A` |
| `border-subtle` | `#E6E9EF` | `#262C34` |
| `border` | `#D5DAE3` | `#303742` |
| `border-strong` | `#B7BECB` | `#414A57` |
| `fg` / ink (primary) | `#0E0F13` | `#ECEEF2` |
| `fg-secondary` | `#3C424D` | `#AEB4BF` |
| `fg-tertiary` | `#616875` (4.6:1 on white ✓) | `#8A909C` |
| `fg-disabled` | `#9AA0AC` | `#5B6270` |

### 1.4 Semantic state palette (instrument-tempered, distinct from brand)

Saturation < 80%. Chips = tinted background (12–16%) + **text-safe** color variant + hairline (~28%), so contrast is text-on-tint (high). Solid/destructive fills use the darker text variant with white.

| Semantic | Card-state | Fill (L) | Text-on-light | Dark |
|---|---|---|---|---|
| Correct / positive | review, correct | `#1F9D57` | `#157A42` (4.8:1 ✓) | `#34D07C` |
| Incorrect / danger | learn, wrong | `#D64541` | `#B0322F` (6.2:1 ✓) | `#F7625A` |
| Warning / gap | buried, caution | `#E1922B` | `#8A5A12` (6.5:1 ✓) | `#F5B44E` |
| New / info | new | `#2E6FD6` | `#2559AE` (6.6:1 ✓) | `#5AA0FF` |

These four + the brand navy form the categorical data-viz set (run a color-blindness pass; the audience skews finance/male → higher deuteranopia rate). **Preserved from the current system:** `suspended` (yellow), `marked` (indigo), and **flags 1–7** keep their existing hues. `accent.card` stays blue (it is the semantic "card" concept, not the app identity). Because the brand is navy (not turquoise), no flag hue needs to move.

### 1.5 Color is never the only signal (hard rule)

Every state — correct / incorrect / partial / new / learn / review / buried / suspended / marked / abstain, and each confidence level — pairs its color with **≥1 of: icon, text label, shape, or position** (WCAG 1.4.1). Example: Correct = check + "Correct" + green; Partial = stepped icon + "Partial: method ok / slip"; Abstain = hatch pattern + "Not enough data yet". Bake the icon+label+shape into the token, don't leave it per-view.

---

## 2. Typography

**Family — system-native, both platforms (decided).** iOS stays **SF** (system). Web uses the **system-ui stack** (SF on Apple, Segoe UI Variable on Windows). True cross-platform parity, zero font load, offline-safe, and it sidesteps the Inter-default tell. A licensed brand sans (IBM Plex, Geist) is reserved for the **wordmark/marketing only**, never product chrome.

```css
--font-sans: system-ui, -apple-system, "SF Pro Text", "Segoe UI Variable Text",
             "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
--font-mono: ui-monospace, "SF Mono", "Cascadia Code", "Roboto Mono", Menlo, Consolas, monospace;
```

**Tabular figures are mandatory** on every number that aligns or changes (scores, Wilson bands, %, deltas, JE grids, ledger amounts, stats):
`font-variant-numeric: tabular-nums lining-nums;` (web) · `.monospacedDigit()` (iOS).
**Ledger / JE cells** step up to system **monospace** for true column alignment and a financial-ledger feel.

**Unified type scale** (web base 16px per the a11y floor; iOS 17pt body — a deliberate density difference, not drift):

| Role | Web | iOS | Weight | Tracking | Line-height | Numeric |
|---|---|---|---|---|---|---|
| Score / display hero | 40px | 34pt | 600 | −0.01em | 1.05 | tabular |
| Section heading | 22px | 24pt | 600 | −0.015em | 1.2 | — |
| Card title | 18px | 20pt | 600 | −0.01em | 1.25 | — |
| Body | 16px | 17pt | 400 | 0 | 1.5–1.55 | tabular where numeric |
| Body emphasis | 16px | 17pt | 600 | 0 | 1.5 | — |
| Callout | 15px | 15pt | 400 | 0 | 1.45 | — |
| Caption | 13px | 13pt | 500 | 0 | 1.4 | tabular where numeric |
| Micro / column-label | 12px | 12pt | 600 | +0.02em (uppercase functional labels only) | 1.3 | — |
| Mono (ledger/JE) | 15px | 15pt | 400/500 | 0 | 1.45 | tabular by nature |

Negative tracking is applied to **display sizes only**; body/caption use SF's built-in optical tracking (the current global −0.4pt fights the system and hurts small-size legibility). **Reading measure capped at ~66ch**; line-height ≥ 1.5.

---

## 3. Spacing · Radius · Elevation · Motion

**Spacing — one 4-pt scale** (extends the iOS names; web emits `--space-*`):
`2 · 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64` → `xxs xs sm md lg xl xxl xxxl huge` (2px = hairline/optical exception). Tight *within* a group, loose *between* groups (Gestalt).

**Radius — one scale** (resolves web 5/12/15 vs iOS 10/12/14/Capsule):

| Token | Value | Applies to |
|---|---|---|
| `inner` | 6px | small chips, inline controls |
| `control` | 8px | **buttons, inputs, selects, toggles** |
| `card` | 12px | cards, panels |
| `container` | 16px | modals, sheets, large surfaces |
| `pill` | 9999px | status chips / badges **only** |

Buttons are 8px rounded-rects (decided) — the iOS Capsule and the web "15px pill button" are retired: full pills read consumer/marketing, which fights the instrument feel. Shape lock: cards 12 · modals 16 · controls 8 · chips pill.

**Elevation — borders-first, tinted to ink** (replaces the web 9-level Material system and the iOS single heavy offset shadow):

```css
/* light — ink #0E0F13 */
--e0: none;                                                       /* default: 1px hairline */
--e1: 0 1px 2px rgba(14,15,19,.06), 0 1px 3px rgba(14,15,19,.05); /* resting card */
--e2: 0 4px 10px rgba(14,15,19,.09), 0 2px 4px rgba(14,15,19,.06);/* menu / popover */
--e3: 0 16px 40px rgba(14,15,19,.16), 0 4px 10px rgba(14,15,19,.08);/* modal / sheet */
/* dark — rely on surface-lightness steps + hairline; shadow secondary */
--e1-dark: 0 1px 2px rgba(0,0,0,.40);
--e2-dark: 0 6px 16px rgba(0,0,0,.50);
--e3-dark: 0 20px 48px rgba(0,0,0,.60);
```

**Motion tokens** (resolves web 180/500/1000 vs iOS none; drop 1000ms):

| Token | Duration | Use |
|---|---|---|
| `instant` | 100ms | press, toggle, tactile feedback |
| `fast` | 160ms | hover, focus ring |
| `base` | 240ms | panel/sheet, confidence-gate reveal, score change |
| `slow` | 400ms | modal, large layout |

Easing: enter `cubic-bezier(0.2,0,0,1)`, exit `cubic-bezier(0.4,0,1,1)`; iOS `.spring(response:0.35, dampingFraction:0.9)` / `.easeOut(0.24)`.
**Reduced motion (mandatory):** `@media (prefers-reduced-motion: reduce)` / `@Environment(\.accessibilityReduceMotion)` → instant/opacity only; no loops. **Focus ring = 2px brand navy + offset, never a glow.**

---

## 4. Accessibility floors (non-negotiable)

Grounded in WCAG 2.2 + Apple HIG + cognitive-load evidence. These **constrain** every aesthetic choice above.

| # | Constraint |
|---|---|
| C1 | Body text ≥ **16px web / 17pt iOS**; never < 12px. |
| C2 | Text contrast ≥ **4.5:1** (≥3:1 large); **target 7:1** for primary study prose. |
| C3 | Non-text/UI/graphic contrast ≥ **3:1** (controls, states, focus rings, chart strokes, grid borders). |
| C4 | Reading measure **45–75ch**, default cap ~66ch. |
| C5 | Line-height body ≥ 1.5; headings 1.2–1.35. |
| C6 | Survive WCAG 1.4.12 text-spacing overrides; reflow at 200% zoom / iOS Dynamic Type to AX sizes with no essential truncation. |
| C7 | Target size ≥ **44×44pt iOS** / ≥ 24×24px (+24px spacing) web. |
| C8 | **Color never the sole signal** (§1.5). |
| C9 | Honor Reduce Motion; no motion-only info; UI transitions ≤ ~200ms; nothing flashing >3×/s. |
| C10 | **Tabular numerals** on all scores/timers/JE cells. |
| C11 | **Retrieval integrity:** answer/rationale not in the render tree until an attempt is committed; no peek affordance. |
| C12 | **Uncertainty honesty:** Readiness = graded/faded Wilson band (never a crisp point or hard error bar) + explicit abstain state. |
| C13 | ≤ ~4 primary chunks per view; visible focus + full keyboard/VoiceOver operability of reviewer, gate, grid. |

---

## 5. Signature-surface guidance

**Reviewer (retrieval + confidence gate).** Focus mode: one item, minimal chrome, content-dominant; defer all metrics. Answer not renderable pre-commit; input affordance identical whether the answer will be right or wrong (no leakage). Confidence gate = exactly 3 equal-weight options (Guess / Unsure / Confident), fixed neutral order, **no default**, no leading color/size, keys 1/2/3, captured before reveal — "Guess" must be visually safe to pick. Feedback is immediate, **task-level not self-level** ("credit Deferred inflow, not Revenue, because…"), calm (no alarm-red flash), carrying icon+label+color. Stem ≤66ch, ≥16px/17px, ~7:1 contrast.

**TBS surface (exhibits + JE grid + partial credit).** Kill split-attention: keep the referenced exhibit and the active cell **co-visible** (synced split-view / pin / inline callout that highlights the exhibit line). Chunk the grid; account entry uses **recognition** (pickers/autocomplete), not recall. Tabular numerals + thousands separators; columns align. Partial credit is **per-step and diagnostic**, distinguishing **method error vs slip** (the single biggest anxiety-lowering move). Continuous autosave + resume-exactly-here; every step state encoded by icon+label+color; grid borders ≥3:1; cells ≥ target size; keyboard-navigable. **Not** the flashcard reviewer — no Again/Hard/Good/Easy.

**3-score dashboard (calibration + honest abstain).** Memory / Performance / Readiness as three **aligned** units on a common horizontal scale (position beats gauges/donuts), all numerals in **neutral ink + tabular** (do not paint them three semantic colors — that implies pass/fail verdicts). **Readiness = a graded brand-navy Wilson band with faded edges** (navy is the brand/chrome color, reserved for this honesty moment; kept distinct from the brighter `new`-state blue by darkness + the large "Readiness" label) + plain-language label ("projected exam-day score; band = confidence range"); optional frequency framing ("~X of 100 exam-days like today pass"). **Abstain is a first-class state** (hatch + "Not enough data yet" + the resolution path: "~20 more scored items in Leases"), visually unlike a low score. **Gap** = literal annotated distance between the Memory and Performance markers, framed as "recognize vs apply — the normal next thing to close", severity-tinted (warning), never color-only. `gap-warning` uses a **danger-tint** background + a defined `--fg-error` text token (this fixes a current real contrast bug: `Dashboard.svelte` paints the row in saturated `--flag-1` red with an undefined `--fg-error` falling back to `#c00`).

---

## 6. Cross-platform token contract

**Single source of truth (decided):** author one `design-tokens.json` (see the sibling file) and generate **both** the SCSS `$vars` map and the Swift `Palette`/token structs. This permanently prevents the drift that already exists today (e.g. learn = **red** on web vs **orange** on iOS; radius 10/14 outliers with no web counterpart; three different "brand" blues).

Name mapping (align on one vocabulary; iOS renames in parens):

| Concept | Web SCSS var | iOS `Palette` field | Value source |
|---|---|---|---|
| App canvas | `--canvas` | `background` → `canvas` | §1.3 `bg` |
| Card surface | `--canvas-elevated` | `surface` | §1.3 `surface` |
| Floating surface | `--canvas-overlay` | `surfaceElevated` | §1.3 `surface-elevated` |
| Input surface | `--canvas-inset` | (add) `surfaceInset` | §1.3 `surface-inset` |
| Ink | `--fg` | `textPrimary` → `fg` | §1.3 `fg` |
| Ink secondary/tertiary | `--fg-subtle` / `--fg-faint` | `textSecondary` / `textTertiary` | §1.3 |
| Brand | `--accent` (+ `link`, `border-focus`, `shadow-focus`) | `accent` (+ `link`) | §1.2 |
| States | `--state-*`, `--flag-*` | (add) `stateNew/Learn/Review/…` | §1.4 |
| Radius | `--border-radius-{control,card,container}` | `AnkountantRadius` | §3 |
| Spacing | `--space-*` | `AnkountantSpacing` | §3 |
| Elevation | `--e0..e3` | `AnkountantElevation` (from `palette.shadow`) | §3 |
| Motion | `--motion-*` | `AnkountantMotion` | §3 |

Base font size stays per-platform (16px web / 17pt iOS); role names and ratios are shared.

---

## 7. Migration plan

**Web (token-driven → changing values re-skins everything; each phase shippable & revertible):**
0. Grep call sites that pass a color to `elevation(...)` or read `--button-*gradient*`.
1. **Token values only:** rewrite `_color-palette.scss` neutral ramps + `_vars.scss` (accent/link/focus/primary = navy, set button `gradient.start = end` = flat, off-black `#0E0F13`) + `elevation.scss` (tint `#0B0D12`, lighter opacities). `_root-vars.scss` re-emits automatically. Test light + `.night-mode`.
2. **Buttons:** de-gradient → flat fill + tinted shadow + `:active { translateY(1px) }`; unify focus ring to brand navy (remove the hardcoded Mac focus + indigo `shadow.focus`).
3. **Systems:** add type + spacing tokens; bump base 15→16px; apply `tabular-nums` to data surfaces; define `--fg-error`; fix dashboard `gap-warning` (danger tint) + score alignment.
Keep `state.*` / `flag.*` untouched → semantics preserved end-to-end. Ensure Bootstrap `--bs-*` (body bg/color, font) are overridden so reboot doesn't reintroduce the generic look.

**iOS:**
1. `ThemeManager` → `@Observable @MainActor`, drop `@unchecked Sendable` (matches the project's own convention; fixes a real data-race smell).
2. **Drop the beige `muted` theme** and collapse `Theme{vivid,muted}` to one identity × light/dark (decided).
3. Move typography/spacing/radius/elevation/motion into the `AnkountantTheme` package (today they live app-only, so the widget re-invents the ramp with different kerning + hardcoded `.blue/.orange/.green`).
4. Add `AnkountantRadius` / `AnkountantElevation` (from `palette.shadow`, theme-aware) / `AnkountantMotion`.
5. Type ramp → **Dynamic Type** (semantic text styles or `@ScaledMetric(relativeTo:)`); drop body/caption negative tracking; add a `.numeric`/`.dataCell()` variant.
6. Add an `onAccent` token (white-on-accent must clear AA; navy passes comfortably) and route status text to darker on-surface shades.
7. Expose `Palette` as resolvable `ShapeStyle` (`.foregroundStyle(.textPrimary)`, `.background(.surface)`) to kill `@Environment(\.palette)` boilerplate.
8. Align `learn` state color to the shared token; add `stateNew/Learn/Review` (stop hardcoding). Pin sRGB in the hex helper for 1:1 parity with web.

---

## 8. Decisions (locked 2026-07-01)

1. **Accent** = **Ink Navy** `#1F3A5F` / `#7FA6D4`. (Ledger Teal was the convergent recommendation; navy chosen for a more classically authoritative finance identity, with brand↔new-blue proximity handled by the chrome-only rule + a brighter new-state blue.)
2. **Theme model** = single Ankountant identity + light/dark; beige `muted` theme retired.
3. **Buttons** = 8px rounded-rect; pills only for status chips.
4. **Type** = system-native (SF / system-ui) + mono for ledger/JE cells.
5. **Token source of truth** = generated `design-tokens.json` → SCSS `$vars` + Swift `Palette`.
6. Web base bumped 15→16px (a11y floor C1). Flags unchanged (navy brand doesn't touch the turquoise flag-6).

**Remaining follow-ups (implementation, not blocking agreement):** build the token generator; run a color-blindness pass on the 5-color data-viz set; verify night-mode WCAG on the score dashboard after the ramp swap; confirm no component treats `accent.card` (blue) as the app's primary/brand.

---

## Appendix — provenance

Synthesized from four parallel skill reviews (grounded in the real token files):
`design-taste-frontend` (visual language), `redesign-existing-projects` (audit + web token migration), `swiftui-pro` (iOS theme review), and a learning-science research brief (adult-learner UI evidence). Conflicts resolved toward the stricter accessibility floor and the more instrument-appropriate option. The two visual reviews independently converged on Ledger Teal; the final identity is **Ink Navy** (owner's call for a more classically authoritative finance look), rendered against the fixed semantic states in `accent-preview.html` before selection.
