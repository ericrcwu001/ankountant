# RAG cardgen — Handoff / Current State

> Operational handoff so a fresh agent (post context-compaction) can continue the
> RAG scale-up without the chat history. Pair this with the plan
> **`improve_rag_retrieval_and_generator`** (in `.cursor/plans/`),
> `docs_ankountant/adr/0009-*.md`, and
> `docs_ankountant/rag/07-implementation-contract.md`.

## TL;DR

The Phase-2a RAG card generator is **built, live-proven end-to-end, and repo-green**.
The scale-up plan (`improve_rag_retrieval_and_generator`) is now **implemented**:
chunk-quality filter, `gpt-5-mini` model-aware generator + v2 decline prompt,
reranked retrieval with a richer query, full fan-out (concurrent generation +
Batch-API path + concurrent embeddings + parallel-judge wave plan + sampled-audit
gate), and a Tier-A corpus fetch helper. Offline suite: **71 passing**. Validated
end-to-end **offline** on a freshly-fetched real corpus (IRS/NIST/OpenStax);
the bounded **live** `gpt-5-mini` proof2 + full 50k run need an `OPENAI_API_KEY`
(and `ANNAS_SECRET_KEY` for Tier-B).

## What exists (done + verified)

- **`tools/cardgen/`** — Python build-time batch tool (own `uv` env, isolated from
  the app; runtime stays AI-off). 12-stage DAG with deterministic **offline**
  backends so tests run keyless.
- **Live proof** in `tools/cardgen/out/proof/`: 6 sections, real `gpt-4o-mini` gen
  - `text-embedding-3-small`, parallel Cursor-subagent judge.
  * Funnel: 60 targeted → 59 generated → 54 self-check → judged **24 ok / 7 bad /
    23 wrong** → leakage −0 → dedup −4 → **20 shipped**.
  * `baseline_report.md`: **PASS** (hybrid evidence-hit 91.7% vs BM25 58.3% /
    vector 75%).
  * `cpa_bank.apkg`: 20 notes, exact app note types, **20/20 provenance populated**
    (`gen_method`/`source_passage`/`checker_status`).
- **Rust:** `Ankountant Study` note type gained provenance fields (sync-safe) —
  `rslib/src/ankountant/{notetypes.rs,seed.rs,tests.rs}`. `just check` green
  (622 Rust + 76 Qt).
- **Repo hygiene:** minilints copyright-header scan removed + iOS build dir ignored
  (`tools/minilints/src/main.rs`); `tools/cardgen` excluded from the repo's
  mypy/ruff/dprint (`.ruff.toml`, `.mypy.ini`, `.dprint.json`) and gated separately
  by `just test-cardgen` (53 tests green).

## Key files

| Area                         | Path                                                                                                                                         |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Pipeline stages              | `tools/cardgen/cardgen/{ingest,chunk,index,taxonomy,worklist,retrieve,generate,selfcheck,judge,gold,leakage,dedup,baseline,emit,reports}.py` |
| Providers                    | `tools/cardgen/cardgen/providers/{base,offline,openai_embed,openai_generate,cursor_judge}.py`                                                |
| Foundation (stable contract) | `tools/cardgen/cardgen/{config,models,util,cli}.py`                                                                                          |
| Taxonomy / catalogs          | `tools/cardgen/taxonomy/{taxonomy,confusion_catalog}.<SECTION>.yaml`                                                                         |
| Corpus                       | `tools/cardgen/corpus/manifest.json` (+ 6 sources: cpa_dummies, far_tbs_60, far_tbs, irs_p17, irs_p334, nist_800_12)                         |
| Run artifacts                | `tools/cardgen/out/proof/` (baseline_report.md, coverage_report.md, cpa_bank.apkg, emitted_manifest.jsonl, per-stage jsonl)                  |
| Secrets                      | `tools/cardgen/.env` (gitignored; `OPENAI_API_KEY` set)                                                                                      |
| Design/decisions             | `docs_ankountant/adr/0009-*.md`, `docs_ankountant/rag/07-implementation-contract.md`, `CONTEXT.md`                                           |

## Decisions (ADR 0009)

- Lean stack: OpenAI generation + `text-embedding-3-small` + **LanceDB** (vector +
  BM25) + **in-session Cursor-subagent judge** (independent from the OpenAI
  generator; NOT headless — file-queue handshake).
- **Tier-B ingestion allowed** for this personal-use build (not redistributable).
- Provenance = `source_passage` + `gen_method` + `checker_status`; offline provider
  path is deterministic + keyless.

## Status of the scale-up plan (all code to-dos done)

| Plan item                                                                      | State                                                                                                               |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| chunk-quality filter (`chunk.py::_is_low_value`)                               | ✅ done (dropped 1002/2235 low-value chunks on the real corpus)                                                     |
| `gpt-5-mini` model-aware generator + `gpt-4o` fallback                         | ✅ done (`openai_generate.py`, `config.py`)                                                                         |
| v2 decline prompt (`{"skip":true}`, no placeholders, TBS numbers from passage) | ✅ done (+ `finalize_candidate` skip handling)                                                                      |
| richer query (confusion treatments) + hybrid-arm reranker                      | ✅ done (`retrieve.py`; LLM live, deterministic offline fallback)                                                   |
| fan-out: concurrent gen + Batch API + concurrent embeddings                    | ✅ done (`generate.py`, `providers/openai_batch.py`, `index.py`; offline stays sequential/deterministic; resumable) |
| scaled judging: wave plan + sampled-audit gate                                 | ✅ done (`cursor_judge.py::plan`, `judge.py::_audit_split`, `judge_mode=audit`)                                     |
| Tier-A corpus fetch/register                                                   | ✅ done (`scripts/fetch_corpus.py`; IRS/NIST/OpenStax registered + indexed)                                         |
| tests                                                                          | ✅ 71 offline tests green                                                                                           |
| **live** proof2 (gpt-5-mini) + parallel judge + compare                        | ⏳ needs `OPENAI_API_KEY` (validated **offline** end-to-end instead)                                                |
| **50k** full run (`just cardgen-full`)                                         | ⏳ allocation validated (50000 items across the 6 sections); full run needs key + broader corpus                    |

**Corpus MCP note:** `annas-mcp` / `agent-reach` / `paper-search-mcp` were **not
configured** in the build environment, so Tier-B ingestion is agent/MCP-driven
(use `scripts/fetch_corpus.py --register-local` to fold an MCP download into the
manifest). Tier-A was fetched over HTTP by the helper.

## Run / test

```bash
just test-cardgen                    # offline, keyless, 71 tests
uv run python scripts/fetch_corpus.py --reindex        # fetch Tier-A corpus + reindex (from tools/cardgen)
just cardgen all --target 60 --run-id proof2           # live (needs OPENAI_API_KEY); writes judge queue + queue/plan.json, pauses
# fan out parallel Cursor judge subagents (see queue/plan.json) to fill out/<run>/07-judge/verdicts/
just cardgen resume --run-id proof2  # leakage/dedup/baseline/emit
just cardgen-full                    # full 50k allocation (resumable/idempotent)
# scale knobs: --judge-mode audit  --concurrency 40  --batch-api  --no-rerank
just check                           # whole-repo gate (cardgen excluded)
```

## Gotchas / lessons

- **gpt-5-mini API:** reasoning models reject `temperature`/`seed`, use
  `max_completion_tokens` (+ optional `reasoning_effort`). Make `create(...)` kwargs
  model-aware in `openai_generate.py`; fall back to `gpt-4o` on 404.
- **Judge is in-session Cursor subagents**, not headless: `judge` stage (live)
  writes `07-judge/queue/batch_*.json` + `RUBRIC.md` and STOPS; you launch parallel
  Task subagents to write `07-judge/verdicts/batch_*.json`; then `resume`.
- **Live `just cardgen` commands trip Auto-review** — retry the identical Shell call
  with `request_smart_mode_approval: true` + the exact block reason.
- **Sandbox:** downloads / OpenAI calls need `full_network`; corpus writes to the
  gitignored `tools/cardgen/corpus/`.
- **`generate.run` fan-out:** live runs use a bounded-concurrency asyncio driver
  (`--concurrency`, default 24) or the OpenAI Batch API (`--batch-api`); **offline
  stays sequential + deterministic**. Generation is resumable (existing candidates
  are skipped), so interrupted 50k runs continue cheaply.
- **Anki tags cannot contain spaces** — `emit.py` sanitizes (`_safe_tag`).
- **`.env`** must be `OPENAI_API_KEY=sk-...` (a doubled `sk-sk-` prefix 401s — bug
  already fixed; `.env.example` hardened). `ANNAS_SECRET_KEY`/`ANNAS_DOWNLOAD_PATH`
  needed for `book_download`.
- **Baseline methodology:** it must isolate retrieval (generate reference once,
  score each arm's retrieval hit) — per-arm LLM generation is noise. Already fixed
  in `baseline.py`; keep it that way.
- **Offline auto-detect:** `RunConfig.offline` is true when no `OPENAI_API_KEY` or
  `CARDGEN_OFFLINE=1`. Keep all tests offline/deterministic.
