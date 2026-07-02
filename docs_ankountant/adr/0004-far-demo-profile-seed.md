# 0004. FAR demo profile: opt-in fake history in the shared-core seed

Status: Accepted
Date: 2026-07-01

## Context

The FAR seed (`rslib/src/ankountant/seed.rs`, RPC `LoadFarSeed`) existed only as
a _structural_ fixture: ~40 placeholder items with prompts like
`"Recall capitalize_vs_expense-0-0"` and **no** review/attempt history. A
freshly-seeded profile therefore showed Memory = insufficient and Readiness =
abstain — it exercised the plumbing but lit nothing up.

The goal was a demo profile where, on a fresh install of **either app**, the
review loop runs on a real deck, the memory model reports an **honest range**,
the **give-up rule** is visible, and some items are TBS — with real CPA content.

Two hard constraints collided:

1. The A4/A5 Rust tests and the `dashboard.test.ts` (A55) e2e spec call the seed
   and **assume zero attempt history** (they inject controlled amounts to test
   the abstain/band thresholds; A55 asserts the freshly-seeded dashboard
   _abstains_). Baking history into the seed unconditionally breaks them.
2. A single static profile cannot show **both** a band (needs to _cross_ the
   thresholds) **and** the give-up rule (fires _under_ them) at the same scope.

## Decision

**Two layers behind one seed, history opt-in via a proto field.**

- **Content (always):** ~130 real CPA-FAR recall cards + real confusion MCQs +
  the pinned anchor TBS + a few worked TBS, embedded from
  `seed_content.json` (authored offline by the `far-seed-content` workflow: a
  fan-out author pass + an independent fact-check pass — the Phase-2a pattern in
  miniature). Provenance rides in the card body / TBS provenance fields.
- **History (opt-in):** `LoadFarSeedRequest.with_history` (new proto field 2,
  backward-compatible — no method-index shift, so iOS dispatch is unaffected).
  When true, the shared core injects fake recall revlog + sealed Attempt-Log
  notes so the profile lands in an **honest band** (~40 sealed attempts @ ~60%
  → "Med" confidence, a real gap), while **one confusion set
  (`trading_afs_htm`) is deliberately left thin** → its per-topic readiness
  reads "insufficient" (the give-up rule) even though the overall band emits
  (coverage 3/4 ≥ 60%).
- **Callers:** the desktop menu and the iOS `DebugView` pass `with_history=true`
  (the lit profile); the e2e fixture and the Rust threshold tests use `false`
  (deterministic content, they control history themselves). Because it lives in
  the shared Rust core, both apps get the identical profile from one code path.

Rejected alternatives: a separate `SeedDemoHistory` RPC (new method → iOS index
drift + more surface); two menu actions (two round-trips, more UI); test-only
history helpers left where they were (wouldn't reach either app).

## Consequences

- One RPC, one seed, both apps — no duplicated seeding logic; iOS lights up as
  soon as it triggers `LoadFarSeed(with_history=true)`.
- The abstain/band threshold tests stay meaningful (they still start from an
  empty-history seed and drive the thresholds themselves).
- The "band + one under-covered topic" shape shows the honest range **and** the
  give-up rule simultaneously — the product's core honesty claim, demoable in
  one click.
- **Pinned forever:** the 4-line lease anchor JE and the 250000/12500 numeric
  TBS (grading + e2e worked examples), and `sealed_tbs_note_ids[0]` = the anchor
  JE (anchors are pushed before content TBS). Changing them breaks A10/A28/A35 +
  the TBS e2e specs. See the `far-demo-seed-contract` memory.
- The embedded `seed_content.json` is the first concrete instance of the Phase-2a
  output contract (see `docs_ankountant/rag/`): ordinary notes, provenance
  populated, sync-safe.
