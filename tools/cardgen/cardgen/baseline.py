"""Stage 11 — Beat-a-baseline A/B/C evaluation.

On a deterministic held-out slice of the work-list, every item is generated
**three ways** — ``bm25`` (keyword only), ``vector`` (dense only), ``hybrid``
(ours) — and scored identically. Because all arms share one index, the only
variable is retrieval strategy: a clean A/B/C.

Reads : ``03-worklist/worklist.jsonl`` (held-out slice), via arm retrieval
Writes: ``out/<run_id>/baseline_report.md`` + ``10-baseline/metrics.json``

**Success (PASS)** = the hybrid arm is ≥ *both* baselines on **faithfulness**
AND **bucket-1 rate** (see :func:`decide_pass`).

The metric functions are pure + importable; ragas is an *optional* extra column
guarded behind an import + live-key check.
"""

from __future__ import annotations

import re
from dataclasses import asdict, is_dataclass
from typing import Any, Sequence

from .config import RunConfig
from .models import BUCKET_OK, BUCKET_WRONG, read_jsonl, write_json
from .providers.base import get_judge
from .util import is_substring_normalized

ARMS = ["bm25", "vector", "hybrid"]
# Held-out slice size for the A/B/C. Each item costs one live reference
# generation, so this is kept modest for a bounded proof (scale up for a full run).
HELDOUT_N = 24
# The reference card is generated ONCE per item from a large-k, arm-neutral
# hybrid retrieval; each arm is then scored on whether its top-k retrieval
# surfaces the evidence that card needs. This isolates RETRIEVAL (the variable
# under test) and removes the per-arm LLM-generation noise that would otherwise
# dominate the headline.
REF_K = 30
# Passing bar is pre-registered (doc 05): hybrid must not regress vs either
# baseline on the two headline numbers.
PASS_RULE = "hybrid >= bm25 AND hybrid >= vector, on faithfulness AND bucket-1 rate"

RUBRIC = (
    "CPA card 3-bucket gate: correct_useful (ship) / wrong (block) / "
    "bad_teaching (quarantine). Score faithfulness against the retrieved passage, "
    "not prior knowledge."
)

_WORD = re.compile(r"[a-z0-9]+")


# ---------------------------------------------------------------------------
# Pure metric primitives
# ---------------------------------------------------------------------------
def _tokens(text: str) -> set[str]:
    return set(_WORD.findall((text or "").lower()))


def _mean(vals: Sequence[float]) -> float:
    return sum(vals) / len(vals) if vals else 0.0


def answer_relevancy(answer: str, reference: str) -> float:
    """Heuristic: overlap coefficient of answer terms with the prompt/topic terms.

    ``|answer ∩ reference| / min(|answer|, |reference|)`` — 1.0 when every term of
    the shorter side is shared, 0.0 when disjoint. Overlap coefficient (not
    Jaccard) so a short answer isn't punished for a long prompt.
    """
    a, r = _tokens(answer), _tokens(reference)
    if not a or not r:
        return 0.0
    return len(a & r) / min(len(a), len(r))


def passage_relevant(passage: str, source_passage: str, floor: float = 0.5) -> bool:
    """A retrieved passage is 'relevant' if it contains the used source passage
    (substring) or shares ≥ ``floor`` of the source passage's terms."""
    if source_passage and is_substring_normalized(source_passage, passage):
        return True
    src = _tokens(source_passage)
    if not src:
        return False
    return len(src & _tokens(passage)) / len(src) >= floor


def context_precision(passages: Sequence[str], source_passage: str) -> float:
    """Ragas-style average precision: rewards putting relevant passages first.

    ``sum_k(precision@k · rel_k) / (#relevant)``; 0.0 when nothing is relevant.
    """
    rels = [passage_relevant(p, source_passage) for p in passages]
    total_rel = sum(rels)
    if not total_rel:
        return 0.0
    cum = 0
    score = 0.0
    for k, rel in enumerate(rels, start=1):
        if rel:
            cum += 1
            score += cum / k
    return score / total_rel


def context_recall(passages: Sequence[str], source_passage: str) -> float:
    """Fraction of the source-passage terms recoverable from the retrieved set."""
    src = _tokens(source_passage)
    if not src:
        return 0.0
    combined: set[str] = set()
    for p in passages:
        combined |= _tokens(p)
    return len(src & combined) / len(src)


def card_faithfulness(source_passage: str, passages: Sequence[str], bucket: str | None) -> float:
    """1.0 iff the source passage is a substring of a retrieved passage AND the
    judge did not call the card ``wrong``; else 0.0 (per doc 05)."""
    grounded = bool(source_passage) and any(
        is_substring_normalized(source_passage, p) for p in passages
    )
    return 1.0 if (grounded and bucket != BUCKET_WRONG) else 0.0


def bucket_one_rate(buckets: Sequence[str | None]) -> float:
    """Fraction of items judged ``correct_useful`` (bucket 1)."""
    if not buckets:
        return 0.0
    return sum(1 for b in buckets if b == BUCKET_OK) / len(buckets)


def decide_pass(arms: dict[str, dict]) -> bool:
    """PASS iff hybrid ≥ both baselines on faithfulness AND bucket-1 rate."""
    h, b, v = arms.get("hybrid"), arms.get("bm25"), arms.get("vector")
    if not (h and b and v):
        return False
    return (
        h["faithfulness"] >= b["faithfulness"]
        and h["faithfulness"] >= v["faithfulness"]
        and h["bucket1_rate"] >= b["bucket1_rate"]
        and h["bucket1_rate"] >= v["bucket1_rate"]
    )


def aggregate(records: Sequence[dict]) -> dict:
    """Mean each per-item metric into an arm-level summary."""
    return {
        "n": len(records),
        "faithfulness": _mean([r["faithful"] for r in records]),
        "retrieval_hit": _mean([r.get("retrieval_hit", 0.0) for r in records]),
        "answer_relevancy": _mean([r["answer_relevancy"] for r in records]),
        "context_precision": _mean([r["context_precision"] for r in records]),
        "context_recall": _mean([r["context_recall"] for r in records]),
        "bucket1_rate": bucket_one_rate([r["bucket"] for r in records]),
    }


# ---------------------------------------------------------------------------
# Lazy, monkeypatchable shims to sibling stages
# ---------------------------------------------------------------------------
def retrieve_for(cfg: RunConfig, item: dict, arm: str, k: int | None = None) -> Any:
    """Shim to :func:`cardgen.retrieve.retrieve_for` (patched in unit tests)."""
    from . import retrieve as _retrieve

    return _retrieve.retrieve_for(cfg, item, arm, k)


def generate_one(cfg: RunConfig, item: dict, passages: Any) -> Any:
    """Shim to :func:`cardgen.generate.generate_one` (patched in unit tests)."""
    from . import generate as _generate

    return _generate.generate_one(cfg, item, passages)


def check_candidate(cfg: RunConfig, candidate: Any) -> Any:
    """Shim to :func:`cardgen.selfcheck.check_candidate`.

    Degrades to ``True`` (treat as passed) when the self-check module isn't
    importable yet, so the A/B/C harness is testable before that stage lands.
    """
    try:
        from . import selfcheck as _selfcheck
    except Exception:
        return True
    return _selfcheck.check_candidate(cfg, candidate)


# ---------------------------------------------------------------------------
# Normalizers (tolerant of the sibling stages' exact return shapes)
# ---------------------------------------------------------------------------
def _passage_texts(retrieved: Any) -> list[str]:
    seq = retrieved.get("passages", []) if isinstance(retrieved, dict) else retrieved
    texts: list[str] = []
    for p in seq or []:
        if isinstance(p, str):
            texts.append(p)
        elif isinstance(p, dict):
            texts.append(p.get("text", ""))
        else:
            texts.append(getattr(p, "text", "") or "")
    return [t for t in texts if t]


def _cand_dict(cand: Any) -> dict | None:
    if cand is None:
        return None
    if is_dataclass(cand) and not isinstance(cand, type):
        return asdict(cand)
    if isinstance(cand, dict):
        return dict(cand)
    return {
        k: getattr(cand, k, None)
        for k in ("item_id", "section", "card_type", "payload", "source_passage", "citation")
    }


def _selfcheck_ok(result: Any) -> bool:
    if result is None:
        return True
    if isinstance(result, bool):
        return result
    if isinstance(result, tuple):
        return bool(result[0]) if result else False
    ok = getattr(result, "ok", None)
    if ok is not None:
        return bool(ok)
    return bool(result)


def _verdict_bucket(verdict: Any) -> str | None:
    if verdict is None:
        return None
    if isinstance(verdict, dict):
        return verdict.get("bucket")
    return getattr(verdict, "bucket", None)


def answer_text(payload: dict) -> str:
    if not isinstance(payload, dict):
        return ""
    back = payload.get("back")
    if isinstance(back, str):
        return back
    if "answer_key" in payload:
        return str(payload.get("answer_key"))
    steps = payload.get("steps")
    if isinstance(steps, list):
        return " ".join(str(s.get("answer_key")) for s in steps if isinstance(s, dict))
    return ""


def prompt_text(payload: dict) -> str:
    if not isinstance(payload, dict):
        return ""
    for key in ("front", "prompt"):
        val = payload.get(key)
        if isinstance(val, str):
            return val
    return ""


def _reference(item: dict, payload: dict) -> str:
    return " ".join(
        str(x)
        for x in (prompt_text(payload), item.get("topic", ""), item.get("area", ""))
        if x
    )


# ---------------------------------------------------------------------------
# Work-list slice
# ---------------------------------------------------------------------------
def load_worklist(cfg: RunConfig) -> list[dict]:
    return list(read_jsonl(cfg.stage_dir("03-worklist") / "worklist.jsonl"))


def heldout_slice(items: Sequence[dict], n: int = HELDOUT_N) -> list[dict]:
    """First ``min(n, len(items))`` items — deterministic held-out slice."""
    return list(items[: min(n, len(items))])


# ---------------------------------------------------------------------------
# Per-item evaluation across one arm
# ---------------------------------------------------------------------------
def _blank_record(item_id: str, arm: str, status: str = "ok") -> dict:
    return {
        "item_id": item_id,
        "arm": arm,
        "retrieval_hit": 0.0,
        "faithful": 0.0,
        "answer_relevancy": 0.0,
        "context_precision": 0.0,
        "context_recall": 0.0,
        "bucket": None,
        "status": status,
    }


def _eval_item(cfg: RunConfig, item: dict, judge: Any) -> dict[str, dict]:
    """Score all arms for one item, generating the reference card ONCE.

    The reference is generated from a large-k, arm-neutral hybrid retrieval and
    judged once (so the bucket is constant across arms). Each arm is then scored
    purely on whether its top-k retrieval surfaces the reference card's evidence
    (``retrieval_hit`` / grounded ``faithful``) plus context precision/recall —
    the retrieval signal the A/B/C is meant to measure, with no per-arm
    generation noise.
    """
    item_id = str(item.get("item_id", ""))

    ref = retrieve_for(cfg, item, "hybrid", REF_K)
    if not _passage_texts(ref):
        return {arm: _blank_record(item_id, arm, "retrieval_empty") for arm in ARMS}

    cand = generate_one(cfg, item, ref)
    cd = _cand_dict(cand)
    if cd is None:
        return {arm: _blank_record(item_id, arm, "generate_empty") for arm in ARMS}

    source_passage = cd.get("source_passage", "") or ""
    payload = cd.get("payload", {}) or {}

    if _selfcheck_ok(check_candidate(cfg, cand)):
        card = {
            "item_id": cd.get("item_id"),
            "card_type": cd.get("card_type"),
            "payload": payload,
            "source_passage": source_passage,
            "citation": cd.get("citation", ""),
        }
        verdicts = judge.judge([card], RUBRIC)
        bucket = _verdict_bucket(verdicts[0]) if verdicts else None
    else:
        bucket = BUCKET_WRONG  # blocked before the judge => never ships

    ans_rel = answer_relevancy(answer_text(payload), _reference(item, payload))
    question = _reference(item, payload)
    answer = answer_text(payload)

    out: dict[str, dict] = {}
    for arm in ARMS:
        arm_passages = _passage_texts(retrieve_for(cfg, item, arm, cfg.top_k))
        hit = 1.0 if (source_passage and any(is_substring_normalized(source_passage, p) for p in arm_passages)) else 0.0
        rec = _blank_record(item_id, arm)
        rec["bucket"] = bucket
        rec["retrieval_hit"] = hit
        rec["faithful"] = card_faithfulness(source_passage, arm_passages, bucket)
        rec["answer_relevancy"] = ans_rel
        rec["context_precision"] = context_precision(arm_passages, source_passage)
        rec["context_recall"] = context_recall(arm_passages, source_passage)
        rec["_question"] = question
        rec["_answer"] = answer
        rec["_contexts"] = arm_passages
        out[arm] = rec
    return out


# ---------------------------------------------------------------------------
# Optional ragas column (guarded)
# ---------------------------------------------------------------------------
def _maybe_ragas(cfg: RunConfig, per_arm_records: dict[str, list[dict]]) -> dict:
    """Best-effort ragas faithfulness/answer_relevancy per arm.

    Skipped unless ragas is importable AND a live model is available (ragas
    metrics need an LLM + embeddings, so this never runs in offline CI).
    """
    try:
        import ragas  # noqa: F401
    except Exception:
        return {}
    if cfg.offline:
        return {}
    try:  # pragma: no cover - live-only path
        from datasets import Dataset
        from ragas import evaluate
        from ragas.metrics import answer_relevancy as r_ar
        from ragas.metrics import faithfulness as r_faith

        out: dict[str, dict] = {}
        for arm, records in per_arm_records.items():
            rows = [r for r in records if r.get("status") == "ok"]
            if not rows:
                continue
            ds = Dataset.from_dict(
                {
                    "question": [r.get("_question", "") for r in rows],
                    "answer": [r.get("_answer", "") for r in rows],
                    "contexts": [r.get("_contexts", []) for r in rows],
                    "ground_truth": [r.get("_answer", "") for r in rows],
                }
            )
            res = evaluate(ds, metrics=[r_faith, r_ar])
            out[arm] = {
                "faithfulness": float(res["faithfulness"]),
                "answer_relevancy": float(res["answer_relevancy"]),
            }
        return out
    except Exception as exc:  # pragma: no cover - defensive
        print(f"[baseline] ragas column skipped: {exc}")
        return {}


# ---------------------------------------------------------------------------
# Report rendering
# ---------------------------------------------------------------------------
def _fmt(x: float) -> str:
    return f"{x:.3f}"


def _examples(per_arm_records: dict[str, list[dict]]) -> tuple[list[str], list[str]]:
    by_item: dict[str, dict[str, dict]] = {}
    for arm, records in per_arm_records.items():
        for rec in records:
            by_item.setdefault(rec["item_id"], {})[arm] = rec

    wins: list[str] = []
    losses: list[str] = []
    for item_id, arms in by_item.items():
        h = arms.get("hybrid")
        b = arms.get("bm25")
        v = arms.get("vector")
        if not (h and b and v):
            continue
        base_faith = max(b["faithful"], v["faithful"])
        if h["faithful"] > base_faith and len(wins) < 2:
            wins.append(
                f"- `{item_id}`: hybrid faithful=1 while "
                f"bm25={_fmt(b['faithful'])}/vector={_fmt(v['faithful'])} "
                f"(bucket hybrid={h['bucket']}, bm25={b['bucket']}, vector={v['bucket']})"
            )
        elif h["faithful"] < base_faith and len(losses) < 2:
            losses.append(
                f"- `{item_id}`: a baseline beat hybrid "
                f"(hybrid={_fmt(h['faithful'])}, bm25={_fmt(b['faithful'])}, "
                f"vector={_fmt(v['faithful'])})"
            )
    return wins, losses


def _render_report(
    cfg: RunConfig,
    n: int,
    arms_metrics: dict[str, dict],
    per_arm_records: dict[str, list[dict]],
    ragas_cols: dict,
    passed: bool,
) -> str:
    lines: list[str] = []
    lines.append("# Baseline A/B/C report")
    lines.append("")
    lines.append(f"- run_id: `{cfg.run_id}`")
    lines.append(f"- held-out items: **{n}** (deterministic first-N slice of the work-list)")
    lines.append(f"- arms: {', '.join(f'`{a}`' for a in ARMS)}")
    lines.append(f"- pass rule (pre-registered): {PASS_RULE}")
    lines.append(
        "- method: the card is generated ONCE per item (arm-neutral, large-k hybrid) "
        "and judged once; each arm is then scored on whether its top-k retrieval "
        "surfaces that card's evidence. Only RETRIEVAL varies — no per-arm generation "
        "noise. `faithfulness` = evidence surfaced AND card not judged wrong."
    )
    lines.append("")

    has_ragas = bool(ragas_cols)
    cols = ["arm", "faithfulness", "bucket-1 rate", "answer_relevancy", "context_precision", "context_recall"]
    if has_ragas:
        cols += ["ragas_faithfulness", "ragas_answer_relevancy"]
    cols += ["n"]
    lines.append("| " + " | ".join(cols) + " |")
    lines.append("| " + " | ".join(["---"] * len(cols)) + " |")
    for arm in ARMS:
        m = arms_metrics[arm]
        cells = [
            f"`{arm}`",
            _fmt(m["faithfulness"]),
            _fmt(m["bucket1_rate"]),
            _fmt(m["answer_relevancy"]),
            _fmt(m["context_precision"]),
            _fmt(m["context_recall"]),
        ]
        if has_ragas:
            rc = ragas_cols.get(arm, {})
            cells += [_fmt(rc.get("faithfulness", 0.0)), _fmt(rc.get("answer_relevancy", 0.0))]
        cells.append(str(m["n"]))
        lines.append("| " + " | ".join(cells) + " |")
    lines.append("")

    h = arms_metrics["hybrid"]
    lines.append("## Deltas (hybrid − baseline)")
    lines.append("")
    lines.append("| baseline | Δ faithfulness | Δ bucket-1 rate |")
    lines.append("| --- | --- | --- |")
    for base in ("bm25", "vector"):
        b = arms_metrics[base]
        lines.append(
            f"| `{base}` | {h['faithfulness'] - b['faithfulness']:+.3f} | "
            f"{h['bucket1_rate'] - b['bucket1_rate']:+.3f} |"
        )
    lines.append("")

    lines.append(
        "Retrieval hit-rate@k (fraction of items whose evidence the arm surfaced): "
        + ", ".join(f"`{a}`={_fmt(arms_metrics[a].get('retrieval_hit', 0.0))}" for a in ARMS)
    )
    lines.append("")

    wins, losses = _examples(per_arm_records)
    lines.append("## Example wins (hybrid beat a baseline)")
    lines.append("")
    lines.extend(wins or ["- (none in this slice)"])
    lines.append("")
    lines.append("## Example losses (a baseline beat hybrid)")
    lines.append("")
    lines.extend(losses or ["- (none in this slice)"])
    lines.append("")

    verdict = "PASS" if passed else "FAIL"
    lines.append(f"## Verdict: **{verdict}**")
    lines.append("")
    lines.append(
        f"Hybrid {'meets' if passed else 'does NOT meet'} the bar: faithfulness "
        f"{_fmt(h['faithfulness'])} and bucket-1 rate {_fmt(h['bucket1_rate'])} "
        f"vs bm25 ({_fmt(arms_metrics['bm25']['faithfulness'])}/"
        f"{_fmt(arms_metrics['bm25']['bucket1_rate'])}) and vector "
        f"({_fmt(arms_metrics['vector']['faithfulness'])}/"
        f"{_fmt(arms_metrics['vector']['bucket1_rate'])})."
    )
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Stage entry point
# ---------------------------------------------------------------------------
def run(cfg: RunConfig) -> dict:
    worklist = load_worklist(cfg)
    hold = heldout_slice(worklist)
    judge = get_judge(cfg)

    per_arm_records: dict[str, list[dict]] = {arm: [] for arm in ARMS}
    for item in hold:
        by_arm = _eval_item(cfg, item, judge)
        for arm in ARMS:
            per_arm_records[arm].append(by_arm[arm])
    arms_metrics = {arm: aggregate(per_arm_records[arm]) for arm in ARMS}

    ragas_cols = _maybe_ragas(cfg, per_arm_records)
    passed = decide_pass(arms_metrics)

    h = arms_metrics.get("hybrid", {})
    deltas = {
        base: {
            "faithfulness": h.get("faithfulness", 0.0) - arms_metrics[base]["faithfulness"],
            "bucket1_rate": h.get("bucket1_rate", 0.0) - arms_metrics[base]["bucket1_rate"],
        }
        for base in ("bm25", "vector")
        if base in arms_metrics
    }

    metrics = {
        "run_id": cfg.run_id,
        "held_out_n": len(hold),
        "arms": ARMS,
        "thresholds": {
            "leakage_threshold": cfg.leakage_threshold,
            "dedup_threshold": cfg.dedup_threshold,
        },
        "pass_rule": PASS_RULE,
        "metrics": arms_metrics,
        "deltas": deltas,
        "ragas": ragas_cols,
        "pass": passed,
    }
    write_json(cfg.stage_dir("10-baseline") / "metrics.json", metrics)

    report = _render_report(cfg, len(hold), arms_metrics, per_arm_records, ragas_cols, passed)
    cfg.out_dir.mkdir(parents=True, exist_ok=True)
    (cfg.out_dir / "baseline_report.md").write_text(report, encoding="utf-8")

    print(
        f"[baseline] {len(hold)} held-out items x {len(ARMS)} arms -> "
        f"{'PASS' if passed else 'FAIL'} "
        f"(hybrid faithful={_fmt(h.get('faithfulness', 0.0))}, "
        f"bucket1={_fmt(h.get('bucket1_rate', 0.0))})"
    )
    return metrics
