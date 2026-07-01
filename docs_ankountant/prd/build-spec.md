# Build spec — seed, ordering, loop launch config, risks

> Operator + Build-agent reference. Contains the seed-content spec, phase ordering, cut order, the exact `agentic-loop` launch parameters, risks, and open questions.

## Phase ordering (hard)

**Complete all of Phase A (A1–A10) and get `just check` + `test-rust` green BEFORE starting Phase B.** Then desktop and iOS run as parallel tracks (disjoint files). This is encoded as `dependsOn` on every B feature (see `rubrics-frontend.md`). If pre-seeding `feature_list.json` (below), set each B feature's `dependsOn` to its Phase-A features so the Build generator won't start B early.

## Seed content (author as part of Phase A)

FAR, sized to exercise every rubric and cross the abstain thresholds on demand:

- **4 CONFUSABLE sets:** capitalize vs expense; operating vs finance lease; rev-rec step selection; trading vs AFS vs HTM.
- **Per set:** 3 study recall cards (tag some `cog::rote`, some `cog::applied` to exercise A2) + **≥6 sealed MCQs** → ≥24 sealed items total, so 20 sealed attempts is reachable and coverage can be dialed above/below 60%.
- **Sealed TBS:** 3 journal-entry + 2 numeric (playable via B4); optionally 1 research + 1 doc-review stored-only (A9 AC3).
- ~15–20 `cog::rote` recall cards total across sets.
- Playwright e2e fixture must load this seed (ship a `FAR-seed.apkg` or a SQL/`col`-config seed builder the fixture imports before each spec).

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
    "Sync-safe: no new SQLite table/column on notes/cards/revlog (FR-5) — hidden notes + col config only."
  ],
  nonGoals: "AI/RAG card generation, quality checker, leakage/baseline eval (Phase 2a). Cloud sync, accounts, sync server (Phase 2b). Populating provenance fields (Phase 2a) — the FIELDS are stored, only population is out. Real IRT/CAT psychometrics (Wilson accuracy-band heuristic only). Research-sim & document-review TBS SURFACES (future PRD) — the note type still STORES all 4 shapes. Sections other than FAR. Ablation study. Full course/content library. B2B/Becker head-on.",
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
- **R3 — readiness over-engineering.** A5 pins a Wilson accuracy-band + abstain; faithful 0-99 scaling is out (OQ-1).
- **R4 — sync-safety regressions.** FR-5 hard rule + A8 AC4 PRAGMA round-trip.
- **R5 — thin seed.** Seed spec above sizes to cross every threshold + show interleaving.
- **R6 — loop ships with iOS unverified.** iOS ACs are a non-gated demo checklist by design; the objective contract is Rust + desktop-e2e. Review iOS manually before calling the demo done.

## Open questions

- **OQ-1** — Readiness display scale: ships as a Wilson band on accuracy % (0–100), exam-day labeled; 0-99 scaled-score mapping deferred (AICPA transform not public). Blocks nothing.
- **OQ-2** — Attempt Log volume at 50k scale: recall reps stay in revlog+custom_data (not Attempt Log). Blocks nothing for MVP.
- **OQ-3** — iOS verification: XCTest at client layer + manual demo; accepted, non-gated.
- **OQ-4** — Resolved: memory = trailing-30d recall accuracy (≥5 in-window reps else "insufficient").
- **OQ-5** — Richer ICAP cognitive-demand taxonomy + per-type latency baselines deferred to a follow-up PRD. Blocks nothing.
