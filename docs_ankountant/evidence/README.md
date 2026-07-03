# Ankountant — reproducible evidence artifacts

Self-contained HTML reports that back two rubric claims with runnable code, not
prose. Open the `.html` files directly in a browser.

| Artifact                               | Claim                                                                                                                                                                                                                                           | Emitter                                                          |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| [`determinism.html`](determinism.html) | #4 — the shared Rust backend is deterministic: identical inputs yield identical scores, confusion-queue order, and next-card interval recommendations; the only scheduling randomness (interval fuzz) is a pure function of `(card_id + reps)`. | `rslib/src/ankountant/determinism.rs::emit_determinism_evidence` |
| [`ablation.html`](ablation.html)       | #5 — the A2 too-easy defunding feature, tested OFF vs ON on the same cohort, lengthens intervals and cuts projected review load; non-rote cards are unaffected.                                                                                 | `rslib/src/ankountant/ablation.rs::emit_ablation_evidence`       |
| [`paraphrase.html`](paraphrase.html)   | #7d — Performance is not a copy of Memory: with study-pile recall held constant, Performance follows the reworded sealed-item accuracy and the memory-minus-performance gap opens only for the "memorizer" cohort.                              | `rslib/src/ankountant/paraphrase.rs::emit_paraphrase_evidence`   |

## Regenerate

```
just check            # once, so protobuf descriptors exist
just ankountant-evidence
```

The recipe runs the `#[ignore]`d Rust emitters. Each recomputes its numbers,
asserts the claim holds, writes `data/<name>.json`, and regenerates the
self-contained `<name>.html` (JSON inlined) from the template in
`rslib/src/ankountant/evidence/`. The same claims are also enforced as ordinary,
non-ignored tests in `just test-rust` (`determinism_*`, `a2_ablation_*`,
`paraphrase_*`).

`data/` holds the raw JSON records; the HTML files embed a copy inline so they
open with no server.
