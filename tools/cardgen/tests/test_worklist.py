"""Offline tests for stage 4 (taxonomy loaders + worklist allocation).

Run:
    cd tools/cardgen && UV_PROJECT_ENVIRONMENT=.venv CARDGEN_OFFLINE=1 \
        uv run pytest tests/test_worklist.py -q
"""

from __future__ import annotations

from collections import Counter

from cardgen.config import SECTIONS, RunConfig
from cardgen.models import (
    CARD_TYPES,
    MCQ,
    RECALL,
    TBS_DOC_REVIEW,
    TBS_JE,
    TBS_NUMERIC,
    TBS_RESEARCH,
    read_jsonl,
)
from cardgen import worklist
from cardgen.taxonomy import all_topics, load_confusion_catalog, load_taxonomy

# The original four FAR confusion sets shipped by the app (seed.rs `SETS` /
# config.rs CONFUSABLE map) — the pipeline MUST keep them verbatim while the
# full FAR catalog stays at the runtime app's 13 categories.
FAR_ANCHOR_SETS = {
    "capitalize_vs_expense",
    "operating_vs_finance_lease",
    "revrec_step_selection",
    "trading_afs_htm",
}
FAR_KNOWN_TAGS = {
    "capitalize_vs_expense": ["ds::cost::capitalize", "ds::cost::expense"],
    "operating_vs_finance_lease": ["ds::lease::operating", "ds::lease::finance"],
    "revrec_step_selection": ["ds::revrec::step4", "ds::revrec::step5"],
    "trading_afs_htm": ["ds::securities::trading", "ds::securities::htm"],
}
FAR_KNOWN_TREATMENTS = {
    "capitalize_vs_expense": ["Capitalize", "Expense"],
    "operating_vs_finance_lease": ["Operating lease", "Finance lease"],
    "revrec_step_selection": ["Allocate price (Step 4)", "Recognize revenue (Step 5)"],
    "trading_afs_htm": ["Trading (FV through NI)", "Held-to-maturity (amortized cost)"],
}

TBS_SHAPES = (TBS_RESEARCH, TBS_NUMERIC, TBS_JE, TBS_DOC_REVIEW)
RICH_CATEGORY_SECTIONS = ("AUD", "REG", "TCP", "ISC")


def _cfg(**kw) -> RunConfig:
    kw.setdefault("run_id", "test_worklist")
    kw.setdefault("offline", True)
    return RunConfig(**kw)


# ---- taxonomy + catalog loaders -------------------------------------------
def test_all_six_taxonomies_and_catalogs_load():
    cfg = _cfg()
    for section in SECTIONS:
        tax = load_taxonomy(cfg, section)
        assert tax["section"] == section
        areas = tax["areas"]
        assert areas, f"{section} has no areas"

        weight_sum = sum(float(a["weight"]) for a in areas)
        assert abs(weight_sum - 1.0) <= 0.02, f"{section} area weights sum to {weight_sum}"

        topics = all_topics(cfg, section)
        assert len(topics) >= 10, f"{section} has only {len(topics)} topics"
        for t in topics:
            assert t["skill_level"] in {"R&U", "Application", "Analysis", "Evaluation"}
            assert set(t) == {
                "section",
                "area",
                "area_weight",
                "group",
                "topic",
                "task_id",
                "skill_level",
            }

        catalog = load_confusion_catalog(cfg, section)
        assert catalog, f"{section} has an empty confusion catalog"
        for cs in catalog:
            assert cs["set_id"]
            assert cs["tags"] and all(tag.startswith("ds::") for tag in cs["tags"])
            assert cs["treatments"]
        if section == "FAR":
            assert len(catalog) == 13
        if section in RICH_CATEGORY_SECTIONS:
            assert len(catalog) >= 6, f"{section} has too few categories"


def test_evaluation_only_appears_in_aud():
    cfg = _cfg()
    for section in SECTIONS:
        levels = {t["skill_level"] for t in all_topics(cfg, section)}
        if section == "AUD":
            assert "Evaluation" in levels
        else:
            assert "Evaluation" not in levels, f"{section} must not use Evaluation"


def test_far_reuses_the_four_known_confusion_sets():
    cfg = _cfg()
    catalog = load_confusion_catalog(cfg, "FAR")
    by_id = {cs["set_id"]: cs for cs in catalog}
    assert FAR_ANCHOR_SETS <= set(by_id)
    for set_id, tags in FAR_KNOWN_TAGS.items():
        assert by_id[set_id]["tags"] == tags
        assert by_id[set_id]["treatments"] == FAR_KNOWN_TREATMENTS[set_id]


def test_task_ids_unique_within_section():
    cfg = _cfg()
    for section in SECTIONS:
        task_ids = [t["task_id"] for t in all_topics(cfg, section)]
        assert len(task_ids) == len(set(task_ids)), f"duplicate task_id in {section}"


# ---- worklist (stage 4) ----------------------------------------------------
def test_worklist_120_all_sections():
    cfg = _cfg(sections=list(SECTIONS), target_total=120)
    path = worklist.run(cfg)
    rows = list(read_jsonl(path))

    # total ~ target, allowing +/- one per section for two-level rounding.
    assert abs(len(rows) - 120) <= len(cfg.sections)

    # every requested section is present
    assert {r["section"] for r in rows} == set(SECTIONS)

    # all six card types appear across the run
    assert set(CARD_TYPES) <= {r["card_type"] for r in rows}

    # each row carries the full worklist schema
    for r in rows:
        assert set(r) == {
            "item_id",
            "section",
            "area",
            "topic",
            "task_id",
            "skill_level",
            "card_type",
            "seed",
            "category",
            "category_tags",
            "treatments",
        }
        assert r["card_type"] in CARD_TYPES
        assert r["category"]
        assert r["category_tags"] and all(t.startswith("ds::") for t in r["category_tags"])
        assert r["treatments"]

    # item_ids are globally unique
    ids = [r["item_id"] for r in rows]
    assert len(ids) == len(set(ids))


def test_worklist_per_section_tbs_shape_coverage():
    cfg = _cfg(sections=list(SECTIONS), target_total=120)
    rows = list(read_jsonl(worklist.run(cfg)))
    for section in SECTIONS:
        types = {r["card_type"] for r in rows if r["section"] == section}
        for shape in TBS_SHAPES:
            assert shape in types, f"{section} missing TBS shape {shape}"
        assert RECALL in types and MCQ in types, section


def test_far_worklist_mcq_uses_known_set_ids():
    cfg = _cfg(sections=["FAR"], target_total=120)
    rows = list(read_jsonl(worklist.run(cfg)))
    mcq_tasks = {r["task_id"] for r in rows if r["card_type"] == MCQ}
    assert mcq_tasks, "no FAR MCQ items generated"
    catalog_sets = {cs["set_id"] for cs in load_confusion_catalog(cfg, "FAR")}
    # every MCQ task_id is derived from a defined FAR category.
    for task_id in mcq_tasks:
        assert task_id.startswith("FAR.confusion.")
        assert task_id.removeprefix("FAR.confusion.") in catalog_sets


def test_worklist_carries_rich_category_metadata_for_visible_sections():
    cfg = _cfg(sections=list(SECTIONS), target_total=300)
    rows = list(read_jsonl(worklist.run(cfg)))
    by_section = {
        section: {r["category"] for r in rows if r["section"] == section}
        for section in RICH_CATEGORY_SECTIONS
    }
    for section, categories in by_section.items():
        assert len(categories) >= 6, f"{section} has sparse categories: {categories}"
    for r in rows:
        if r["card_type"] == MCQ:
            assert r["task_id"].endswith(r["category"])
            assert r["category_tags"]
            assert r["treatments"]


def test_section_targets_follow_doc2_weights():
    cfg = _cfg(sections=list(SECTIONS), target_total=120)
    targets = worklist.section_targets(cfg)
    # FAR is the biggest, ISC the smallest (doc-2 across-section weighting).
    assert targets["FAR"] == max(targets.values())
    assert targets["ISC"] == min(targets.values())
    assert sum(targets.values()) == 120


def test_worklist_is_deterministic():
    cfg1 = _cfg(sections=list(SECTIONS), target_total=120)
    rows1 = list(read_jsonl(worklist.run(cfg1)))
    cfg2 = _cfg(sections=list(SECTIONS), target_total=120)
    rows2 = list(read_jsonl(worklist.run(cfg2)))
    assert rows1 == rows2
    assert len(rows1) > 0


def test_worklist_seed_changes_item_seeds_not_structure():
    base = _cfg(sections=list(SECTIONS), target_total=120, seed=0)
    other = _cfg(sections=list(SECTIONS), target_total=120, seed=7)
    rows_a = list(read_jsonl(worklist.run(base)))
    rows_b = list(read_jsonl(worklist.run(other)))
    # same allocation (ids/types/topics), but per-item seeds differ.
    assert [r["item_id"] for r in rows_a] == [r["item_id"] for r in rows_b]
    assert [r["card_type"] for r in rows_a] == [r["card_type"] for r in rows_b]
    assert [r["seed"] for r in rows_a] != [r["seed"] for r in rows_b]
