# Performance Model

## Purpose

Performance estimates whether the student can answer new exam-style questions, not whether they can repeat a studied card. It answers: "Can the learner apply the idea under exam-like wording and constraints?"

This is the bridge between flashcard memory and score readiness.

## Inputs

- Sealed exam-style items that are not part of the normal study pile.
- Confusion-choice attempts, TBS attempts, partial credit, confidence, and latency.
- Attempt Log notes written by `SubmitPerformanceAttempt`.
- Topic coverage and deep-structure tags such as `ds::lease::operating` or `ds::revrec::step4`.

## Output

The app reports Performance as a topic-level probability with a range. Each topic payload includes:

- point estimate,
- low/high range,
- timing and partial-credit effects,
- confidence-sensitive reasons,
- contribution to the Memory minus Performance gap.

## Give-Up Rule

Performance abstains when sealed evidence is too thin. The overall readiness score also gives up when there are fewer than 20 sealed attempts or less than 60% topic coverage.

When the backend abstains, it keeps reasons and evidence fields but clears score fields so the UI cannot display a fake number.

## Evidence

- `docs_ankountant/evidence/models.html` reports held-out Performance accuracy on disjoint exam-style outcomes.
- `docs_ankountant/evidence/paraphrase.html` shows Performance follows reworded sealed-item accuracy rather than copying Memory.
- `rslib/src/ankountant/tests.rs` covers sealed-only Performance, no study-pile leakage, TBS partial credit, and timing penalties.

## Known Limit

The current held-out Performance artifact is a deterministic backend fixture. It is useful for verifying the model pipeline, but it is not a longitudinal practice-test validation study.
