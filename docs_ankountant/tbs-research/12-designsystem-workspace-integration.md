# 12 — TBS Surfaces, Design System, And Workspace Integration

> Status: **Implemented** · Owner: eric · Last audited: 2026-07-06
>
> This file replaces the earlier read-only integration survey. Current desktop
> surfaces are implemented in the Ledger design system and registered in the BSP
> workspace.

## Current Workspace Model

The desktop workspace is a pure BSP tree in
`ts/routes/(ankountant)/ankountant-workspace/workspace-layout.ts`. A leaf mounts
one `SurfaceKind`; a split recursively lays out two children. The current surface
union is:

```ts
"dashboard" | "confusion" | "tbs" | "research" | "doc_review" |
"literature" | "stats" | "add" | "browse"
```

`surfaces.ts` maps each kind to a label, glyph, and self-loading pane component.
Each pane loads from the collection through generated backend calls and does not
share mutable state with sibling panes. Cross-pane coordination goes through the
Rust collection, not direct pane messaging.

## Surface Strategy

| Concern | Current placement | Reason |
| --- | --- | --- |
| JE/numeric work area | `TbsSurface.svelte` inside the TBS tab/surface | requirement and answer grid need one local state model |
| Research work area | `ResearchSurface.svelte` | citation input and results belong with the task |
| Document-review work area | `DocReviewSurface.svelte` | blanks, document, and per-blank results need one component tree |
| Exhibits | inside each work surface via `ExamShell` / exhibits pane | active requirement and supporting material must be co-visible |
| Authoritative literature | both in `ExamShell` and standalone `literature` pane | read-only reference is useful tiled beside any surface |

This preserves exam-style split-screen behavior inside a task while still letting
the outer workspace tile research/doc-review/literature with Readiness, Browse,
Stats, or Add.

## Design-System Contract

Desktop TBS surfaces use the Ledger token stack:

- Semantic colors from `ts/lib/sass/_vars.scss` / emitted CSS custom properties.
- Tabular numerals for amounts, percentages, scores, and timing.
- `--font-mono` for citation, ledger, and numeric cells.
- Color-never-alone for correctness: icon plus text/aria label, not color alone.
- 8px control radius and compact, work-focused layout.

Do not invent route-local palettes or ad hoc spacing when adding a TBS component.
Prefer existing tokens and utilities; add tokens at the Sass map level when a new
semantic value is genuinely needed.

## Current File Map

| Concern | Files |
| --- | --- |
| Workspace model | `ankountant-workspace/workspace-layout.ts` |
| Workspace renderer | `Workspace.svelte`, `TileView.svelte`, `Pane.svelte`, `Resizer.svelte` |
| Registry | `ankountant-workspace/surfaces.ts` |
| Pane wrappers | `ankountant-workspace/panes/*.svelte` |
| TBS exam shell | `ankountant-tbs/ExamShell.svelte` |
| JE/numeric | `ankountant-tbs/TbsSurface.svelte` |
| Research | `ankountant-research/ResearchSurface.svelte` |
| Document review | `ankountant-doc-review/DocReviewSurface.svelte` |
| Literature | `ankountant-tbs/LiteraturePane.svelte`, `ankountant-workspace/panes/LiteraturePane.svelte` |
| Shell routing | `ts/routes/(ankountant)/+layout.svelte` |
| Qt hosting | `qt/aqt/{mediasrv.py,workspace.py,main.py}` |

## Adding Or Changing A Surface

1. Add or update the `SurfaceKind` union and `SURFACE_KINDS` order in
   `workspace-layout.ts`.
2. Add/update the `SURFACES` entry in `surfaces.ts`.
3. Create a self-loading pane wrapper under `panes/`.
4. Add a standalone route only if deep-linking or e2e coverage needs one.
5. Register the route/context in Qt hosting if it is exposed outside the
   workspace.
6. Add unit/e2e coverage for parser, layout, and interaction contracts.

## Verification

```bash
just test-ts
just test-e2e
just check
```
