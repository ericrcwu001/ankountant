"""Stage 8 — the independent 3-bucket quality gate.

Offline: the deterministic judge grades inline. Live: the batched
Cursor-subagent queue is written and the stage STOPS; the operator fans out
parallel judge subagents (one per section / batch slice) to fill
``07-judge/verdicts/``, then ``resume`` ingests them.

``ensure_graded(cfg)`` (called by :mod:`cardgen.leakage`) returns the path to
``07-judge/graded.jsonl``, materializing it from the offline judge or the
operator-filled verdicts as needed.
"""

from __future__ import annotations

from pathlib import Path

from .config import RunConfig
from .models import read_jsonl, write_jsonl
from .providers.base import get_judge

RUBRIC = """You are an INDEPENDENT CPA-exam item reviewer. You did NOT write these cards.
Grade each card into EXACTLY one bucket:

- correct_useful : factually correct AND well-taught (clear, single-concept,
  unambiguous, exam-relevant). Ship it.
- wrong          : ANY factual error, wrong number, outdated/incorrect standard
  or citation, or a claim not entailed by the source. A wrong fact is worse than
  no card. Block it.
- bad_teaching   : correct but poorly taught — ambiguous, trivial, leading, or
  two-facts-in-one. Quarantine it.

Rules:
- Judge FAITHFULNESS against the card's source_passage / retrieved_passage, NOT
  your own memory. If a claim is not supported by the source, it is `wrong`.
- Re-check every number and citation against the source.
- Output one verdict per card: {"item_id","bucket","reason","faithful"} where
  faithful is 0.0-1.0 (how well the card is entailed by the source)."""


def _card_of(cand: dict) -> dict:
    return {
        "item_id": cand.get("item_id"),
        "card_type": cand.get("card_type"),
        "payload": cand.get("payload", {}),
        "source_passage": cand.get("source_passage", ""),
        "citation": cand.get("citation", ""),
    }


def _passed(cfg: RunConfig) -> list[dict]:
    return list(read_jsonl(cfg.stage_dir("06-checked") / "passed.jsonl"))


def _graded_path(cfg: RunConfig) -> Path:
    return cfg.stage_dir("07-judge") / "graded.jsonl"


def _merge(passed: list[dict], verdicts: dict) -> list[dict]:
    graded = []
    for c in passed:
        v = verdicts.get(c.get("item_id"))
        if v is None:
            continue  # unjudged never ships
        graded.append({**c, "bucket": v.bucket, "reason": v.reason, "faithful": v.faithful})
    return graded


def run(cfg: RunConfig) -> None:
    passed = _passed(cfg)
    if cfg.offline:
        judge = get_judge(cfg)
        verdicts = {v.item_id: v for v in judge.judge([_card_of(c) for c in passed], RUBRIC)}
        graded = _merge(passed, verdicts)
        # offline path never drops the unjudged (every card gets a verdict)
        write_jsonl(_graded_path(cfg), graded)
        print(f"[judge] offline graded {len(graded)} cards")
    else:
        from .providers.cursor_judge import CursorSubagentJudge

        cards = [dict(_card_of(c), retrieved_passage=c.get("source_passage", "")) for c in passed]
        qdir = cfg.stage_dir("07-judge") / "queue"
        paths = CursorSubagentJudge(cfg).write_queue(cards, RUBRIC, qdir)
        print(
            f"[judge] wrote {len(paths)} batch(es) of <= {cfg.judge_batch} cards to {qdir}.\n"
            f"[judge] Fan out parallel Cursor judge subagents to fill "
            f"{cfg.stage_dir('07-judge') / 'verdicts'}/, then: cardgen resume"
        )


def ensure_graded(cfg: RunConfig) -> Path:
    gp = _graded_path(cfg)
    if gp.exists():
        return gp
    if cfg.offline:
        run(cfg)
        return gp
    from .providers.cursor_judge import CursorSubagentJudge

    verdicts = {
        v.item_id: v
        for v in CursorSubagentJudge(cfg).read_verdicts(cfg.stage_dir("07-judge") / "verdicts")
    }
    graded = _merge(_passed(cfg), verdicts)
    write_jsonl(gp, graded)
    print(f"[judge] ingested {len(graded)} verdicts -> graded.jsonl")
    return gp
