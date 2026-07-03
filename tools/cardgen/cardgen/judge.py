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

import math
from pathlib import Path

from .config import JUDGE_AUDIT, RunConfig
from .models import BUCKET_OK, read_jsonl, write_jsonl
from .providers.base import get_judge
from .util import content_hash

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


def _autopass_path(cfg: RunConfig) -> Path:
    return cfg.stage_dir("07-judge") / "autopass.jsonl"


def _merge(passed: list[dict], verdicts: dict) -> list[dict]:
    graded = []
    for c in passed:
        v = verdicts.get(c.get("item_id"))
        if v is None:
            continue  # unjudged never ships
        graded.append({**c, "bucket": v.bucket, "reason": v.reason, "faithful": v.faithful})
    return graded


def _audit_split(cfg: RunConfig, passed: list[dict]) -> tuple[list[dict], list[dict]]:
    """In ``audit`` mode, split ``passed`` into (to_judge, autopass).

    ``to_judge`` is a deterministic sample of size ``max(audit_min,
    ceil(audit_fraction*N))`` (sampled by a stable hash of item_id); the rest are
    auto-passed on the strength of the deterministic self-check they already
    cleared. ``full`` mode judges everything (autopass empty).
    """
    if cfg.judge_mode != JUDGE_AUDIT:
        return passed, []
    n = len(passed)
    target = max(cfg.audit_min, math.ceil(cfg.audit_fraction * n))
    if target >= n:
        return passed, []
    ordered = sorted(passed, key=lambda c: content_hash(c.get("item_id", "")))
    to_judge = ordered[:target]
    judged_ids = {c.get("item_id") for c in to_judge}
    autopass = [c for c in passed if c.get("item_id") not in judged_ids]
    return to_judge, autopass


def _autopass_rows(autopass: list[dict]) -> list[dict]:
    """Graded-ready rows for the audit remainder (self-check gated => ship)."""
    return [
        {**c, "bucket": BUCKET_OK, "reason": "audit_autopass (self-check gated)", "faithful": 1.0}
        for c in autopass
    ]


def run(cfg: RunConfig) -> None:
    passed = _passed(cfg)
    to_judge, autopass = _audit_split(cfg, passed)
    autopass_rows = _autopass_rows(autopass)
    if autopass_rows:
        write_jsonl(_autopass_path(cfg), autopass_rows)

    if cfg.offline:
        judge = get_judge(cfg)
        verdicts = {v.item_id: v for v in judge.judge([_card_of(c) for c in to_judge], RUBRIC)}
        graded = _merge(to_judge, verdicts) + autopass_rows
        # offline path never drops the unjudged (every card gets a verdict)
        write_jsonl(_graded_path(cfg), graded)
        mode = f" (audit: judged {len(to_judge)}, autopassed {len(autopass_rows)})" if autopass_rows else ""
        print(f"[judge] offline graded {len(graded)} cards{mode}")
    else:
        from .providers.cursor_judge import CursorSubagentJudge

        cards = [dict(_card_of(c), retrieved_passage=c.get("source_passage", "")) for c in to_judge]
        qdir = cfg.stage_dir("07-judge") / "queue"
        paths = CursorSubagentJudge(cfg).write_queue(cards, RUBRIC, qdir)
        extra = (
            f" (audit mode: {len(autopass_rows)} card(s) auto-passed by self-check, "
            f"written to {_autopass_path(cfg).name})"
            if autopass_rows
            else ""
        )
        print(
            f"[judge] wrote {len(paths)} batch(es) of <= {cfg.judge_batch} cards to {qdir}{extra}.\n"
            f"[judge] See {qdir / 'plan.json'} for the parallel wave plan "
            f"({cfg.judge_parallelism} subagents/wave); fill "
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
    # Fold in any audit-mode auto-passed remainder (disjoint from judged ids).
    autopass_rows = list(read_jsonl(_autopass_path(cfg)))
    if autopass_rows:
        judged_ids = {r.get("item_id") for r in graded}
        graded += [r for r in autopass_rows if r.get("item_id") not in judged_ids]
    write_jsonl(gp, graded)
    print(f"[judge] ingested {len(graded)} verdicts -> graded.jsonl")
    return gp
