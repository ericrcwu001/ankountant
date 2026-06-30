# 0001. Layered agent-navigation context system (hot index + cold nested context + single-source Cursor routers)

Status: Accepted
Date: 2026-06-30

## Context

Anki is a large, multi-language legacy codebase: core logic in Rust (`rslib/`),
a Python library and Qt GUI (`pylib/`, `qt/aqt/`), a Svelte/TypeScript frontend
(`ts/`), and a Protobuf contract (`proto/`) tying the layers together. AI coding
agents had no map of this structure, so they re-explored the tree from scratch on
every query — grepping, opening files, and rebuilding the same mental model turn
after turn. That wasted tokens and produced inconsistent navigation.

## Decision

Adopt a **hot/cold** navigation system, with a single source of truth shared
between Claude Code and Cursor.

- **Hot index.** The root `CLAUDE.md` carries a lean (~40-line) *Architecture
  Map*: pointers, not prose. It is loaded on every turn, so an agent always knows
  where the layers live and where to look next.

- **Cold nested context.** Detailed local knowledge lives in 5 nested `CLAUDE.md`
  files — `rslib/src/scheduler`, `proto`, `ts`, `qt/aqt`, `pylib/anki`. These are
  *cold*: auto-loaded only when an agent is actually working in that subtree, so
  their cost is paid only when relevant.

- **Cursor reconciliation.** `AGENTS.md` is symlinked to `CLAUDE.md`, so Cursor
  already receives the hot map. We therefore do **not** duplicate the map into
  `.cursor/rules`. Instead, `.cursor/rules/*.mdc` are thin *routers*: glob
  frontmatter that auto-attaches per path and points at the canonical nested
  `CLAUDE.md`. One source of truth, nothing to drift.

- **Ignore strategy.** Index noise (lockfiles, the docs site) goes in
  `.cursorindexingignore` — kept out of the search index but still *readable* on
  demand. It deliberately does **not** go in `.cursorignore`, which hard-blocks
  reads: the root `CLAUDE.md` notes that generated code under `out/` is useful to
  read on demand, and a hard block would defeat that. Build output is left to
  `.gitignore`, which Cursor already respects.

## Trade-off

We accept **pointer indirection** — an agent must open a nested file to get local
detail — in exchange for a low per-turn token cost and zero duplicated content
that could drift between tools.

## Consequences

- New subsystem docs are added as nested `CLAUDE.md` files plus a one-line pointer
  in the hot map and a thin `.mdc` router — never by inlining detail at the root.
- If a layer is split or moved, update the pointer and the router glob; the
  canonical content moves with the nested file and stays in one place.
