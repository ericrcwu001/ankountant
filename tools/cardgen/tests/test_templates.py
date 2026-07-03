"""Offline tests for the template / Automatic Item Generation stage.

    cd tools/cardgen && UV_PROJECT_ENVIRONMENT=.venv CARDGEN_OFFLINE=1 \
        uv run pytest tests/test_templates.py -q
"""

from __future__ import annotations

import yaml

import cardgen.config as config
from cardgen import selfcheck, templates
from cardgen.dedup import near_duplicate_clusters
from cardgen.models import read_json, write_jsonl

RECALL_PASSAGE = "The maximum amount of the enhanced deduction for seniors is $6,000 per person."
METHOD_PASSAGE = "The straight-line method allocates the depreciable base evenly over the asset's useful life."


def _cfg(tmp_path, monkeypatch, sections=None):
    monkeypatch.setattr(config, "ROOT", tmp_path)
    monkeypatch.setenv("CARDGEN_OFFLINE", "1")
    return config.RunConfig(run_id="tmpl_test", sections=sections or ["REG", "FAR"], offline=True)


def _write_family(cfg, name, obj):
    cfg.templates_dir.mkdir(parents=True, exist_ok=True)
    (cfg.templates_dir / name).write_text(yaml.safe_dump(obj), encoding="utf-8")


def _ingest(cfg, source_id, text):
    write_jsonl(
        cfg.stage_dir("00-ingest") / f"{source_id}.jsonl",
        [{"source_id": source_id, "locator": "p1", "heading_path": "", "text": f"Intro. {text} End."}],
    )


def test_recall_expand_grounded_and_selfcheck(tmp_path, monkeypatch) -> None:
    cfg = _cfg(tmp_path, monkeypatch)
    _ingest(cfg, "irs_test", RECALL_PASSAGE)
    _write_family(cfg, "thresh.yaml", {
        "template_id": "reg_thresh", "card_type": "recall", "skill_level": "R&U",
        "section": "REG", "topic": "{topic}", "citation": "{cite}",
        "front": "For {tax_year}, {q}", "back": "{a} (Source: {cite})", "variant_key": "{row_id}",
        "rows": [{
            "row_id": "senior", "tax_year": 2025, "topic": "deductions", "q": "what is the max?",
            "a": "$6,000 per person", "cite": "IRS Pub 17 (2025), p.94",
            "source_id": "irs_test", "locator": "p1", "source_passage": RECALL_PASSAGE, "license": "public",
        }],
    })

    templates.run(cfg)

    files = list(cfg.stage_dir("05-candidates").glob("*.json"))
    assert len(files) == 1
    c = read_json(files[0])
    assert c["card_type"] == "recall"
    assert c["payload"]["front"].startswith("For 2025,")
    assert c["source_id"] == "irs_test" and c["source_passage"] == RECALL_PASSAGE
    assert c["gen_method"]["method"] == "template" and c["gen_method"]["license"] == "public"
    assert any(t.startswith("sec::REG") for t in c["tags"])
    ok, reason = selfcheck.check_candidate(cfg, c)
    assert ok, reason
    # Deterministic item_id: re-running yields the same file.
    templates.run(cfg)
    assert len(list(cfg.stage_dir("05-candidates").glob("*.json"))) == 1


def test_numeric_formula_and_money_render(tmp_path, monkeypatch) -> None:
    cfg = _cfg(tmp_path, monkeypatch, sections=["FAR"])
    _ingest(cfg, "openstax", METHOD_PASSAGE)
    _write_family(cfg, "dep.yaml", {
        "template_id": "far_depr", "card_type": "tbs_numeric", "skill_level": "Application",
        "section": "FAR", "topic": "Depreciation", "citation": "{cite}",
        "prompt": "Compute annual straight-line depreciation for an asset costing ${cost:money}.",
        "exhibits": [{"title": "Data", "kind": "text", "body": "Cost {cost}, salvage {salvage}, life {life} years."}],
        "steps": [{"id": "c1", "kind": "numeric", "label": "Annual depreciation", "weight": 1.0,
                    "tolerance": 1, "answer_formula": {"fn": "straight_line", "args": ["cost", "salvage", "life"]}}],
        "variant_key": "{row_id}",
        "rows": [{
            "row_id": "press", "cost": 58000, "salvage": 10000, "life": 5, "cite": "OpenStax Ch.11",
            "source_id": "openstax", "locator": "p1", "source_passage": METHOD_PASSAGE, "license": "personal_use",
        }],
    })

    templates.run(cfg)
    c = read_json(next(iter(cfg.stage_dir("05-candidates").glob("*.json"))))
    assert c["card_type"] == "tbs_numeric"
    assert c["payload"]["steps"][0]["answer_key"] == 9600.0  # (58000-10000)/5
    assert "$58,000" in c["payload"]["prompt"]  # money formatting
    ok, reason = selfcheck.check_candidate(cfg, c)
    assert ok, reason


def test_grounding_drops_ungrounded_row(tmp_path, monkeypatch) -> None:
    cfg = _cfg(tmp_path, monkeypatch)
    _ingest(cfg, "irs_test", RECALL_PASSAGE)
    _write_family(cfg, "bad.yaml", {
        "template_id": "reg_bad", "card_type": "recall", "skill_level": "R&U", "section": "REG",
        "topic": "x", "citation": "c", "front": "Q {q}", "back": "A", "variant_key": "{row_id}",
        "rows": [{
            "row_id": "nope", "q": "?",
            "source_id": "irs_test", "locator": "p1",
            "source_passage": "This exact sentence does not appear anywhere in the ingested source text.",
            "license": "public",
        }],
    })
    templates.run(cfg)
    assert list(cfg.stage_dir("05-candidates").glob("*.json")) == []


def test_template_aware_dedup_keeps_distinct_variants() -> None:
    # Identical wording, but different template variant keys must NOT merge.
    texts = ["compute straight line depreciation for the asset", "compute straight line depreciation for the asset"]
    keys = ["far_depr::a", "far_depr::b"]
    assert near_duplicate_clusters(texts, [], 0.95, block_keys=keys) == [[0], [1]]
    # Same variant key (true duplicate) still merges; no keys => merges as before.
    assert near_duplicate_clusters(texts, [], 0.95, block_keys=["k", "k"]) == [[0, 1]]
    assert near_duplicate_clusters(texts, [], 0.95) == [[0, 1]]
