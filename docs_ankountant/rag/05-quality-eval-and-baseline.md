# 5 — Quality, Eval & Beating the Baseline

[← Pipeline](04-generation-pipeline.md) · [Index](README.md) · Next: [Provenance, output & ops →](06-provenance-output-and-ops.md)

This is where "a wrong fact is worse than no card" becomes machinery. Three
independent gates stand between generation and a card reaching a candidate:
**self-check** (deterministic, [doc 4](04-generation-pipeline.md) stage 7), the
**quality gate** (judged), and **leakage/dedup**. This doc specifies the judged
gate, the metrics, and the assignment's **beat-a-baseline** requirement.

## The gold set (the ground truth)

Per section, a **human-verified gold set** of ~150–300 items:

- **Positive gold** — correct, well-taught Q&A with known citations. Used to
  _calibrate the judge_ (the judge must pass these) and to seed Ragas.
- **Negative gold** — deliberately wrong or subtly-off cards (wrong number,
  outdated standard, right-answer-bad-teaching). The judge **must catch these**.

If the judge can't reliably pass positives and fail negatives, the judge (not the
generator) is fixed first. The gold set is small enough to hand-verify and is the
only place humans are strictly required.

## The 3-bucket quality gate

Every generated card the self-check passes is scored by an **independent judge**
into exactly:

1. **Correct + useful** → eligible to ship.
2. **Wrong** → auto-blocked, logged with the reason. Non-negotiable.
3. **Correct but bad teaching** (ambiguous, trivial, leading, or two-facts-in-one)
   → quarantined; optionally reworked once, else dropped.

Rules that make the gate honest:

- **Cutoff pre-registered.** The passing bar (e.g. "≥ 0.9 of shipped cards are
  bucket-1 on the audited sample; 0 tolerated bucket-2 in the shipped set") is
  written down **before** looking at outputs.
- **Judge independence.** Different model/tier from the generator, distinct
  rubric prompt; grounded-faithfulness scored against the **retrieved passage**,
  not the judge's own memory (reduces shared-hallucination pass-through).
- **Judge calibration reported.** We publish the judge's precision/recall on the
  negative gold set so its verdicts are trustworthy.

## Ragas metrics

On sampled shipped cards + all baseline-comparison cards:

| Metric                | What it guards                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------ |
| **Faithfulness**      | card content is entailed by the retrieved passage (anti-hallucination; ties to provenance) |
| **Answer relevancy**  | the answer actually addresses the front/prompt                                             |
| **Context precision** | the retrieved passages were on-point (retriever quality)                                   |
| **Context recall**    | the passages contained what the card needed                                                |

Faithfulness is the headline number: a card can be _fluent and wrong_; only
faithfulness-to-source + citation makes it defensible under the provenance rule.

## Beating the baseline (assignment requirement)

On a **held-out slice** of the work-list, generate each item **three ways** and
score all three identically (Ragas + judge bucket rates):

| Arm                  | Retrieval                              | Purpose                        |
| -------------------- | -------------------------------------- | ------------------------------ |
| **Baseline-keyword** | BM25 only (LanceDB FTS)                | the "plain keyword search" bar |
| **Baseline-vector**  | dense only (Voyage)                    | the "plain vector search" bar  |
| **RAG (ours)**       | hybrid (BM25 + dense, fused, reranked) | the system under test          |

**Success = RAG's faithfulness + bucket-1 rate significantly exceed both
baselines** on the same items, with the comparison, sample size, and cutoffs
fixed in advance. The report (`out/baseline_report.md`) is a shippable artifact:
per-arm metrics, deltas, and example wins/losses. Because all three arms share
one LanceDB store, the only variable is the retrieval strategy — a clean A/B/C.

## Leakage & dedup (guarding the app's firewall)

- **Leakage** ([doc 4](04-generation-pipeline.md) stage 9): each candidate is
  ANN-queried against the **sealed performance bank** and the **held-out test
  set**; near-copies (cosine ≥ threshold, or high MinHash overlap) are dropped.
  This protects SPOV-5 — the sealed bank must stay a true held-out measure, so a
  study card that is a paraphrase of a sealed item would corrupt the readiness
  signal.
- **Dedup** (stage 10): within-corpus near-duplicate clustering; one survivor
  per cluster (highest judge score). Keeps the 50k _distinct_.

## No silent truncation

Every drop is logged with a reason (retrieval-empty, self-check-fail,
judge-wrong, judge-bad-teaching, leakage, dedup). The build emits a
`coverage_report.md`: per topic, `target vs generated vs shipped` and the drop
breakdown. A topic that under-delivers is **visible**, not hidden — the same
honesty principle the app's abstain rule embodies.

Next: [Provenance, output & ops →](06-provenance-output-and-ops.md)
