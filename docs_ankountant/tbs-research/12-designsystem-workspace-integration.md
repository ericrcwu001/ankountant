# 12 — Design system + tiling-workspace integration for the new TBS surfaces

> Status: **Analysis (read-only survey of `main`)** · Owner: eric · Last updated: 2026-07-02
> Purpose: define how the two deferred _test-accurate_ TBS shapes — **research-sim**
> and **document-review** (`docs_ankountant/PRD-tbs-shapes-future.md`) — should plug
> into the Ledger design system and the BSP tiling workspace so they reproduce the
> real exam's split-screen ("exhibits + authoritative-literature tabs | response
> area + spreadsheet") layout.
>
> This is a design/integration map, not an implementation. Every claim carries a
> file ref. No code was changed producing this doc.

## 0. Sources surveyed

- Design system: `docs_ankountant/design-system.md`, `design-system-implementation.md`,
  `design-tokens.json`, `desktop-single-window-shell.md`.
- Token emission: `ts/lib/sass/_vars.scss`, `_root-vars.scss`, `base.scss`.
- ADR: `docs_ankountant/adr/0002-ankountant-study-workspace-tiling.md`.
- Workspace: `ts/routes/(ankountant)/ankountant-workspace/{layout.ts,context.ts,surfaces.ts,Workspace.svelte,TileView.svelte,Pane.svelte,Resizer.svelte,+page.ts,+page.svelte}`
  and `panes/{TbsPane,ConfusionPane,DashboardPane,BrowsePane,StatsPane,AddPane,PaneState}.svelte`.
- Shell + surfaces: `ts/routes/(ankountant)/+layout.svelte`, `ankountant-tbs/{TbsSurface.svelte,lib.ts}`,
  `ankountant-confusion/ConfusionMode.svelte`, `ankountant-home/Home.svelte`.
- Qt host: `qt/aqt/workspace.py`, `qt/aqt/mediasrv.py`, `qt/aqt/main.py`.
- iOS hub: `ios/AnkountantApp/Sources/Simulations/{SimulationsHubView,TbsTaskView}.swift`.
- Feature contract: `docs_ankountant/PRD-tbs-shapes-future.md`.

---

## 1. How the tiling workspace + panes work

### 1.1 The layout model is a pure BSP tree

`ts/routes/(ankountant)/ankountant-workspace/layout.ts` is a DOM-free binary
space-partition tree. Every node is a `LeafNode { type:"leaf", id, surface }`
or a `SplitNode { type:"split", id, dir:"row"|"col", ratio, a, b }`
(`layout.ts:27-43`). A pane shows exactly one `SurfaceKind`:

```13:13:ts/routes/(ankountant)/ankountant-workspace/layout.ts
export type SurfaceKind = "dashboard" | "confusion" | "tbs" | "stats" | "add" | "browse";
```

All edits are **pure, path-addressed, immutable** operations with structural
sharing: `splitAt`, `closeAt`, `setSurfaceAt`, `setRatioAt`, `addPane`,
`ensureSurface` (`layout.ts:105-191`). Guards: `MAX_PANES = 4` and
`MIN_RATIO = 0.15` (`layout.ts:45-49`). Persistence is
`serialize`/`deserialize` with a `sanitize` repair pass (unknown surface →
`dashboard`, dead child collapses to sibling, out-of-range ratio clamped)
(`layout.ts:193-243`). This model is unit-tested (`layout.test.ts`), so adding
a surface never touches the tree logic.

### 1.2 Rendering is a recursion of four components

- **`Workspace.svelte`** — the root. Owns the `tree`, seeds it from
  `?initial` or localStorage (`Workspace.svelte:40,85-107`), exposes the four
  edit actions through Svelte context, renders the toolbar (add-pane picker,
  reset, pane count `leaves/MAX_PANES`), and mounts one `TileView` at the root
  path `[]` (`Workspace.svelte:48-62,110-155`).
- **`TileView.svelte`** — recursive: a `leaf` renders a `Pane`; a `split`
  renders two child `TileView`s (self-import) sized by `flex-grow:{ratio}` /
  `{1-ratio}` with a `Resizer` between them (`TileView.svelte:22-34`).
- **`Pane.svelte`** — one leaf: a 36px header (surface `<select>` switcher +
  split-row / split-col / close buttons) over the mounted surface, which is
  `<svelte:component this={def.component} />` (`Pane.svelte:33-118`). Splitting
  duplicates the current surface into the new pane (`Pane.svelte:55,76`); the
  user re-points it with the switcher.
- **`Resizer.svelte`** — the draggable gutter. Reports a new `ratio` on
  pointer-move (measured against its parent split's rect) and is keyboard-
  operable as an ARIA `separator` (`Resizer.svelte:24-82`).

### 1.3 Panes talk to the root by path, not to each other

`context.ts` is the whole contract:

```12:17:ts/routes/(ankountant)/ankountant-workspace/context.ts
export interface WorkspaceActions {
    split(path: Path, dir: SplitDir, surface: SurfaceKind, side?: Side): void;
    close(path: Path): void;
    setSurface(path: Path, surface: SurfaceKind): void;
    setRatio(path: Path, ratio: number): void;
}
```

`Workspace.svelte` `setContext(WORKSPACE_ACTIONS, actions)`; `Pane`/`Resizer`
`getContext` it (`Workspace.svelte:62`, `Pane.svelte:23`, `Resizer.svelte:21`).
**There is no peer-to-peer pane messaging and no shared in-memory app store.**
The context only mutates _layout_. Panes coordinate solely through the **Rust
collection as the single source of truth**: each pane self-loads via
`@generated/backend` (`postProto`) and re-fetches to refresh. This is the key
constraint for §2.

### 1.4 A "surface" = registry entry + self-loading pane wrapper

`surfaces.ts` maps each `SurfaceKind` to a `SurfaceDef { kind, label, glyph,
component }` (`surfaces.ts:23-68`). Each `component` is a **self-loading pane
wrapper** under `panes/` that replicates the corresponding route's `+page.ts`
loader, then mounts the shared surface component. Canonical example:

```28:49:ts/routes/(ankountant)/ankountant-workspace/panes/TbsPane.svelte
async function load(): Promise<void> {
    phase = "loading";
    try {
        const found = await searchNotes({ search: FIRST_TBS_SEARCH });
        noteId = found.ids.length > 0 ? found.ids[0] : 0n;
        ...
        const note = await getNote({ nid: noteId });
        model = buildTbsModel(note.fields);
        phase = "ready";
    } catch (err) { ... }
}
```

`panes/PaneState.svelte` renders the loading/empty/error placeholder so a pane
never shows blank (`TbsPane.svelte:51-60`, `PaneState.svelte`). Some panes are
trivial pass-throughs (`StatsPane.svelte` just mounts `Stats`); some are rich
(`BrowsePane.svelte` composes sidebar + virtual table + editor and self-manages
scroll regions).

**Adding a surface is a 4-touch registry change** (ADR 0002 "Consequences"):

1. add the kind to the `SurfaceKind` union + `SURFACE_KINDS` array (`layout.ts:13,52-59`),
2. add a `SURFACES` entry (`surfaces.ts:31-68`),
3. write a `panes/*Pane.svelte` self-loader,
4. (optional) keep a standalone route for deep-linking/tests.

### 1.5 The Qt/host seam

`Workspace.svelte` exposes `window.__ankWorkspace.open(kind)` / `.reset()` so Qt
can add/focus a surface in an already-open workspace (`Workspace.svelte:94-107`).
The workspace itself is opened as a **Qt dock tab**, not a main-window state:
`qt/aqt/workspace.py` maps logical names → flat routes (`_ANKOUNTANT_ROUTES`,
`workspace.py:57-61`) and `open_ankountant(...)` (`main.py:1591-1606`). The
shell tab bar is suppressed on the workspace route so the workspace owns its
chrome (`+layout.svelte:38-40`, `Workspace.svelte` toolbar).

---

## 2. Mapping the exam's split-screen onto our tiles

### 2.1 What the exam looks like

Per `PRD-tbs-shapes-future.md §1,§5`: a real research testlet is _prompt +
searchable authoritative literature_ (FAR/BAR → FASB ASC), submit a citation,
graded on **correctness + time** (navigation, not recall). A doc-review testlet
is _exhibits + a document with N blanks_, each blank a confusion-set "which
treatment?" call, graded per-blank. The on-screen shape is the classic
split-screen: **reference material on one side, the response/work area (often
with a spreadsheet) on the other.**

### 2.2 Two ways to render a split-screen here — and which to use where

**Option A — composite surface with an _internal_ split.** One `SurfaceKind`
renders both halves itself (a nested `flex` layout), like today's
`TbsSurface.svelte` (`.tbs-body` = `.task` flex:2 | `.exhibits` flex:1,
`TbsSurface.svelte:253-289`) or `BrowsePane.svelte` (sidebar | table | editor).

**Option B — separate tileable panes** the user arranges with the BSP splitter
(exhibits/literature as their own `SurfaceKind`s dropped next to the work pane).

**Can exhibits/literature be their own panes the user tiles?** _Partly, and the
distinction matters:_

- The **authoritative-literature browser is an excellent standalone tileable
  surface** — it is read-only reference (a searchable corpus, T2), semantically
  like `browse`/`stats`. Tiling it beside anything (a TBS work pane, the
  dashboard, the note browser) is exactly what the workspace is for, and it lets
  a candidate keep the codification open while doing unrelated study.
- **Exhibits must stay _inside_ the work-area surface.** Two hard reasons:
  1. **Split-attention is a product rule, not a preference.** `design-system.md
     §5` (TBS guidance) and constraint **C13** require the referenced exhibit and
     the active cell/blank to be **co-visible and synced** ("synced split-view /
     pin / inline callout that highlights the exhibit line"). That co-visibility
     cannot depend on the user manually tiling a second pane and keeping it open.
  2. **Panes can't share selection.** Per §1.3, `WorkspaceActions` only mutates
     layout and there is no shared store — so a cross-pane interaction like
     "click a citation in the literature pane → highlight the matching cell in the
     TBS pane," or "click exhibit line 4 → scroll the work grid," is _impossible_
     across a pane boundary today. Those interactions only work _within_ one
     surface's own component tree.

**Recommendation (hybrid):**

| Concern                                       | Where it lives                                                        | Why                                                                                        |
| --------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Research work area (prompt + citation submit) | inside a `research` composite surface (internal split)                | needs in-surface "cite this passage" wiring                                                |
| Doc-review work area (document + N blanks)    | inside a `docreview` composite surface (internal split with exhibits) | exhibit↔blank co-visibility + sync (C13)                                                   |
| Authoritative-literature corpus browser       | a _new standalone tileable_ surface (e.g. `literature`)               | read-only reference, no cross-pane state needed; genuinely useful tiled beside any surface |

The **outer** BSP tiling then still composes study sessions the exam can't:
`[docreview] | [dashboard]` to watch the gap move (`design-system.md §5`),
`[research] | [literature]` for extra reference, or `[research] | [browse]`.
Net: the _test-accurate_ split-screen is delivered _inside_ each work surface;
the workspace adds optional, on-brand outer composition on top.

---

## 3. Design tokens & typography to use

All tokens below are the CSS custom properties actually emitted by
`_root-vars.scss` from the `$vars` map in `_vars.scss` (nested keys flatten to
`--a-b-c`, and a `default` leaf drops its suffix — e.g. `border-radius.default`
→ `--border-radius`, `border-radius.medium` → `--border-radius-medium`). Do not
invent hexes; reference the vars.

### 3.1 Numerics — the non-negotiables for JE/spreadsheet/numeric grids

- **Tabular figures on every aligned/changing number** (scores, %, amounts, JE
  cells, time-to-cite): `.tabular` utility or `font-variant-numeric: tabular-nums
  lining-nums` (`base.scss:48-50`; `design-system.md §2`; constraint **C10**).
- **Ledger/JE + citation cells step up to mono** for true column alignment:
  `font-family: var(--font-mono)` (`_vars.scss:26-28`). The existing JE grid
  already does exactly this and right-aligns amounts
  (`TbsSurface.svelte:380-386`). The `.t-mono` utility bundles both
  (`base.scss:71-74`).

### 3.2 Type scale — never hardcode font-size

Use the role tokens `--type-<role>-{size,weight,line,tracking}` or the `.t-<role>`
utilities (`base.scss:52-69`; `_vars.scss:33-88`). Roles available:
`display-hero, section-heading, card-title, body, body-emphasis, callout,
caption, micro, mono`. Suggested assignment:

| Surface element                    | Role                          | Token(s)                       |
| ---------------------------------- | ----------------------------- | ------------------------------ |
| Surface/task title                 | `section-heading`             | `--type-section-heading-*`     |
| Prompt / document prose            | `body` (cap ~66ch, **C4**)    | `--type-body-*`                |
| Literature passage body            | `body`, `text-selection` on   | `--type-body-*`                |
| Citation string / JE cell / amount | `mono` + tabular              | `--font-mono`, `.tabular`      |
| Column labels / "Exhibits" caps    | `micro` (uppercase)           | `--type-micro-*`               |
| Time-to-submit, partial-credit %   | `caption`/`callout` + tabular | `--type-caption-*`, `.tabular` |

### 3.3 Color, surfaces, borders, focus

- **Brand navy is chrome-only** (`--accent`, `--accent-tint`): primary submit
  button, active tab, focus ring, selection — never a data state
  (`design-system.md §1.1-1.2`; `_vars.scss:452-466`).
- **Correctness/state = semantic + icon + label** (color-never-alone, **C8**):
  `--fg-success` / `--fg-error` paired with a `✓`/`✗` glyph and an aria label,
  exactly as the JE grid step-marks (`TbsSurface.svelte:389-400`) and the
  confusion verdict (`ConfusionMode.svelte:243-258`).
- **Card surface pattern** (reused everywhere): `background: var(--canvas-elevated)`
  - `1px solid var(--border-subtle)` + `border-radius: var(--border-radius-medium)`
  - `box-shadow: var(--elevation-e1)` (`TbsSurface.svelte:259-266`,
    `Home.svelte:246-252`).
- **Grid/control borders must clear 3:1** (**C3**): inputs, selects, choice
  buttons use `--border-control`; hairline row dividers use `--border-subtle`,
  header underline `--border` (`TbsSurface.svelte:315-367`).
- **Inputs**: `background: var(--canvas-inset)`, `1px solid var(--border-control)`,
  `border-radius: var(--border-radius)`, focus = `outline: 2px solid var(--accent);
  outline-offset` (never a glow; `design-system.md §3`; `TbsSurface.svelte:349-367`).
- **Choice blanks (doc-review)** reuse the confusion treatment button: full-width,
  `min-height: 44px` target (**C7**), `--border-control`, hover
  `border-color/background: var(--accent)/var(--accent-tint)`
  (`ConfusionMode.svelte:190-223`).
- **Spacing**: 4-pt scale `--space-xxs..huge` (`_vars.scss:89-100`).
- **Motion**: `--motion-{instant,fast,base,slow}`; feedback-only; gate large
  motion behind `@media (prefers-reduced-motion: reduce)` (`_vars.scss:143-148`;
  `design-system.md §3`; **C9**). (Note: legacy `--transition*` also exists,
  180/500/1000ms — prefer `--motion-*`.)

### 3.4 Uncertainty / honesty tokens (carry through to dashboards these surfaces feed)

Readiness stays a faded navy Wilson band, abstain is first-class
(`Home.svelte:373-445`, **C12**). Research/doc-review attempts feed Performance
and the gap (PRD T1 AC4 / T3 AC4), so nothing in these surfaces should paint a
crisp pass/fail verdict on the score — keep verdicts task-level.

---

## 4. How the new surfaces register (workspace + shell + iOS SimulationsHub)

The shape enum already anticipates both new shapes on all layers — only the
UI + grading branches are missing:

- TS render model: `TbsShape = "journal_entry" | "numeric" | "research" |
  "doc_review"` (`ankountant-tbs/lib.ts:18`), and `buildTbsModel` already accepts
  them (`lib.ts:96-107`). The answer key is stripped server-side — steps render
  **without** `answer_key` (`lib.ts:26-42`), satisfying retrieval integrity
  (**C11**).
- iOS: `TbsShape` has `.research`/`.docReview`; `SimulationsHubView.shapeLabel`
  already labels them ("Research", "Document review",
  `SimulationsHubView.swift:74-81`); `TbsTaskView` switches on shape and
  currently renders _"This simulation type isn't supported yet."_ for both
  (`TbsTaskView.swift:66-72`) — that branch is the exact insertion point.
- Grading: `SubmitPerformanceAttempt(mode="research"|"doc_review")`, append-only,
  no new table/proto (PRD T4; the RPC is already called by
  `TbsSurface.svelte:41-52`).

### 4.1 Web workspace registration

For each new work surface (`research`, `docreview`) and the optional read-only
`literature` surface:

1. Extend `SurfaceKind` + `SURFACE_KINDS` (`layout.ts:13,52-59`).
2. Add `SURFACES` entries with label/glyph (`surfaces.ts:31-68`).
3. Add `panes/ResearchPane.svelte` / `panes/DocReviewPane.svelte` self-loaders
   modeled on `TbsPane.svelte`. **Watch-out:** `TbsPane` loads the _first_ TBS
   note regardless of shape (`FIRST_TBS_SEARCH`, `TbsPane.svelte:19-21`). The new
   panes must **filter by `tbsType`** (field index `TBS_FIELD.tbsType`,
   `lib.ts:9-16`) so they load a `research` / `doc_review` note, not collide on
   the first JE note. The note carries `data-shape` (`TbsSurface.svelte:61`).
4. The `literature` pane self-loads the bundled corpus (PRD T2) — client-side
   search over a bundled file, or an append-only `SearchLiterature` RPC if the
   corpus is large (PRD T2/OQ-3).

### 4.2 Shell route + host wiring (parity with `ankountant-tbs`)

ADR 0002 keeps standalone routes "for deep-linking + tests". To match, give each
work surface a flat route under the `(ankountant)/` group (e.g.
`ankountant-research`, `ankountant-doc-review`) with the usual
`+page.ts`/`+page.svelte`/`Surface.svelte`/`lib.ts`. Then, **in lockstep**
(`desktop-single-window-shell.md §7` risks):

- add the route name to the first-segment whitelist `qt/aqt/mediasrv.py`
  (`mediasrv.py:428-431`),
- add it to `_ANKOUNTANT_ROUTES` (`qt/aqt/workspace.py:57-61`),
- optionally add a shell tab (`+layout.svelte:21-28`) and/or an Ankountant menu
  action (`main.py:1591-1606`).

### 4.3 iOS SimulationsHub registration

`SimulationsHubView` lists tasks generically via `performanceClient.listTbsTasks()`
and routes every row to `TbsTaskView(noteId:)` (`SimulationsHubView.swift:32-59`),
so research/doc-review items **already appear** in the list once seeded. Work
needed: replace the two "unsupported" branches in `TbsTaskView`
(`TbsTaskView.swift:66-72`) with `ResearchTaskView` / `DocReviewTaskView`
subviews using the same `AnkountantTheme` palette/fonts as the JE/numeric grids
(`TbsTaskView.swift:84-223`). iOS has **no codegen** — if T2 adds a
`SearchLiterature` RPC, re-derive the service/method indices in
`ios/Sources/AnkiBackend/AnkiBackend.swift` from
`out/pylib/anki/_backend_generated.py` (root `CLAUDE.md` / `ios/CLAUDE.md`).

---

## 5. Recommended composition for each new surface

### 5.1 Research-sim surface (`research`)

**Internal split (row): Literature (left, larger) | Task (right).** Reuse
`TbsSurface`'s `.tbs-body` flex idiom (`TbsSurface.svelte:253-272`) but flip the
weighting so the corpus is the big pane (it's what the candidate navigates).

```
┌ Research simulation ─────────────────────────────────────────────┐
│ prompt (body, ≤66ch)                                              │
├───────────────────────── row split ──────────────┬───────────────┤
│ LITERATURE (flex:2)                               │ TASK (flex:1) │
│  ┌ search input (--canvas-inset,--border-control)┐│ Citation:     │
│  │ e.g. "lease classification"        [Search]   ││ [ASC 8__ ]    │  <- mono input
│  └───────────────────────────────────────────────┘│  (tabular/mono)│
│  results list (citation + title, mono citation)   │ [ Submit ]    │  <- navy primary
│  ── passage reader (body, ≤66ch, text-select on) ─│ result:       │
│     "» cite this" fills the citation input        │  ✓ Correct    │  <- icon+label+--fg-success
│                                                    │  12.4s        │  <- caption+tabular
└────────────────────────────────────────────────────┴──────────────┘
```

- **Behavior (PRD T1):** search the bundled corpus, submit a citation string;
  grade exact/normalized correctness (1/0) with **time-to-submit** surfaced as a
  neutral secondary caption, _not_ a credit multiplier. Keep the accepted-cite
  key server-side (**C11**; `lib.ts` already strips keys).
- **In-surface sync (allowed, within one component):** clicking a passage's
  "cite this" fills the citation input — the cross-pane version is impossible
  (§2.2), which is exactly why this lives in one surface.
- **Tokens:** card surfaces §3.3; `--font-mono` for citation strings + input;
  `.tabular` for time; correctness = `--fg-success`/`--fg-error` + `✓`/`✗` + label;
  submit = `--button-primary-bg`/`--button-primary-hover-bg` (`TbsSurface.svelte:409-438`).
- **Keyboard:** `Ctrl/Cmd+F` focuses the corpus search, mirroring
  `BrowsePane.svelte:592-597`.
- **As a pane:** `ResearchPane.svelte` self-loads the first `research`-shape note
  (§4.1) → `<ResearchSurface {noteId} {model} />`; `PaneState` for loading/empty.
- **Not the reviewer:** never render Again/Hard/Good/Easy (`TbsSurface.svelte:59-60`).

### 5.2 Document-review surface (`docreview`)

**Internal split (row): Exhibits (left) | Document with N blanks (right)** — the
test-accurate exhibit/response split, co-visible by construction (**C13**).

```
┌ Document review ─────────────────────────────────────────────────┐
│ prompt (body)                                                     │
├───────────────── row split ─────────────┬────────────────────────┤
│ EXHIBITS (flex:1, own scroll)            │ DOCUMENT (flex:2)      │
│  ┌ Exhibit A (card) ────────────┐        │  ...paragraph text...  │
│  │ pre / mono body              │        │  treatment for X is    │
│  └──────────────────────────────┘        │  [ which? ▾ ]     ✓     │  <- blank = confusion choice group
│  ┌ Exhibit B (card) ────────────┐        │  ...more text... and   │
│  │ ...                          │        │  Y is [ ▿ ]      ✗     │  <- per-blank icon+label mark
│  └──────────────────────────────┘        │                        │
│                                           │  [ Submit ]  74%       │  <- navy primary + tabular chip
└──────────────────────────────────────────┴────────────────────────┘
```

- **Behavior (PRD T3):** each blank is a confusion-set "which treatment?" choice
  (candidate treatments, **label-stripped** per SPOV 4). Reuse the confusion
  treatment-button pattern (recognition rows, 44px targets,
  `ConfusionMode.svelte:92-107,190-223`) for each blank. Submit → per-blank
  correctness → partial-credit total (same math as JE, A10); render a per-blank
  `✓`/`✗` mark inline (icon+label+color, **C8**) and the total in an
  `--accent-tint` chip with tabular figures (`TbsSurface.svelte:440-459`).
- **Exhibits pane:** stacked exhibit cards with mono `pre` bodies and its own
  independent scroll region (like `BrowsePane`'s regions), reusing
  `TbsSurface`'s `.exhibits`/`.exhibit` styling (`TbsSurface.svelte:274-312`).
- **Co-visibility:** exhibits and the active blank stay on screen together; an
  inline "highlight the exhibit line this blank references" callout is the C13
  ideal — feasible because both halves are one component.
- **As a pane:** `DocReviewPane.svelte` self-loads the first `doc_review`-shape
  note (§4.1) → `<DocReviewSurface {noteId} {model} />`.
- **Outer tiling:** `[docreview] | [dashboard]` lets the candidate watch
  Performance/gap move after submit (PRD T3 AC4; `design-system.md §5`).

### 5.3 Optional literature reference surface (`literature`)

A read-only, tileable corpus browser (search field + citation-keyed results +
passage reader), styled like `BrowsePane` but reference-only. It answers the
"can literature be its own pane?" question affirmatively for the _reference_
role, and can be tiled beside a `research` pane, the `browse` pane, or the
`dashboard`. It self-loads the bundled corpus (PRD T2) and holds no answer keys.

---

## 6. Gaps & watch-outs (verified)

- **No cross-pane state.** `WorkspaceActions` mutates layout only; there is no
  shared selection/highlight store (`context.ts:12-17`, §1.3). Any "click here →
  highlight there" must be intra-surface. Do **not** design the exhibit↔cell or
  citation↔cell sync as two separate tiles.
- **`TbsPane` loads the first TBS note regardless of shape**
  (`TbsPane.svelte:19-21`). New panes must filter by `tbsType` or the JE/numeric
  and research/doc-review panes will fight over the same note.
- **`MAX_PANES = 4`** (`layout.ts:46`). Putting exhibits/literature _inside_ the
  work surface (composite) means one work surface consumes **one** pane slot, not
  two — the internal split doesn't draw from the 4-pane budget. This is another
  reason to prefer composite work surfaces.
- **Pane body scrolls the whole surface** (`.pane-body { overflow:auto }`,
  `Pane.svelte:216-220`). Composite surfaces should manage their own internal
  scroll regions per column (as `BrowsePane` does) so exhibits and document
  scroll independently.
- **Lockstep host edits.** A standalone route needs the mediasrv whitelist
  (`mediasrv.py:428-431`) **and** `_ANKOUNTANT_ROUTES` (`workspace.py:57-61`)
  updated together, or the page 404s / can't be opened
  (`desktop-single-window-shell.md §7`).
- **iOS indices are hand-maintained.** A new `SearchLiterature` RPC (if chosen
  per OQ-3) forces re-deriving `AnkiBackend.swift` indices (root `CLAUDE.md`).
- **Retrieval integrity (C11).** Accepted citations (research) and blank answer
  keys (doc-review) stay server-side; the render model must keep stripping them
  (`ankountant-tbs/lib.ts:26-42`).
- **Licensing (PRD R1/OQ-1).** Ship only scoped literature excerpts; treat
  ingested standards text as untrusted if AI ever touches it (Phase 2a).
