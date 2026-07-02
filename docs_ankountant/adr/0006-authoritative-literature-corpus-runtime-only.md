# 0006. Authoritative-literature corpus: real excerpts, runtime-only, uncommitted

Status: Accepted
Date: 2026-07-02

## Context

The test-accurate TBS build (see `PRD-tbs-shapes-future.md`) renders every TBS
inside a shared **exam shell** that includes an **authoritative-literature
browser** (FAR → FASB ASC). Real fidelity — especially for the **research sim**,
where the skill under test is _navigating_ the codification to find a governing
paragraph — wants the browser to contain real ASC prose to search.

But the project's own sourcing firewall (`CONTEXT.md`, `docs_ankountant/rag/*`)
classifies FASB ASC as a **Tier-B source: "cite but never ingest/redistribute."**
The repo is a public-capable GitHub fork of AGPL Anki
(`github.com/ericrcwu001/ankountant`), so committing ASC prose into it is
redistribution — independent of the app being personal-use-only.

The tension: research-sim fidelity wants real ASC text; the firewall (and
copyright) forbids redistributing it.

Options considered:

1. **Commit real ASC excerpts into the repo** — simplest authoring; violates
   Tier-B + copyright via GitHub redistribution.
2. **Ship no ASC prose** — paraphrase + cite-only; safe, but the browsed prose is
   less authentic.
3. **Real excerpts at runtime, kept out of version control** — authentic
   locally, redistributes nothing.

## Decision

**Bundle real ASC excerpts into the personal runtime, but keep the corpus out of
version control.** The literature corpus is loaded at runtime from an
uncommitted, gitignored location (the Anki collection media folder), so the local
build is fully authentic while the repo redistributes nothing.

- **MAY be committed:** the **citations** themselves (facts — `ASC 842-20-25-1` —
  not copyrightable), our **own paraphrased section summaries**, corpus
  _manifests/indexes_ (citation keys + which seed items reference them), and all
  code/schema.
- **NEVER committed:** verbatim ASC prose bodies. They live only in the user's
  local media folder (gitignored), populated by a local, non-committed authoring
  step.
- The corpus sits behind a clean **loader interface** so a properly-licensed or
  fully-paraphrased corpus can replace it before any distribution, with no caller
  changes (the T2 seam).
- Preserves the Tier-B firewall (no redistribution) and the sync-safe rule
  (corpus is media, not new SQLite tables/columns).

## Consequences

- The running app is test-accurate for research navigation; the repo stays
  Tier-B-clean and copyright-safe.
- Seed research items reference corpus passages by **citation key**; their
  _accepted citations_ and _paraphrased summaries_ are committed, but the verbatim
  body a user searches is local-only. Tests MUST NOT depend on verbatim ASC prose
  (assert on citation keys + paraphrase presence instead).
- A first-run/authoring step must populate the local corpus (documented, not
  committed). If absent, the browser degrades to paraphrase+citation view rather
  than crashing.
- Any future public distribution is a clean swap at the loader seam — revisit
  this ADR before shipping. Supersedes the personal-use "licensing isn't a
  concern" stance only to the extent of keeping ASC prose uncommitted.
