# 09 — Desktop TBS Surfaces: As-Built Map

> Status: **Implemented** · Owner: eric · Last audited: 2026-07-06 · Scope:
> desktop Svelte web surfaces for research, document-review, journal-entry, and
> numeric TBS.
>
> Earlier versions of this file were a pre-build plan. The current source of
> truth is the file map below; older "what to build" language has been removed so
> this doc can be used operationally.

## Current Behavior

Desktop now renders all four `Ankountant TBS` shapes:

| Shape | Surface | Submit mode | Scoring |
| --- | --- | --- | --- |
| Journal entry | `ankountant-tbs/TbsSurface.svelte` | `tbs` | per-line partial credit |
| Numeric | `ankountant-tbs/TbsSurface.svelte` | `tbs` | per-cell partial credit with tolerance |
| Research | `ankountant-research/ResearchSurface.svelte` | `research` | citation all-or-nothing, time-to-cite recorded as neutral signal |
| Document review | `ankountant-doc-review/DocReviewSurface.svelte` | `doc_review` | per-blank partial credit |

All modes use the shared Rust `SubmitPerformanceAttempt` path. The client render
model never receives `answer_key`; the answer key is parsed and graded only in
`rslib/src/ankountant/`.

## As-Built File Map

| Concern | Files |
| --- | --- |
| TBS render model and submission JSON | `ts/routes/(ankountant)/ankountant-tbs/lib.ts` |
| Shared exam shell | `ts/routes/(ankountant)/ankountant-tbs/ExamShell.svelte` |
| JE/numeric surface | `ts/routes/(ankountant)/ankountant-tbs/TbsSurface.svelte` |
| Shape/section chooser | `ts/routes/(ankountant)/ankountant-tbs/TbsTab.svelte` |
| Research surface | `ts/routes/(ankountant)/ankountant-research/ResearchSurface.svelte` |
| Document-review surface | `ts/routes/(ankountant)/ankountant-doc-review/DocReviewSurface.svelte` |
| Literature browser | `ts/routes/(ankountant)/ankountant-tbs/LiteraturePane.svelte`, `ankountant-research/{corpus,generated-corpus,lib}.ts` |
| Workspace panes | `ts/routes/(ankountant)/ankountant-workspace/panes/{TbsPane,ResearchPane,DocReviewPane,LiteraturePane}.svelte` |
| Workspace registry | `ts/routes/(ankountant)/ankountant-workspace/{workspace-layout.ts,surfaces.ts}` |
| Qt route hosting | `qt/aqt/mediasrv.py`, `qt/aqt/workspace.py` |
| Core grading and attempt log | `rslib/src/ankountant/{service,grading,logic,attempt_log,readiness}.rs` |
| Seed and literature corpus | `rslib/src/ankountant/{seed.rs,seed_content.json,literature.rs,seed_literature.json}` |

## Data Contract

- `Ankountant TBS` remains one union note type with fixed fields:
  `tbs_type`, `prompt`, `exhibits_json`, `steps_json`, `schema_tag`,
  `source_passage`, `gen_method`, `checker_status`.
- Section is carried by `sec::<SECTION>` tags and deck names such as
  `Ankountant::Sealed::<SECTION>::<set_id>`.
- Research steps use a `citation` step whose server-side `answer_key` may be a
  scalar citation or an accepted-citation array.
- Document-review steps use `kind:"blank"`, label-stripped `options`, and a
  document exhibit marked `role:"document"` with `<blank step="...">...</blank>`
  markers.

## Workspace Integration

The desktop workspace currently exposes `dashboard`, `confusion`, `tbs`,
`research`, `doc_review`, `literature`, `stats`, `add`, and `browse` surfaces.
Each pane self-loads from the collection and coordinates with other panes
through collection state, not peer-to-peer pane state. The literature pane is
tileable as read-only reference; exhibits stay inside each work surface so the
active requirement and supporting material remain co-visible.

## Remaining Work

- More production content coverage, especially beyond the current seeded/demo
  and generated/template decks.
- Keyboard-first polish for grids, dropdown blanks, and account selection.
- Deeper result explanations per blank/step where source material supports it.
- Fresh e2e coverage whenever the interaction contract changes.

## Verification

Use repo recipes only:

```bash
just test-ts
just test-e2e
just check
```
