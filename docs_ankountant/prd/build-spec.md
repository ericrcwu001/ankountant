# Build spec — seed, ordering, loop launch config, risks

> Operator + Build-agent reference. Contains the seed-content spec, phase ordering, cut order, the exact `agentic-loop` launch parameters, risks, and open questions.

## Phase ordering (hard)

**Complete all of Phase A (A1–A10) and get `just check` + `test-rust` green BEFORE starting Phase B.** Then desktop and iOS run as parallel tracks (disjoint files). This is encoded as `dependsOn` on every B feature (see `rubrics-frontend.md`). If pre-seeding `feature_list.json` (below), set each B feature's `dependsOn` to its Phase-A features so the Build generator won't start B early.

## Seed content (author as part of Phase A)

The demo seed (`rslib/src/ankountant/seed.rs` + `seed_content.json`, loaded by the `LoadFarSeed` RPC) is **FAR-deep and five-section-wide**: FAR carries the full rubric-exercising content, and AUD/REG/TCP/ISC add enough that the summit dashboard shows a real readiness range for all five visible sections (BAR is seeded structurally only, not shown). Every layer rides ordinary Anki objects (FR-5).

**FAR — deep core**, sized to exercise every rubric and cross the abstain thresholds on demand:

- **13-topic CONFUSABLE map** (one set per Home summit topic). The first four are the anchor sets the grading + e2e tests pin by index: capitalize vs expense; operating vs finance lease; rev-rec step selection; trading vs AFS vs HTM.
- **~100 real recall cards** across the topics (tagged `cog::rote` / `cog::applied` to exercise A2) so Memory is measurable per topic.
- **≥6 sealed MCQs per set**, plus the pinned anchor **journal-entry + numeric TBS** (A10 + e2e pin these), extra worked JE/numeric TBS, and section-agnostic research/doc-review items — comfortably clearing A5's ≥20-sealed-attempt / ≥60%-coverage thresholds so abstain can be dialed either way.

**AUD / REG / TCP / ISC — summit breadth:** 6 confusion sets each, with study recall cards, sealed MCQs, and section-agnostic TBS (research / doc-review / numeric / journal-entry), so every visible section reports a real Memory/Performance/Readiness signal. **38 confusion sets total** across the six sections (BAR contributes 1, structural only).

**Demo history** (opt-in `with_history`): fake review revlog + sealed Attempt Log notes and exam dates for all five visible sections, so a fresh profile opens on a lived-in summit with an honest band and the per-topic give-up rule.

- Playwright e2e fixture loads this seed via the `LoadFarSeed` RPC (a SQL/`col`-config seed builder run before each spec).

## Cut order (if the night runs short — cut last-to-first)

① iOS B-track (desktop demo suffices) → ② A2 latency defunding (mark `parked` so it doesn't gate the contract) → ③ numeric TBS (keep journal-entry) → ④ B4 exhibits polish. **Never cut:** A1, A3+A6, A4+A5, A7+A8, A9+A10, and desktop B3/B4/B5 — the minimum coherent thesis demo.

## Launching the agentic-loop

Point `/agentic-loop` at `../PRD.md`. The one clarifying round should answer with these values (drawn from this repo):

```
clarifications = {
  stackTarget: "Rust core (rslib) + PyQt/Svelte desktop (qt/, ts/) + SwiftUI iOS (ios/); protobuf contract in proto/",
  hardConstraints: [
    "Shared Rust core binds desktop (PyO3) + iOS (C FFI); AGPL-3.0.",
    "Proto changes append-only; never reorder SchedulerService methods.",
    "iOS service/method indices hand-maintained in AnkiBackend.swift; resync from _backend_generated.py after any proto change (FR-6).",
    "Sync-safe: no new SQLite table/column on notes/cards/revlog (FR-5) — hidden notes/settings notes + col config only."
  ],
  nonGoals: "Runtime AI/RAG card generation (Phase 2a is build-time only; optional Learning Feedback may call OpenAI as tutoring feedback but never grading/scheduling/readiness). Cloud sync, accounts, sync server proof (Phase 2b). Real IRT/CAT psychometrics (ADR 0005 CPA-scale heuristic only). BAR-first specialization. Full unique 50k course/content library. B2B/Becker head-on.",
  definitionOfDone: "just check exits 0; test-rust + test-py + test-ts green; every desktop-UI acceptance (per-assertion Playwright specs) green; all objective contract assertions pass. iOS is a manual demo track, NOT contract-gated. A2 may be parked without failing the contract.",
  budget: "one overnight run",
  buildLocation: "in-place (no worktree)",
  allowDestructiveRestart: false
}

config = {
  buildCmd: "just check",
  testCmd:  "just test-rust && just test-py && just test-ts",
  lintCmd:  "just lint",
  maxBuildIters: 5,
  maxContractRounds: 3,
  maxRestarts: 2,
  allowDestructiveRestart: false
}
```

**Pass `nonGoals` verbatim** — the scope-guard reads `clarifications.nonGoals`, not the PRD's non-goals section, and the "stored vs populated" distinction is what stops it false-dropping A9's provenance fields.

### Optional: pre-seed the contract to lock exact assertions

The loop skips a phase if its state file already exists. Because the rubrics in `rubrics-core.md`/`rubrics-frontend.md` were already adversarially reviewed, you may hand-author `<targetDir>/.agentic-loop/contract.md` (objective desktop+core assertions only, ids `A01…`, each mapping to feature ids) **and** a matching `feature_list.json`, then launch with `resume: true`. The loop will skip Plan+Contract and build against your exact contract. Trade-off: you bypass the loop's adversarial contract negotiation — only do this if you trust the hand-authored contract (it was 4-expert reviewed). If you skip pre-seeding, keep the per-feature acceptance bullets in `../PRD.md` substantive, since the Contract phase derives assertions from those hints (it never sees this file).

## Risks & mitigations

- **R1 — scope vs one night.** Strict P0/P1 + cut order above; shared-core-first so the engine story demos even if a frontend slips.
- **R2 — iOS index drift.** FR-6 append-only + resync + dispatch smoke test; iOS is cut-first.
- **R3 — readiness over-engineering.** A5 pins abstain + a Wilson sealed-Performance band projected through the ADR 0005 CPA-scale heuristic; faithful IRT/CAT scoring is out.
- **R4 — sync-safety regressions.** FR-5 hard rule + A8 AC4 PRAGMA round-trip.
- **R5 — thin seed.** Seed spec above sizes to cross every threshold + show interleaving.
- **R6 — loop ships with iOS unverified.** iOS ACs are a non-gated demo checklist by design; the objective contract is Rust + desktop-e2e. Review iOS manually before calling the demo done.

## Open questions

- **OQ-1** — Resolved: Readiness ships as a Wilson sealed-Performance band projected onto the CPA 0–99 scale by the documented ADR 0005 heuristic; faithful AICPA IRT/CAT scaling remains out because the transform is not public. Blocks nothing.
- **OQ-2** — Attempt Log volume at 50k scale: recall reps stay in revlog+custom_data (not Attempt Log). Blocks nothing for MVP.
- **OQ-3** — iOS verification: XCTest at client layer + manual demo; accepted, non-gated.
- **OQ-4** — Resolved: memory = trailing-30d recall accuracy (≥5 in-window reps else "insufficient").
- **OQ-5** — Richer ICAP cognitive-demand taxonomy + per-type latency baselines deferred to a follow-up PRD. Blocks nothing.
