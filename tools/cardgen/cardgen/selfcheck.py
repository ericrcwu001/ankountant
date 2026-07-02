"""Stage 7 — deterministic self-check (cheap, no LLM).

Validates each candidate BEFORE spending judge effort: schema per card type,
grounding (source_passage is a real substring of a retrieved passage when
passages are available; else it must at least be non-empty — grounding is
already proven upstream in :mod:`cardgen.generate`), citation present, and the
TBS structural invariants (weights ~sum to 1.0; research has exactly one
citation step; doc-review blanks are well-formed; JE sides are dr/cr — an
unbalanced entry is WARNed, not failed, mirroring ``grading.rs`` which does not
enforce balance).

Public: ``check_candidate(cfg, candidate, passages=None) -> (ok, reason)`` — the
signature ``baseline.py`` calls with ``(cfg, candidate)``.
Reads : ``05-candidates/*.json`` (+ ``04-retrieved/<id>.json`` for passages)
Writes: ``06-checked/passed.jsonl`` + ``06-checked/dropped.jsonl``
"""

from __future__ import annotations

from dataclasses import asdict, is_dataclass
from typing import Any, Optional

from .config import RunConfig
from .models import (
    MCQ,
    RECALL,
    TBS_DOC_REVIEW,
    TBS_JE,
    TBS_NUMERIC,
    TBS_RESEARCH,
    read_json,
    write_jsonl,
)
from .util import is_substring_normalized

WEIGHT_TOL = 0.02
BALANCE_TOL = 0.01


def _as_dict(candidate: Any) -> dict:
    if is_dataclass(candidate) and not isinstance(candidate, type):
        return asdict(candidate)
    if isinstance(candidate, dict):
        return dict(candidate)
    return {
        k: getattr(candidate, k, None)
        for k in ("item_id", "section", "card_type", "payload", "source_passage", "citation")
    }


def _is_number(x: Any) -> bool:
    try:
        float(x)
        return True
    except (TypeError, ValueError):
        return False


def _weights_ok(steps: list[dict]) -> bool:
    ws = [float(s.get("weight", 0) or 0) for s in steps if isinstance(s, dict)]
    if not any(ws):  # no explicit weights => equal split assumed downstream
        return True
    return abs(sum(ws) - 1.0) <= WEIGHT_TOL


def _passage_texts(passages: Any) -> list[str]:
    out: list[str] = []
    for p in passages or []:
        if isinstance(p, dict):
            out.append(p.get("text", "") or "")
        else:
            out.append(getattr(p, "text", "") or "")
    return [t for t in out if t]


def check_candidate(
    cfg: RunConfig, candidate: Any, passages: Optional[list] = None
) -> tuple[bool, str]:
    c = _as_dict(candidate)
    ct = c.get("card_type")
    payload = c.get("payload") or {}
    sp = (c.get("source_passage") or "").strip()
    citation = (c.get("citation") or "").strip()

    if not ct:
        return False, "missing card_type"
    if not sp:
        return False, "empty source_passage (ungrounded)"
    if not citation:
        return False, "empty citation"

    if passages:
        texts = _passage_texts(passages)
        if texts and not any(is_substring_normalized(sp, t) for t in texts):
            return False, "source_passage not a substring of any retrieved passage"

    if ct == RECALL:
        if not payload.get("front") or not payload.get("back"):
            return False, "recall missing front/back"

    elif ct == MCQ:
        if not payload.get("prompt"):
            return False, "mcq missing prompt"
        treatments = payload.get("treatments") or []
        if not treatments or payload.get("answer_key") not in treatments:
            return False, "mcq answer_key not one of treatments"

    elif ct == TBS_RESEARCH:
        steps = payload.get("steps") or []
        if len(steps) != 1:
            return False, "research must have exactly one step"
        s0 = steps[0]
        if s0.get("id") != "citation":
            return False, "research step id must be 'citation'"
        acc = s0.get("answer_key")
        accepted = acc if isinstance(acc, list) else [acc]
        if not any(str(a).strip() for a in accepted):
            return False, "research missing accepted citations"
        if not _weights_ok(steps):
            return False, "research weights do not sum to 1.0"

    elif ct == TBS_NUMERIC:
        steps = payload.get("steps") or []
        if not steps:
            return False, "numeric missing steps"
        for s in steps:
            if not _is_number(s.get("answer_key")):
                return False, "numeric answer_key not a number"
        if not _weights_ok(steps):
            return False, "numeric weights do not sum to 1.0"

    elif ct == TBS_JE:
        steps = payload.get("steps") or []
        if not steps:
            return False, "je missing steps"
        dr = cr = 0.0
        for s in steps:
            ak = s.get("answer_key") or {}
            side = str(ak.get("side", "")).lower()
            if side not in ("dr", "cr"):
                return False, "je side must be dr/cr"
            if not _is_number(ak.get("amount")):
                return False, "je amount not a number"
            amt = float(ak.get("amount"))
            dr += amt if side == "dr" else 0.0
            cr += amt if side == "cr" else 0.0
        if not _weights_ok(steps):
            return False, "je weights do not sum to 1.0"
        if abs(dr - cr) > BALANCE_TOL:  # WARN, not fail (grading.rs doesn't enforce balance)
            print(f"[selfcheck] WARN {c.get('item_id')}: JE debits {dr} != credits {cr}")

    elif ct == TBS_DOC_REVIEW:
        steps = payload.get("steps") or []
        exhibits = payload.get("exhibits") or []
        doc = next((e for e in exhibits if str((e or {}).get("role")) == "document"), None)
        if not doc:
            return False, "doc_review missing document exhibit (role=document)"
        body = str(doc.get("body", ""))
        if not steps:
            return False, "doc_review missing steps"
        for s in steps:
            opts = s.get("options") or []
            ids = [o.get("id") for o in opts]
            if len(opts) < 2:
                return False, "doc_review blank needs >=2 options"
            if len(set(ids)) != len(ids):
                return False, "doc_review option ids not unique"
            if s.get("answer_key") not in ids:
                return False, "doc_review answer_key not an option id"
            sid = s.get("id")
            if f'step="{sid}"' not in body and f"[[{sid}]]" not in body:
                return False, f"doc_review blank {sid} not marked in document body"
        if not _weights_ok(steps):
            return False, "doc_review weights do not sum to 1.0"

    else:
        return False, f"unknown card_type {ct}"

    return True, ""


def run(cfg: RunConfig) -> None:
    cand_dir = cfg.stage_dir("05-candidates")
    retr_dir = cfg.stage_dir("04-retrieved")
    out_dir = cfg.stage_dir("06-checked")

    passed: list[dict] = []
    dropped: list[dict] = []
    for path in sorted(cand_dir.glob("*.json")):
        c = read_json(path)
        item_id = c.get("item_id", path.stem)
        rpath = retr_dir / f"{item_id}.json"
        passages = read_json(rpath).get("passages") if rpath.exists() else None
        ok, reason = check_candidate(cfg, c, passages)
        if ok:
            passed.append(c)
        else:
            dropped.append({"item_id": item_id, "reason": reason})

    write_jsonl(out_dir / "passed.jsonl", passed)
    write_jsonl(out_dir / "dropped.jsonl", dropped)
    print(f"[selfcheck] {len(passed)} passed, {len(dropped)} dropped")
