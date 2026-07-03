"""Offline tests for the quality gate: self-check + judge + gold calibration."""

from __future__ import annotations

from pathlib import Path

import pytest

from cardgen import gold, judge, selfcheck
from cardgen.config import RunConfig
from cardgen.models import (
    BUCKET_OK,
    BUCKET_WRONG,
    MCQ,
    RECALL,
    TBS_DOC_REVIEW,
    TBS_JE,
    TBS_NUMERIC,
    TBS_RESEARCH,
    Verdict,
    read_json,
    read_jsonl,
    write_jsonl,
)

VALID = {
    RECALL: {"front": "Q?", "back": "A."},
    MCQ: {"prompt": "Which treatment?", "answer_key": "A", "treatments": ["A", "B"]},
    TBS_RESEARCH: {
        "prompt": "Cite the standard.",
        "exhibits": [{"title": "S", "kind": "text", "body": "x"}],
        "steps": [{"id": "citation", "kind": "citation", "answer_key": ["ASC 842-20-25-1"], "weight": 1.0}],
    },
    TBS_NUMERIC: {
        "prompt": "Compute.",
        "exhibits": [{"title": "D", "kind": "text", "body": "x"}],
        "steps": [{"id": "c1", "kind": "numeric", "answer_key": 100.0, "weight": 1.0}],
    },
    TBS_JE: {
        "prompt": "Record.",
        "exhibits": [{"title": "D", "kind": "text", "body": "x"}],
        "steps": [
            {"id": "l1", "kind": "je", "answer_key": {"account": "Cash", "side": "dr", "amount": 100.0}, "weight": 0.5},
            {"id": "l2", "kind": "je", "answer_key": {"account": "Rev", "side": "cr", "amount": 100.0}, "weight": 0.5},
        ],
    },
    TBS_DOC_REVIEW: {
        "prompt": "Review.",
        "exhibits": [
            {"id": "doc", "title": "Doc", "kind": "document", "role": "document",
             "body": 'Intro <blank step="s1">orig</blank> end.'}
        ],
        "steps": [
            {"id": "s1", "kind": "blank", "answer_key": "o1", "weight": 1.0, "original_text": "orig",
             "options": [{"id": "o1", "kind": "keep", "text": "keep"}, {"id": "o2", "kind": "replace", "text": "repl"}]}
        ],
    },
}


def _cand(card_type, payload, sp="grounded snippet here", cit="ASC 606-10-25"):
    return {
        "item_id": f"i_{card_type}",
        "section": "FAR",
        "card_type": card_type,
        "payload": payload,
        "source_passage": sp,
        "citation": cit,
    }


def _passages(sp):
    return [{"chunk_id": "c1", "text": f"Context. {sp}. More.", "source_id": "s", "locator": "p1", "score": 1.0}]


def test_selfcheck_valid_all_types():
    cfg = RunConfig(offline=True)
    for ct, payload in VALID.items():
        sp = "grounded snippet here"
        ok, reason = selfcheck.check_candidate(cfg, _cand(ct, payload, sp), _passages(sp))
        assert ok, f"{ct} should pass but failed: {reason}"


def test_selfcheck_invalid_cases():
    cfg = RunConfig(offline=True)
    sp = "grounded snippet here"
    ps = _passages(sp)

    ok, _ = selfcheck.check_candidate(cfg, _cand(RECALL, VALID[RECALL], sp, cit=""), ps)
    assert not ok, "empty citation must fail"

    ok, _ = selfcheck.check_candidate(cfg, _cand(RECALL, VALID[RECALL], "unrelated text not in passage"), ps)
    assert not ok, "ungrounded source_passage must fail"

    ok, _ = selfcheck.check_candidate(cfg, _cand(MCQ, {"prompt": "Q", "answer_key": "Z", "treatments": ["A", "B"]}, sp), ps)
    assert not ok, "mcq answer_key not in treatments must fail"

    two_step = {"prompt": "C", "steps": [
        {"id": "citation", "answer_key": ["x"], "weight": 0.5}, {"id": "extra", "weight": 0.5}]}
    ok, _ = selfcheck.check_candidate(cfg, _cand(TBS_RESEARCH, two_step, sp), ps)
    assert not ok, "research with 2 steps must fail"

    one_opt = {"prompt": "R", "exhibits": [{"role": "document", "body": '<blank step="s1">o</blank>'}],
               "steps": [{"id": "s1", "answer_key": "o1", "weight": 1.0, "options": [{"id": "o1"}]}]}
    ok, _ = selfcheck.check_candidate(cfg, _cand(TBS_DOC_REVIEW, one_opt, sp), ps)
    assert not ok, "doc_review with 1 option must fail"


def test_selfcheck_je_imbalance_warns_not_fails():
    cfg = RunConfig(offline=True)
    sp = "grounded snippet here"
    unbalanced = {"prompt": "Record.", "exhibits": [{"title": "D", "kind": "text", "body": "x"}],
                  "steps": [
                      {"id": "l1", "kind": "je", "answer_key": {"account": "Cash", "side": "dr", "amount": 100.0}, "weight": 0.5},
                      {"id": "l2", "kind": "je", "answer_key": {"account": "Rev", "side": "cr", "amount": 90.0}, "weight": 0.5},
                  ]}
    ok, _ = selfcheck.check_candidate(cfg, _cand(TBS_JE, unbalanced, sp), _passages(sp))
    assert ok, "unbalanced JE should WARN, not fail"


def test_judge_offline_grades(tmp_path, monkeypatch):
    monkeypatch.setattr("cardgen.config.ROOT", tmp_path)
    cfg = RunConfig(offline=True)
    passed = [
        _cand(RECALL, VALID[RECALL]),
        {"item_id": "bad", "section": "FAR", "card_type": RECALL,
         "payload": {"front": "q", "back": "__wrong__ figure"}, "source_passage": "sp", "citation": "c"},
    ]
    write_jsonl(cfg.stage_dir("06-checked") / "passed.jsonl", passed)
    graded_path = judge.ensure_graded(cfg)
    rows = {r["item_id"]: r for r in read_jsonl(graded_path)}
    assert rows["i_recall"]["bucket"] == BUCKET_OK
    assert rows["bad"]["bucket"] == BUCKET_WRONG


def test_gold_build_and_calibrate(tmp_path, monkeypatch):
    monkeypatch.setattr("cardgen.config.ROOT", tmp_path)
    real_seed = Path(__file__).resolve().parents[3] / "rslib" / "src" / "ankountant" / "seed_content.json"
    assert real_seed.exists(), f"seed content missing at {real_seed}"
    cfg = RunConfig(offline=True)

    by_sec = gold.build_gold(cfg, seed_path=real_seed)
    assert by_sec, "gold should not be empty"
    assert any(any(x["polarity"] == "negative" for x in items) for items in by_sec.values())

    res = gold.calibrate(cfg, seed_path=real_seed)
    assert res["positives"] > 0 and res["negatives"] > 0
    assert res["positives_pass_rate"] == 1.0, res
    assert res["negatives_recall"] == 1.0, res


def test_gold_run_writes_calibration_and_passes(tmp_path, monkeypatch):
    """The wired `gold` stage produces judge_calibration.json and passes the bar."""
    monkeypatch.setattr("cardgen.config.ROOT", tmp_path)
    cfg = RunConfig(offline=True)

    gold.run(cfg)  # offline judge: passes positives, catches planted negatives

    report = cfg.out_dir / "judge_calibration.json"
    assert report.exists(), "gold stage must write judge_calibration.json"
    data = read_json(report)
    assert data["positives"] > 0 and data["negatives"] > 0
    assert data["positives_pass_rate"] == 1.0 and data["negatives_recall"] == 1.0


def test_gold_run_halts_when_judge_misses_negatives(tmp_path, monkeypatch):
    """A judge that can't catch planted negatives HALTS the run (gate works)."""
    monkeypatch.setattr("cardgen.config.ROOT", tmp_path)
    cfg = RunConfig(offline=True)

    class _AllOkJudge:
        def judge(self, cards, rubric):
            return [Verdict(c["item_id"], BUCKET_OK, "ok", 1.0) for c in cards]

    monkeypatch.setattr("cardgen.gold.get_judge", lambda _cfg: _AllOkJudge())
    with pytest.raises(SystemExit):
        gold.run(cfg)
