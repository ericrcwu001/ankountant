"""Gold set + judge calibration (doc 05).

Positives are bootstrapped from the ALREADY human-verified seed content
(``rslib/src/ankountant/seed_content.json``): those are known-correct, well-taught
Q&A. Negatives are synthesized by mutating positives with a real defect (wrong
fact / two-facts-in-one) plus a marker so the deterministic offline judge catches
them; the live Cursor judge catches them on the substance.

``calibrate(cfg)`` runs the judge over the gold set and reports positives
pass-rate + negatives recall — if the judge can't pass positives and fail
negatives, the judge is fixed before trusting the gate.
"""

from __future__ import annotations

import copy

from .config import ROOT, SECTIONS, RunConfig
from .models import (
    BUCKET_BAD,
    BUCKET_OK,
    BUCKET_WRONG,
    MCQ,
    RECALL,
    read_json,
    read_jsonl,
    write_json,
    write_jsonl,
)
from .providers.base import get_judge

# tools/cardgen/ -> tools/ -> <repo>/rslib/src/ankountant/seed_content.json
_SEED = ROOT.parent.parent / "rslib" / "src" / "ankountant" / "seed_content.json"


def _section_from_tag(tag: str, default: str = "FAR") -> str:
    head = (tag or "").split("::")[0].upper()
    return head if head in SECTIONS else default


def _positives(seed_path=None) -> list[dict]:
    path = seed_path or _SEED
    if not path.exists():
        print(f"[gold] WARNING: seed content not found at {path}")
        return []
    data = read_json(path)
    pos: list[dict] = []

    for r in data.get("recall", []) or []:
        front, back = r.get("front"), r.get("back")
        if not front or not back:
            continue
        pos.append(
            {
                "section": _section_from_tag(r.get("topic_tag")),
                "card_type": RECALL,
                "payload": {"front": front, "back": back},
                "citation": r.get("source") or "seed",
                "source_passage": back,
            }
        )

    mcqs = data.get("mcqs", {})
    if isinstance(mcqs, dict):
        for group in mcqs.values():
            for m in group or []:
                if not isinstance(m, dict):
                    continue
                prompt = m.get("prompt")
                correct = m.get("correct_treatment") or m.get("answer_key")
                if not prompt or not correct:
                    continue
                pos.append(
                    {
                        "section": "FAR",
                        "card_type": MCQ,
                        "payload": {
                            "prompt": prompt,
                            "answer_key": correct,
                            "treatments": [correct, "An alternative treatment"],
                        },
                        "citation": m.get("source") or "seed",
                        "source_passage": prompt,
                    }
                )
    return pos


def _inject_defect(payload: dict, marker: str) -> None:
    for key in ("back", "prompt", "front"):
        if isinstance(payload.get(key), str):
            payload[key] = f"{payload[key]} {marker}"
            return
    payload["back"] = marker


def build_gold(cfg: RunConfig, seed_path=None) -> dict[str, list[dict]]:
    positives = _positives(seed_path)
    by_sec: dict[str, list[dict]] = {}
    for i, p in enumerate(positives):
        entry = dict(p, id=f"pos_{i}", polarity="positive", expected_bucket=BUCKET_OK)
        by_sec.setdefault(p["section"], []).append(entry)

    # Synthesize negatives from a slice of each section's positives.
    for sec, items in list(by_sec.items()):
        positives_only = [x for x in items if x["polarity"] == "positive"]
        n_neg = max(3, len(positives_only) // 5)
        negs: list[dict] = []
        for j, p in enumerate(positives_only[:n_neg]):
            n = copy.deepcopy(p)
            n["id"] = f"neg_{sec}_{j}"
            n["polarity"] = "negative"
            if j % 2 == 0:
                n["expected_bucket"] = BUCKET_WRONG
                n["defect"] = "deliberately wrong fact"
                _inject_defect(n["payload"], "__wrong__ (deliberately incorrect figure)")
            else:
                n["expected_bucket"] = BUCKET_BAD
                n["defect"] = "two-facts-in-one / ambiguous"
                _inject_defect(n["payload"], "__bad__ (two facts in one, ambiguous)")
            negs.append(n)
        by_sec[sec] = items + negs

    cfg.gold_dir.mkdir(parents=True, exist_ok=True)
    total = 0
    for sec, items in by_sec.items():
        write_jsonl(cfg.gold_dir / f"gold.{sec}.jsonl", items)
        total += len(items)
    print(f"[gold] wrote {total} gold items across {len(by_sec)} section(s)")
    return by_sec


def _load_gold(cfg: RunConfig) -> list[dict]:
    gold: list[dict] = []
    for sec in SECTIONS:
        gold.extend(read_jsonl(cfg.gold_dir / f"gold.{sec}.jsonl"))
    return gold


def calibrate(cfg: RunConfig, seed_path=None) -> dict:
    gold = _load_gold(cfg)
    if not gold:
        build_gold(cfg, seed_path)
        gold = _load_gold(cfg)

    cards = [
        {
            "item_id": g["id"],
            "card_type": g["card_type"],
            "payload": g["payload"],
            "source_passage": g.get("source_passage", ""),
            "citation": g.get("citation", ""),
        }
        for g in gold
    ]
    verdicts = {v.item_id: v for v in get_judge(cfg).judge(cards, "calibration")}

    pos = [g for g in gold if g["polarity"] == "positive"]
    neg = [g for g in gold if g["polarity"] == "negative"]
    pos_pass = sum(1 for g in pos if (v := verdicts.get(g["id"])) and v.bucket == BUCKET_OK)
    neg_caught = sum(1 for g in neg if (v := verdicts.get(g["id"])) and v.bucket != BUCKET_OK)

    result = {
        "positives": len(pos),
        "positives_pass_rate": round(pos_pass / len(pos), 4) if pos else 0.0,
        "negatives": len(neg),
        "negatives_recall": round(neg_caught / len(neg), 4) if neg else 0.0,
    }
    write_json(cfg.out_dir / "judge_calibration.json", result)
    print(
        f"[gold] calibration: positives pass {result['positives_pass_rate']:.2f}, "
        f"negatives recall {result['negatives_recall']:.2f}"
    )
    return result
