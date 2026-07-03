"""In-session Cursor-subagent judge (ADR 0009) — a file-based handshake.

The SHIPPING gate is judged by batched Cursor subagents the operator drives from
a Cursor session (NOT a hosted API, NOT the generator — independence via a
different provider+model). The stage writes independent batch files; parallel
judge subagents each grade a disjoint slice against the fixed rubric and write
verdict files; nothing collides.

- ``write_queue(cards, rubric, queue_dir)`` — write ``batch_NNN.json`` + ``RUBRIC.md``.
- ``read_verdicts(verdicts_dir)`` — ingest operator/subagent-filled verdicts.
- ``judge(cards, rubric)`` — a deterministic grounding-based fallback for INLINE
  callers that need a synchronous judge (e.g. the baseline A/B/C retrieval
  comparison, where the judge is identical across arms so the retrieval signal is
  what differentiates them). Shipped cards always go through the queue, not this.
"""

from __future__ import annotations

import json
from pathlib import Path

from ..config import RunConfig
from ..models import BUCKET_BAD, BUCKET_OK, BUCKET_WRONG, Verdict, read_json, write_json


class CursorSubagentJudge:
    def __init__(self, cfg: RunConfig) -> None:
        self.cfg = cfg

    def judge(self, cards: list[dict], rubric: str) -> list[Verdict]:
        out: list[Verdict] = []
        for c in cards:
            blob = json.dumps(c.get("payload", {}), ensure_ascii=False)
            if "__wrong__" in blob:
                out.append(Verdict(c["item_id"], BUCKET_WRONG, "wrong marker", 0.0))
            elif "__bad__" in blob:
                out.append(Verdict(c["item_id"], BUCKET_BAD, "bad-teaching marker", 0.5))
            elif not c.get("source_passage"):
                out.append(Verdict(c["item_id"], BUCKET_WRONG, "ungrounded", 0.0))
            else:
                out.append(Verdict(c["item_id"], BUCKET_OK, "grounded (inline fallback)", 1.0))
        return out

    def write_queue(self, cards: list[dict], rubric: str, queue_dir: str | Path) -> list[Path]:
        queue_dir = Path(queue_dir)
        queue_dir.mkdir(parents=True, exist_ok=True)
        (queue_dir / "RUBRIC.md").write_text(rubric, encoding="utf-8")
        batch = self.cfg.judge_batch or 25
        paths: list[Path] = []
        for i in range(0, len(cards), batch):
            p = queue_dir / f"batch_{i // batch:03d}.json"
            write_json(p, {"batch": i // batch, "rubric_ref": "RUBRIC.md", "cards": cards[i : i + batch]})
            paths.append(p)
        # A wave plan so the operator can fan out N parallel judge subagents at a
        # time (each subagent grades one batch, writing verdicts/<batch>.json).
        write_json(queue_dir / "plan.json", self.plan(paths))
        return paths

    def plan(self, batch_paths: list[Path]) -> dict:
        """Partition batches into waves of ``cfg.judge_parallelism`` for parallel
        Cursor judge subagents. Each subagent grades exactly one batch file."""
        names = [p.name for p in batch_paths]
        n = max(1, int(self.cfg.judge_parallelism or 1))
        waves = [names[i : i + n] for i in range(0, len(names), n)]
        return {
            "parallelism": n,
            "batch_count": len(names),
            "card_batch_size": self.cfg.judge_batch or 25,
            "waves": waves,
            "instructions": (
                "For each wave, launch one Cursor judge subagent per listed batch "
                "file IN PARALLEL. Each subagent: read RUBRIC.md + queue/<batch>.json, "
                "grade every card into correct_useful|wrong|bad_teaching judging "
                "FAITHFULNESS against each card's retrieved_passage, and write "
                "verdicts/<batch>.json as {\"verdicts\":[{item_id,bucket,reason,faithful}]}. "
                "Run waves sequentially; within a wave, batches are independent."
            ),
        }

    def read_verdicts(self, verdicts_dir: str | Path) -> list[Verdict]:
        verdicts_dir = Path(verdicts_dir)
        out: list[Verdict] = []
        if not verdicts_dir.exists():
            return out
        for p in sorted(verdicts_dir.glob("*.json")):
            data = read_json(p)
            rows = data.get("verdicts", []) if isinstance(data, dict) else data
            for r in rows or []:
                out.append(
                    Verdict(
                        r["item_id"],
                        r.get("bucket", BUCKET_OK),
                        r.get("reason", ""),
                        float(r.get("faithful", 1.0)),
                    )
                )
        return out
