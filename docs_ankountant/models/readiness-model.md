# Readiness Model

## Purpose

Readiness estimates the student's rough CPA FAR score today and how uncertain that estimate is. It answers: "If the student sat for the exam now, what score range should they expect?"

Readiness is derived from sealed Performance evidence, not raw flashcard recall alone.

## Inputs

- Sealed exam-style attempts by topic.
- Coverage across the FAR topic map.
- Timing, confidence, and partial-credit signals.
- Performance Wilson bands.
- The documented CPA 0-99 score transform from ADR 0005.

## Output

The app reports Readiness with:

- point estimate on the CPA 0-99 scale,
- low/high range,
- coverage percentage,
- confidence label,
- last updated time,
- main reasons,
- next study action.

## Give-Up Rule

Readiness shows no score unless both conditions are met:

- at least 20 sealed attempts,
- at least 60% topic coverage.

Below either line, the backend marks the response as abstained and clears the point/range fields. This is the core honesty rule: the app knows when it does not know.

## Evidence

- `docs_ankountant/adr/0005-cpa-scale-readiness-transform.md` documents the CPA 0-99 score mapping.
- `docs_ankountant/evidence/models.html` reports the held-out score mapping and range.
- `docs_ankountant/evidence/coverage-map.html` lists FAR topic coverage and the 60% coverage floor.
- `pylib/tests/test_ankountant.py`, `rslib/src/ankountant/tests.rs`, and iOS readiness tests cover ranges, abstention, reasons, and metadata.

## Known Limit

The CPA 0-99 mapping is a documented heuristic projection, not an official AICPA equating. Real-student practice-test validation remains future work.
