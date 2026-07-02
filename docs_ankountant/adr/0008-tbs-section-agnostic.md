# 0008. TBS engine is section-agnostic across all CPA sections

Status: Accepted
Date: 2026-07-02

## Context

The MVP (`PRD.md`) is scoped to **FAR**, and the deferred-TBS work initially
inherited that: FAR-only seed, FAR confusion sets, FAR literature. But the four
TBS **shapes** (journal-entry, numeric, research, document-review) are identical
across all six CPA sections (**AUD, FAR, REG, BAR, ISC, TCP**); only the content,
the authoritative-literature body, and shape prevalence differ. Restricting the
TBS surfaces to FAR under-serves the very shapes being added — **document-review's
canonical home is AUD** (the verbatim KCN example is an AUD item), and the
research **licensing** story is FAR-specific.

Cross-section facts (agent 05; `CONTEXT.md` Tier-A/Tier-B):

- **Literature bodies:** FAR/BAR → FASB ASC (+ SEC `S99`, GASB for governmental);
  AUD → AICPA Professional Standards + **PCAOB** standards; REG/TCP → **Internal
  Revenue Code** + Treasury Regs + IRS pubs; ISC → NIST / SOC / COBIT frameworks.
- **Licensing flips by section:** FASB ASC + GASB + AICPA = **Tier-B (cite-only)**;
  IRC/Treasury/IRS + SEC (eCFR) + PCAOB/GAO + NIST = **public domain (Tier-A,
  bundle verbatim)**. So REG/TCP and AUD research corpora can ship real text;
  FAR/BAR cannot (ADR 0006 still governs ASC).
- **Doc-review prevalence:** AUD-heavy (workpapers, request lists), medium on FAR
  (footnotes/disclosures), REG (tax docs), lower in the Disciplines.

## Decision

**The TBS engine, surfaces, and data model are section-agnostic.**

- **One `Ankountant TBS` union note type**, discriminated by `tbs_type` (shape)
  **and** a `section` value (AUD/FAR/REG/BAR/ISC/TCP). No per-shape or per-section
  note types (that would explode combinatorially). _This resolves the open
  note-type question in favor of the single-union-type option._
- Per-shape structure is expressed as **first-class, versioned, validated typed
  schemas** (not the "unknown JSON keys are ignored" trick), with a **typed
  exhibit model** (`{title, kind, body|rows}`). Sync-safe: still no new SQLite
  tables/columns; `section` + schemas ride in existing note fields + `col` config.
- The **authoritative-literature corpus is per-section/per-body** behind one
  loader: ASC = cite-only skeleton + paraphrase + deep link (ADR 0006);
  IRC/SEC/PCAOB/NIST = **bundled verbatim** (public domain).
- **Confusion sets, the CONFUSABLE map, and readiness become multi-section** —
  config keys are already `ankountant.confusable.<section>` and
  `GetReadiness(section)`, so the engine is half-built for this.
- **Seed content spans sections:** lead with AUD document-review (canonical),
  REG/IRC research (bundle-able verbatim), FAR footnote/numeric + research, and
  grow to BAR/ISC/TCP.

## Consequences

- Bigger content surface, but a single coherent engine; the shapes were always
  universal.
- The research **licensing problem is partly dissolved**: REG/TCP + AUD ship real
  authoritative text; only FASB-ASC sections (FAR/BAR) stay cite-only.
- The **broader app** (exam-date scheduling, the Memory study pile) may stay
  FAR-first for now; **TBS + confusion sets + Performance/readiness go
  multi-section**. Whether the full study loop follows is a separate, later call.
- ADR 0006 (ASC corpus) and ADR 0007 (exam shell) stand; this generalizes them
  across sections.
