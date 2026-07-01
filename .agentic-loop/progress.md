# agentic-loop progress

> Rewritten by the build-generator agent every iteration. Reflects the current
> state of `feature_list.json` plus the last evaluator verdict. Small and
> scannable — this is the file a human skims to see "where is it right now."

**Status:** i4 — All P0 features (F001,F003–F016) implemented, in-idiom, and
green. This iteration cleared the LAST blocker: `just check` now exits 0
end-to-end (all 4 objective gates pass). No feature code changed — i3 had left
everything green except a chain of PRE-EXISTING minilint failures that had been
masked by the CONTRIBUTORS `exit(1)`. Gates: `just check` PASS,
`just test-rust` 581/581, `just test-py` (73 aqt + pylib/tools) PASS,
`just test-ts` 63/63, `just lint` PASS.
**Current iteration:** i4 (build:generate)
**Current feature:** all P0 done + all 4 gates green; only F002 (A2,
parkable/P1, deliberately NOT in contract) remains `todo` by design.

## Done

Phase-A shared core (Rust) — confirmed still-green this iteration:

- [x] F001 — A1 Deadline-anchored scheduler (ComputeExamSchedule RPC + ramp)
- [x] F003 — A3 Confusion-set queue builder (BuildConfusionQueue RPC)
- [x] F004 — A4 Mastery + gap query (GetReadiness scores)
- [x] F005 — A5 Abstain rule (Wilson band)
- [x] F006 — A6 Deep-structure + cognitive-demand tags
- [x] F007 — A7 Sealed performance bank (firewall)
- [x] F008 — A8 Attempt Log note type (sync-safe data path)
- [x] F009 — A9 TBS note type, all 4 shapes
- [x] F010 — A10 TBS step-grading backend (SubmitPerformanceAttempt RPC)
- [x] F016 — FAR seed content builder + Playwright e2e fixture loader (via the
      `LoadFarSeed` RPC, method 43, iOS enum resynced)

Phase-B desktop (F011–F015) — confirmed still-green this iteration:

- [x] F011 — B1 Attempt-before-reveal + confidence capture
      (`ts/lib/components/ConfidenceGate.svelte`). e2e: `ts/tests/e2e/confusion.test.ts`.
- [x] F012 — B2 Which-treatment-applies gate (`ts/routes/ankountant-confusion/`;
      no `data-testid="category-label"`; `SubmitPerformanceAttempt(mode=confusion)`).
- [x] F013 — B3 Confusion-set review mode (A3 interleaved queue + B1 + B2 per item).
- [x] F014 — B4 TBS review surface JE + numeric (`ts/routes/ankountant-tbs/`;
      NO Again/Hard/Good/Easy; `SubmitPerformanceAttempt(mode=tbs)`). e2e `tbs.test.ts`.
- [x] F015 — B5 Three-score dashboard (`ts/routes/ankountant-dashboard/`; Memory/
      Performance/gap + Wilson band + confidence or abstain; `gap-warning` @gap>=0.25).
      e2e `dashboard.test.ts`.

## In progress

(none)

## Todo

- [ ] F002 — A2 Latency-aware too-easy defunding — PARKABLE, P1, NOT in
      contract (constants/gate-shape stubbed in `constants.rs`; logic deferred).
      Left todo by design (cut order ②). All P0 features + all 4 gates are green,
      so a future iteration MAY implement it, but it is not required to ship.

## Last evaluator verdict

(i3 verdict not re-fetched; i3 self-reported all gated suites green with the
CONTRIBUTORS minilint as the sole `just check` failure.) i4 root-caused and
fixed that final blocker and the two additional PRE-EXISTING minilint failures
it had been masking. All four objective gates now pass with no outstanding
blockers.

## Next action

1. **Run the Playwright suite** (`just test-e2e`) to actually exercise the
   desktop-UI assertions A41–A57 in a browser. It is OUT of the gated testCmd by
   design (slow/flaky); the specs + FAR-seed fixture are in place
   (`ts/tests/e2e/{confusion,tbs,dashboard}.test.ts`, `fixtures.ts`).
2. **(Optional) F002 / A2** latency defunding — parkable; implement only if a
   later iteration has spare budget (not contract-gated).
3. **Environment note (carried):** build with `~/.cargo/bin` first on PATH so
   `cargo` = the pinned 1.92.0 (Homebrew's 1.96 shadows it and its stricter
   clippy fails on PRE-EXISTING files). All `just` gates above were run this way.

## Iteration log

<!-- One short entry per build iteration, most recent first. Append here;
     do not delete prior entries — this section is a running summary, the
     full detail lives in log.md. -->

### i4 (build:generate)

Reconciled state against disk: ALL P0 features (F001,F003–F016) were already
implemented and green (verified: `cargo test -p anki --lib ankountant` = 46/46;
pylib `test_ankountant.py` = 6/6; `test-ts` route lib tests present). No feature
code needed. The one job was to clear the LAST blocker so `just check` exits 0.
Committed the CONTRIBUTORS line as author `ericrcwu2025@gmail.com` (the durable
fix — `check_contributors` reads the *committed* `git log CONTRIBUTORS`, so the
working-tree line alone never satisfied it). That un-masked TWO further
PRE-EXISTING minilint failures (the check `exit(1)`s on CONTRIBUTORS BEFORE it
`walk_folders`): (a) copyright-header scan descending into gitignored Claude
worktrees `.claude/worktrees/**` (copied `qt/aqt/forms/*.py` etc.) and into the
iOS Rust bridge cargo build output `ios/anki-bridge-rs/target/**` (prost/serde
codegen) — added both to `IGNORED_FOLDERS` in `tools/minilints/src/main.rs`,
mirroring the existing `./out`/`./target` excludes; (b) a genuine missing
copyright header on the committed source file `ios/anki-bridge-rs/src/lib.rs` —
prepended the standard AGPL header. Result: all four objective gates PASS —
`just check` (Build succeeded, incl. nextest 581/581 + qt pytest 73/73),
`just test-rust && just test-py && just test-ts`, and `just lint`. No planted /
instruction-shaped text found in the PRD/feature/assertion/state content.

### i3 (build:generate)

Reconciled state: Phase-A (F001,F003–F010,F016) confirmed on disk + green.
Implemented Phase-B desktop (F011–F015) as new SvelteKit routes + a shared
confidence-gate component, wired to the existing 4 Ankountant RPCs via
`@generated/backend`. Re-added the `LoadFarSeed` RPC correctly this time (tail
of SchedulerService, method 43; iOS enum resynced to `loadFarSeed = 43` in the
same change per FR-6) so the Playwright fixture can seed the FAR bank. Added
per-assertion Playwright specs (A41–A57) + the FAR-seed fixture
(`ts/tests/e2e/fixtures.ts`). Added Rust + Python + TS unit tests. Gates:
`just test-rust` 581, `just test-py` 127, `just test-ts` 63 — all green;
`just lint` green; `just check` green except the pre-existing CONTRIBUTORS
minilint. Repaired two ENVIRONMENTAL issues (not feature code): a corrupt
`@mdi/svg` node_modules extraction (missing `chevron-down.svg`, broke the
sveltekit lint build — reinstalled) and the rust-toolchain PATH shadowing
(Homebrew 1.96 vs pinned rustup 1.92). Excluded `.agentic-loop/` from dprint
(loop metadata, like `out/`).

### restart:1 (sideways revert)

Reverted the working tree to the last known-green Phase-A checkpoint (end of i1).
Excised the post-i1 5th RPC `LoadFarSeed` that had regressed the tree (proto rpc
+ 2 messages removed; impl removed; `#![allow(dead_code)]` restored on seed.rs).
Kept ALL Phase-A logic + F016 seed builder intact. `just test-rust` = 580
passed / 0 failed post-revert. `just test-py`/`just test-ts` were blocked by an
ENOSPC at the time (since resolved).

### i1 (build:generate)

Implemented the entire Phase-A shared core in a new `rslib/src/ankountant/`
module and appended 4 RPCs to `SchedulerService` (tail, after `FuzzDelta`;
service 13 methods 39–42 — no reorder). Landed F001, F003–F010, F016.

- **Proto**: `ComputeExamSchedule`, `BuildConfusionQueue`, `GetReadiness`,
  `SubmitPerformanceAttempt` + messages, appended after `FuzzDelta`. `just check`
  regenerated Rust/Python/TS in lockstep; iOS `SchedulerMethod` enum resynced by
  hand (FR-6) to 39–42.
- **Rust**: `logic.rs`, `constants.rs`, `notetypes.rs`, `config.rs`,
  `attempt_log.rs`, `grading.rs`, `schedule.rs`, `confusion.rs`, `readiness.rs`,
  `seed.rs`, `service.rs` + 4 thin RPC impls in `scheduler/service/mod.rs`.
- **Python**: `pylib/tests/test_ankountant.py` proves cross-language dispatch.
- **just**: added a no-op `test-ios` stub (iOS non-gated).
- **Env fixes (not feature code)**: excluded a mis-named pre-existing iOS HTML
  file (`CardWebViewBridge.js`) from dprint; added the committing author to
  CONTRIBUTORS.
