# Ankountant — reproducible evidence artifacts

Self-contained HTML reports that back six rubric claims with runnable code, not
prose. Open the `.html` files directly in a browser.

| Artifact                               | Claim                                                                                                                                                                                                                                               | Emitter                                                          |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [`determinism.html`](determinism.html) | #4 — the shared Rust backend is deterministic: identical inputs yield identical scores, confusion-queue order, and next-card interval recommendations; the only scheduling randomness (interval fuzz) is a pure function of `(card_id + reps)`.     | `rslib/src/ankountant/determinism.rs::emit_determinism_evidence` |
| [`ablation.html`](ablation.html)       | #5 — the A2 too-easy defunding feature, tested OFF vs ON on the same cohort, lengthens intervals and cuts projected review load; non-rote cards are unaffected.                                                                                     | `rslib/src/ankountant/ablation.rs::emit_ablation_evidence`       |
| [`paraphrase.html`](paraphrase.html)   | #7d — Performance is not a copy of Memory: with study-pile recall held constant, Performance follows the reworded sealed-item accuracy and the memory-minus-performance gap opens only for the "memorizer" cohort.                                  | `rslib/src/ankountant/paraphrase.rs::emit_paraphrase_evidence`   |
| [`models.html`](models.html)           | Sunday models — deterministic held-out split reproducibility, Memory calibration chart + Brier/log loss, held-out exam-style Performance accuracy, and CPA score mapping with a range.                                                              | `rslib/src/ankountant/models_evidence.rs::emit_models_evidence`  |
| [`undo.html`](undo.html)               | #7a — the Rust change keeps undo working and does not corrupt the collection: a representative op sequence (incl. the A2 flag written inside `answer_card`) fully round-trips through undo/redo and a database integrity check finds zero problems. | `rslib/src/ankountant/undo_evidence.rs::emit_undo_evidence`      |
| [`latency.html`](latency.html)         | #7h / §10 — the one-command benchmark: on a large deck the shared engine hits the p95 speed targets for answering, serving the next card, and powering the dashboard (reported as p50 / p95 / worst).                                               | `rslib/src/ankountant/latency.rs::emit_latency_bench`            |

## Regenerate

```
just check                       # once, so protobuf descriptors exist
just ankountant-evidence          # determinism, ablation, paraphrase, models, undo
just ankountant-bench             # default 10k-card release latency artifact
ANKOUNTANT_BENCH_CARDS=50000 just ankountant-bench
```

`ankountant-evidence` runs the `#[ignore]`d Rust emitters. Each recomputes its
numbers, asserts the claim holds, writes `data/<name>.json`, and regenerates the
self-contained `<name>.html` (JSON inlined) from the template in
`rslib/src/ankountant/evidence/`. Most claims are also enforced as ordinary,
non-ignored tests in `just test-rust` (`determinism_*`, `a2_ablation_*`,
`paraphrase_*`, `models_evidence_*`,
`undo_restores_state_and_collection_is_not_corrupt`,
`latency_harness_produces_ordered_percentiles`,
`evidence_html_artifacts_are_self_contained_readable_pages`).

`ankountant-bench` is separate because latency is only meaningful from an
optimized build; it measures the in-process Rust engine (no PyO3/IPC/render) and
records the build profile in the artifact. It reports pass/fail against the
targets but never gates on machine-dependent wall-clock numbers. The committed
`latency.json` is the headline release benchmark (`ANKOUNTANT_BENCH_CARDS=50000`,
50,921 total cards after the FAR seed). `ANKOUNTANT_BENCH_CARDS`,
`ANKOUNTANT_BENCH_ANSWERS` and `ANKOUNTANT_BENCH_DASH_ITERS` tune the sample
counts.

`data/` holds the raw JSON records; the HTML files embed a copy inline so they
open with no server.

## Mentor-facing index pages

- [`sunday-verification.html`](sunday-verification.html) — final requirement
  matrix and evidence index.
- [`ai-card-check.html`](ai-card-check.html) — 7f AI card check report with
  one-source 3-bucket counts, cutoff, gold set, baseline, and leakage proof.
- [`coverage-map.html`](coverage-map.html) — 7c FAR coverage map and abstain
  line.
- [`prompt-injection.html`](prompt-injection.html) — prompt-injection resistance
  evidence for hidden HTML sanitization, retrieved-passage delimiters, no tools,
  and JSON-only generation requests.
