"""Offline tests for the fan-out / scale features.

Covers the concurrent generation driver (deterministic vs sequential), resume
idempotency, the judge audit-gate split, and the parallel judge wave plan. All
keyless/offline.

    cd tools/cardgen && UV_PROJECT_ENVIRONMENT=.venv CARDGEN_OFFLINE=1 \
        uv run pytest tests/test_scale.py -q
"""

from __future__ import annotations

import math
from pathlib import Path

import cardgen.config as config
from cardgen import generate, judge
from cardgen.config import RunConfig
from cardgen.models import BUCKET_OK, RECALL, read_jsonl, write_json, write_jsonl
from cardgen.providers.cursor_judge import CursorSubagentJudge
from cardgen.providers.offline import OfflineGenerator

_PASSAGE = {
    "chunk_id": "c1",
    "text": "Revenue is recognized when a performance obligation is satisfied.",
    "source_id": "s1",
    "locator": "p1",
    "score": 1.0,
}


def _setup_retrieved(cfg: RunConfig, n: int) -> None:
    items = []
    for i in range(n):
        iid = f"it{i}"
        items.append(
            {
                "item_id": iid,
                "section": "FAR",
                "area": "Revenue",
                "topic": "Revenue Recognition",
                "task_id": "t1",
                "skill_level": "R&U",
                "card_type": RECALL,
                "seed": i,
            }
        )
        write_json(
            cfg.stage_dir("04-retrieved") / f"{iid}.json",
            {"item_id": iid, "arm": "hybrid", "passages": [_PASSAGE]},
        )
    write_jsonl(cfg.stage_dir("03-worklist") / "worklist.jsonl", items)


# ---- generation fan-out ----------------------------------------------------
def test_generate_concurrent_matches_sequential(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(config, "ROOT", tmp_path)

    seq_cfg = config.RunConfig(run_id="seq", offline=True)
    _setup_retrieved(seq_cfg, 6)
    generate.run(seq_cfg)  # offline -> strictly sequential
    seq = {p.name: p.read_text() for p in seq_cfg.stage_dir("05-candidates").glob("*.json")}

    conc_cfg = config.RunConfig(run_id="conc", offline=True)
    _setup_retrieved(conc_cfg, 6)
    work = generate._collect_work(conc_cfg)
    written = generate._run_concurrent(conc_cfg, work, OfflineGenerator())
    conc = {p.name: p.read_text() for p in conc_cfg.stage_dir("05-candidates").glob("*.json")}

    assert written == 6
    assert set(seq) == set(conc) and len(seq) == 6
    for name in seq:  # concurrency must not change the (deterministic) output
        assert seq[name] == conc[name]


def test_generate_run_is_resumable(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(config, "ROOT", tmp_path)
    cfg = config.RunConfig(run_id="res", offline=True)
    _setup_retrieved(cfg, 4)

    generate.run(cfg)
    assert len(list(cfg.stage_dir("05-candidates").glob("*.json"))) == 4
    # Second pass: everything already generated -> no remaining work.
    assert generate._collect_work(cfg) == []


# ---- judge audit gate ------------------------------------------------------
def _passed(n: int) -> list[dict]:
    return [
        {
            "item_id": f"c{i}",
            "section": "FAR",
            "card_type": RECALL,
            "payload": {"front": "q", "back": "a"},
            "source_passage": "sp",
            "citation": "cite",
        }
        for i in range(n)
    ]


def test_audit_split_samples_and_is_deterministic() -> None:
    cfg = RunConfig(run_id="a", offline=True, judge_mode="audit")
    cfg.audit_min, cfg.audit_fraction = 3, 0.1
    passed = _passed(20)

    to_judge, autopass = judge._audit_split(cfg, passed)
    assert len(to_judge) == max(3, math.ceil(0.1 * 20))  # == 3
    assert len(autopass) == 20 - len(to_judge)
    assert {c["item_id"] for c in to_judge}.isdisjoint({c["item_id"] for c in autopass})
    # deterministic sample
    again, _ = judge._audit_split(cfg, passed)
    assert [c["item_id"] for c in again] == [c["item_id"] for c in to_judge]


def test_full_mode_judges_everything() -> None:
    cfg = RunConfig(run_id="f", offline=True)  # judge_mode defaults to full
    to_judge, autopass = judge._audit_split(cfg, _passed(10))
    assert len(to_judge) == 10 and autopass == []


def test_judge_audit_offline_grades_all(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr("cardgen.config.ROOT", tmp_path)
    cfg = RunConfig(run_id="aud", offline=True, judge_mode="audit")
    cfg.audit_min, cfg.audit_fraction = 2, 0.1
    write_jsonl(cfg.stage_dir("06-checked") / "passed.jsonl", _passed(10))

    graded = list(read_jsonl(judge.ensure_graded(cfg)))
    assert len(graded) == 10  # judged sample + autopassed remainder
    assert all(r["bucket"] == BUCKET_OK for r in graded)

    autopass = list(read_jsonl(cfg.stage_dir("07-judge") / "autopass.jsonl"))
    assert len(autopass) == 10 - max(2, math.ceil(0.1 * 10))  # == 8
    assert all(r["reason"].startswith("audit_autopass") for r in autopass)


# ---- judge wave plan -------------------------------------------------------
def test_judge_wave_plan_partitions() -> None:
    cfg = RunConfig(run_id="w", offline=True)
    cfg.judge_parallelism = 3
    plan = CursorSubagentJudge(cfg).plan([Path(f"batch_{i:03d}.json") for i in range(7)])
    assert plan["parallelism"] == 3 and plan["batch_count"] == 7
    assert [len(w) for w in plan["waves"]] == [3, 3, 1]


def test_write_queue_emits_plan_and_rubric(tmp_path) -> None:
    cfg = RunConfig(run_id="q", offline=True)
    cfg.judge_batch, cfg.judge_parallelism = 2, 2
    cards = [
        {"item_id": f"c{i}", "card_type": RECALL, "payload": {}, "source_passage": "x", "citation": "y"}
        for i in range(5)
    ]
    paths = CursorSubagentJudge(cfg).write_queue(cards, "RUBRIC BODY", tmp_path / "queue")
    assert len(paths) == 3  # ceil(5/2)
    assert (tmp_path / "queue" / "plan.json").exists()
    assert (tmp_path / "queue" / "RUBRIC.md").read_text() == "RUBRIC BODY"
