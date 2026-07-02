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

PRE = ["ingest", "chunk", "index", "worklist", "retrieve", "generate", "selfcheck", "judge"]
POST = ["leakage", "dedup", "baseline", "emit"]
STAGES = PRE + POST


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
    args = ap.parse_args(argv)

    cfg = RunConfig(
        run_id=args.run_id,
        sections=[s.strip().upper() for s in args.sections.split(",") if s.strip()],
        target_total=args.target,
        offline=args.offline,
    )
    print(f"[cardgen] run_id={cfg.run_id} sections={cfg.sections} target={cfg.target_total} offline={cfg.offline}")

    if args.stage == "all":
        for s in PRE:
            _run_stage(s, cfg)
        if cfg.offline:
            for s in POST:
                _run_stage(s, cfg)
        else:
            print(
                f"[cardgen] judge queue written under {cfg.out_dir}/07-judge/queue.\n"
                f"[cardgen] Drive the Cursor-subagent judge to fill 07-judge/verdicts, then:\n"
                f"[cardgen]   python -m cardgen.cli resume --run-id {cfg.run_id}"
            )
    elif args.stage == "resume":
        for s in POST:
            _run_stage(s, cfg)
    else:
        _run_stage(args.stage, cfg)


if __name__ == "__main__":
    main()
