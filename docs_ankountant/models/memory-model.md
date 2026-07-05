# Memory Model

## Purpose

Memory estimates whether the student can recall study-pile material when the same idea appears again. It answers: "Does the learner remember the underlying fact or rule?"

Memory is intentionally separate from Performance and Readiness. A student can remember a flashcard and still miss a new exam-style question that asks for transfer, timing, or discrimination between similar treatments.

## Inputs

- Study-pile review history from Anki's scheduler.
- Recall outcome, rating, answer timing, and card state.
- Topic tags and cognitive-demand tags such as `cog::rote` and `cog::applied`.
- Per-topic trailing recall evidence used by the Ankountant readiness backend.

## Output

The app reports Memory as a topic-level probability with a range. Each topic payload includes:

- point estimate,
- low/high range,
- insufficient-evidence flag when the topic has too little recall data,
- topic identifier and display label,
- contribution to the Memory minus Performance gap.

## Give-Up Rule

Memory can be withheld at the topic level when the topic has too little recall evidence. When withheld, the backend clears the point and range fields for that topic instead of showing a misleading number.

Readiness has the stricter overall give-up rule: no readiness score with fewer than 20 sealed attempts or less than 60% topic coverage.

## Evidence

- `docs_ankountant/evidence/models.html` reports held-out Memory calibration with Brier score and log loss.
- `docs_ankountant/evidence/paraphrase.html` shows Memory can stay high while Performance drops on reworded sealed items.
- `pylib/tests/test_ankountant.py` checks Memory ranges and insufficient-topic behavior through the Python bridge.

## Known Limit

The current model evidence is a deterministic held-out fixture for Sunday verification. It proves the reporting and calibration mechanics, not real-student external validation.
