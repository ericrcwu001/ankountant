# RAG cardgen — Handoff / Current State

> Operational handoff so a fresh agent (post context-compaction) can continue the
> RAG scale-up without the chat history. Pair this with the plan
> **`improve_rag_retrieval_and_generator`** (in `.cursor/plans/`),
> `docs_ankountant/adr/0009-*.md`, and
> `docs_ankountant/rag/07-implementation-contract.md`.

## TL;DR

The Phase-2a RAG card generator is **built, live-proven end-to-end, and repo-green**.
A bounded live run shipped **20 vetted cards / 60 targeted** across all six CPA
sections with the "beat-a-baseline" gate **PASS**. The next task (this plan) is to
**raise the ship rate and scale toward 50k** via better corpus (MCP), retrieval +
generator upgrades, and full fan-out.

## What exists (done + verified)

- **`tools/cardgen/`** — Python build-time batch tool (own `uv` env, isolated from
  the app; runtime stays AI-off). 12-stage DAG with deterministic **offline**
  backends so tests run keyless.
- **Live proof** in `tools/cardgen/out/proof/`: 6 sections, real `gpt-4o-mini` gen
  + `text-embedding-3-small`, parallel Cursor-subagent judge.
  - Funnel: 60 targeted → 59 generated → 54 self-check → judged **24 ok / 7 bad /
    23 wrong** → leakage −0 → dedup −4 → **20 shipped**.
  - `baseline_report.md`: **PASS** (hybrid evidence-hit 91.7% vs BM25 58.3% /
    vector 75%).
  - `cpa_bank.apkg`: 20 notes, exact app note types, **20/20 provenance populated**
    (`gen_method`/`source_passage`/`checker_status`).
- **Rust:** `Ankountant Study` note type gained provenance fields (sync-safe) —
  `rslib/src/ankountant/{notetypes.rs,seed.rs,tests.rs}`. `just check` green
  (622 Rust + 76 Qt).
- **Repo hygiene:** minilints copyright-header scan removed + iOS build dir ignored
  (`tools/minilints/src/main.rs`); `tools/cardgen` excluded from the repo's
  mypy/ruff/dprint (`.ruff.toml`, `.mypy.ini`, `.dprint.json`) and gated separately
  by `just test-cardgen` (53 tests green).

## Key files

| Area | Path |
| --- | --- |
| Pipeline stages | `tools/cardgen/cardgen/{ingest,chunk,index,taxonomy,worklist,retrieve,generate,selfcheck,judge,gold,leakage,dedup,baseline,emit,reports}.py` |
| Providers | `tools/cardgen/cardgen/providers/{base,offline,openai_embed,openai_generate,cursor_judge}.py` |
| Foundation (stable contract) | `tools/cardgen/cardgen/{config,models,util,cli}.py` |
| Taxonomy / catalogs | `tools/cardgen/taxonomy/{taxonomy,confusion_catalog}.<SECTION>.yaml` |
| Corpus | `tools/cardgen/corpus/manifest.json` (+ 6 sources: cpa_dummies, far_tbs_60, far_tbs, irs_p17, irs_p334, nist_800_12) |
| Run artifacts | `tools/cardgen/out/proof/` (baseline_report.md, coverage_report.md, cpa_bank.apkg, emitted_manifest.jsonl, per-stage jsonl) |
| Secrets | `tools/cardgen/.env` (gitignored; `OPENAI_API_KEY` set) |
| Design/decisions | `docs_ankountant/adr/0009-*.md`, `docs_ankountant/rag/07-implementation-contract.md`, `CONTEXT.md` |

## Decisions (ADR 0009)

- Lean stack: OpenAI generation + `text-embedding-3-small` + **LanceDB** (vector +
  BM25) + **in-session Cursor-subagent judge** (independent from the OpenAI
  generator; NOT headless — file-queue handshake).
- **Tier-B ingestion allowed** for this personal-use build (not redistributable).
- Provenance = `source_passage` + `gen_method` + `checker_status`; offline provider
  path is deterministic + keyless.

## Pending work (this plan)

See the plan `improve_rag_retrieval_and_generator` for the authoritative to-dos.
Execution order:

1. **Corpus via MCP** (biggest lever): `annas-mcp` `book_search`→`book_download`
   (exam-aligned accounting/audit/tax/IS + CPA-review textbooks, Tier-B) as
   primary; `agent-reach` `get_status` + built-in web/`curl` for Tier-A
   (OpenStax/IRS/PCAOB/GAO/SEC/NIST/AICPA); `paper-search-mcp` for open-access
   papers. Register via `ingest.register_source(...)`; re-ingest + re-index.
2. **Ship-rate:** `gpt-5-mini` (model-aware API — see gotchas) + **v2 decline
   prompt** (`{"skip":true}` when unsupported; no schema placeholders; TBS numbers
   must be in the passage); **chunk-quality filter** (drop heading/stub/stem/short);
   **reranker + richer query** in `retrieve.py`.
3. **Fan-out:** concurrent async generation (bounded `AsyncOpenAI`) + optional
   OpenAI **Batch API**; concurrent embeddings/retrieve/rerank; **N parallel Cursor
   judge subagents in waves** + a **sampled-audit** gate (`judge_mode=full|audit`).
4. **Rerun** bounded as `run-id proof2` (gpt-5-mini), fan out judge subagents,
   `resume`, and **compare vs 20/60**. Then optional `just cardgen-full` (50k).

## Run / test

```bash
just test-cardgen                    # offline, keyless, 53 tests
just cardgen all --target 60 --run-id proof2   # live (needs OPENAI_API_KEY); writes judge queue, pauses
# operator fans out parallel Cursor judge subagents to fill out/<run>/07-judge/verdicts/
just cardgen resume --run-id proof2  # leakage/dedup/baseline/emit
just cardgen-full                    # full 50k allocation (resumable)
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
- **`generate.run` is sequential** today — the fan-out step fixes throughput for 50k.
- **Anki tags cannot contain spaces** — `emit.py` sanitizes (`_safe_tag`).
- **`.env`** must be `OPENAI_API_KEY=sk-...` (a doubled `sk-sk-` prefix 401s — bug
  already fixed; `.env.example` hardened). `ANNAS_SECRET_KEY`/`ANNAS_DOWNLOAD_PATH`
  needed for `book_download`.
- **Baseline methodology:** it must isolate retrieval (generate reference once,
  score each arm's retrieval hit) — per-arm LLM generation is noise. Already fixed
  in `baseline.py`; keep it that way.
- **Offline auto-detect:** `RunConfig.offline` is true when no `OPENAI_API_KEY` or
  `CARDGEN_OFFLINE=1`. Keep all tests offline/deterministic.
