"""DAG driver. Each stage module exposes `run(cfg: RunConfig) -> None`.

    python -m cardgen.cli all --sections FAR,REG,AUD,BAR,ISC,TCP --target 900
    python -m cardgen.cli resume            # after the Cursor-subagent judge fills verdicts

Offline runs (no key / --offline) execute the whole DAG unattended (the offline
judge fills verdicts inline). Live runs pause after the judge queue is written so
the operator can drive the batched Cursor-subagent judge, then `resume`.
"""

from __future__ import annotations

import argparse
import importlib

from .config import SECTIONS, RunConfig

# `gold` calibrates the judge against the gold set (positives + planted negatives)
# and HALTS the run if the judge can't be trusted — it runs BEFORE `judge` grades
# the real ship queue ("fix the judge, not the generator, first").
PRE = ["ingest", "chunk", "index", "worklist", "retrieve", "generate", "selfcheck", "gold", "judge"]
POST = ["leakage", "dedup", "baseline", "emit"]

# Template (Automatic Item Generation) mode: expand curated templates x
# source-pinned data into candidates directly — no corpus retrieval, no per-card
# LLM. `ingest` runs only to provide 00-ingest text for grounding verification.
TEMPLATE_PRE = ["ingest", "templates", "selfcheck", "gold", "judge"]
TEMPLATE_POST = ["leakage", "dedup", "emit"]

STAGES = PRE + POST + ["templates"]


def _run_stage(name: str, cfg: RunConfig) -> None:
    mod = importlib.import_module(f".{name}", package="cardgen")
    run = getattr(mod, "run", None)
    if run is None:
        raise SystemExit(f"stage '{name}' has no run(cfg)")
    print(f"[cardgen] === stage: {name} ===")
    run(cfg)


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser("cardgen")
    ap.add_argument("stage", choices=[*STAGES, "all", "resume"])
    ap.add_argument("--sections", default=",".join(SECTIONS))
    ap.add_argument("--target", type=int, default=900)
    ap.add_argument("--run-id", default="proof")
    ap.add_argument("--offline", action="store_true")
    # Optional overrides (env/RunConfig defaults apply when omitted).
    ap.add_argument("--gen-model", default=None, help="override generator model (default gpt-5-mini)")
    ap.add_argument("--prompt-version", default=None, choices=["v1", "v2"])
    ap.add_argument("--no-rerank", action="store_true", help="disable the hybrid-arm reranker")
    ap.add_argument("--concurrency", type=int, default=None, help="live generation concurrency")
    ap.add_argument("--batch-api", action="store_true", help="use the OpenAI Batch API for generation")
    ap.add_argument("--judge-mode", default=None, choices=["full", "audit"])
    ap.add_argument("--judge-parallelism", type=int, default=None, help="parallel judge subagents/wave")
    ap.add_argument("--judge-batch", type=int, default=None, help="cards per judge batch file")
    ap.add_argument("--mode", default="rag", choices=["rag", "template"],
                    help="rag = LLM generation; template = expand curated templates (no per-card LLM)")
    args = ap.parse_args(argv)

    cfg = RunConfig(
        run_id=args.run_id,
        sections=[s.strip().upper() for s in args.sections.split(",") if s.strip()],
        target_total=args.target,
        offline=args.offline,
    )
    if args.gen_model:
        cfg.gen_model = args.gen_model
    if args.prompt_version:
        cfg.prompt_version = args.prompt_version
    if args.no_rerank:
        cfg.rerank = False
    if args.concurrency is not None:
        cfg.gen_concurrency = args.concurrency
    if args.batch_api:
        cfg.use_batch_api = True
    if args.judge_mode:
        cfg.judge_mode = args.judge_mode
    if args.judge_parallelism is not None:
        cfg.judge_parallelism = args.judge_parallelism
    if args.judge_batch is not None:
        cfg.judge_batch = args.judge_batch
    cfg.gen_source = args.mode
    pre, post = (TEMPLATE_PRE, TEMPLATE_POST) if cfg.gen_source == "template" else (PRE, POST)
    print(
        f"[cardgen] run_id={cfg.run_id} mode={cfg.gen_source} sections={cfg.sections} "
        f"target={cfg.target_total} offline={cfg.offline} gen_model={cfg.gen_model} "
        f"prompt={cfg.prompt_version} rerank={cfg.rerank} judge_mode={cfg.judge_mode}"
    )

    if args.stage == "all":
        for s in pre:
            _run_stage(s, cfg)
        if cfg.offline:
            for s in post:
                _run_stage(s, cfg)
        else:
            print(
                f"[cardgen] judge queue written under {cfg.out_dir}/07-judge/queue.\n"
                f"[cardgen] Drive the Cursor-subagent judge to fill 07-judge/verdicts, then:\n"
                f"[cardgen]   python -m cardgen.cli resume --run-id {cfg.run_id} --mode {cfg.gen_source}"
            )
    elif args.stage == "resume":
        for s in post:
            _run_stage(s, cfg)
    else:
        _run_stage(args.stage, cfg)


if __name__ == "__main__":
    main()
