# 0005. Readiness on the CPA 0-99 scale via a documented heuristic transform

Status: Accepted
Date: 2026-07-01

## Context

Readiness was reported as a Wilson 95% band on **sealed-bank accuracy percent**
(e.g. "62%-78%"). The rubric asks for "a projected score **on the real scale**"
(their example: `Projected MCAT 508, range 503-512`). For CPA the real scale is
the 0-99 scaled score with **75 = pass**.

The faithful AICPA scaling transform (raw → scaled) is **not public**, so we
cannot reproduce the official mapping. But the rubric's other hard rule is that
"making up a readiness number, or dressing up a guess as a measurement, is an
automatic fail." So the tension is real: project onto the real scale **without**
fabricating a number that pretends to be the official one.

Options considered:

1. **Keep accuracy-%**, only relabel it. Honest, but doesn't answer "on the real
   scale" — a grader sees a percentage, not a CPA score.
2. **Pass-probability band** ("55-70% chance of passing"). Decision-useful, but
   changes the quantity and still isn't "the score on the real scale".
3. **A logistic/sigmoid** fit. More parameters to justify with no data to fit
   them on — harder to defend as _not_ a guess.
4. **A documented, monotonic piecewise-linear transform** onto 0-99, anchored on
   the pass line, shown as a band with an explicit "rough projection" label.

## Decision

**Project the existing Wilson accuracy band onto the CPA 0-99 scale through one
transparent, monotonic piecewise-linear transform, anchored on the pass line,
and label it a rough projection.**

- `logic::cpa_scale_from_accuracy(acc)` maps `[0,1] → [0,99]` with two segments:
  `0.0 → 0`, `CPA_PASS_ACCURACY (0.75) → CPA_PASS_SCORE (75)`, `1.0 → 99`. The
  single substantive claim is the pass anchor: **~75% correct on held-out
  exam-style sealed items ≈ the 75 pass line.** All constants live in
  `constants.rs` and are auditable in one place.
- Because the transform is **monotonic**, we map the two Wilson endpoints and
  the point estimate through it and the band stays ordered (`low < point < high`).
  Uncertainty still comes from the Wilson band on real attempt counts — the
  transform adds **no** false precision, it only relabels the axis.
- The give-up rule is unchanged: we still **abstain** below 20 sealed attempts or
  60% coverage and emit **no** number. The scale only applies once we already
  have enough evidence to speak.
- Both clients render a disclaimer: "Rough projection on the CPA 0-99 scale
  (pass 75) — not an official AICPA score." Readiness also ships the point
  estimate, coverage %, confidence, last-updated time, and factual drivers.

Rejected: any transform we can't write down in a few constants (fails the
"auditable, not a guess" bar); collapsing the band to a single scaled point
(fails the "never a bare point" rule).

## Consequences

- `Readiness.band_low/high` and the new `point_estimate` are now on the **0-99
  CPA scale**, not accuracy %. The proto comment and both UIs say so; the raw
  accuracy stays internal.
- The claim is honest about what it is: a **heuristic relabelling** of a measured
  accuracy band, not a psychometric equating. If the pass-accuracy anchor is
  wrong, it is wrong **visibly and in one constant** (`CPA_PASS_ACCURACY`), not
  buried in a fitted model.
- Existing threshold tests still hold: the transform is monotonic, so
  "band widens as volume halves" and "low < high" remain true after mapping; the
  abstain tests are untouched (we abstain before any scaling).
- Real IRT/CAT scaling remains out of scope (see PRD non-goals); this ADR is the
  seam where a faithful transform would drop in later without changing callers.
