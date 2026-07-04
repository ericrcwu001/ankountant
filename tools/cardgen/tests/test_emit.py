"""Stage-12 emit tests — fully offline (no key, no network).

Builds a ``09-dedup/kept.jsonl`` fixture with one of every card_type, runs the
emitter, and asserts the produced ``.apkg`` is a real Anki package whose note
types mirror the app's field orders exactly (``notetypes.rs``), plus the
confusable patch + coverage report sidecars.
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import zipfile

import pytest

from cardgen import emit, reports
from cardgen.config import RunConfig
from cardgen.models import write_json, write_jsonl

# The exact app note-type field orders (rslib/src/ankountant/notetypes.rs).
STUDY_FIELDS = ["Front", "Back", "source_passage", "gen_method", "checker_status"]
TBS_FIELDS = [
    "tbs_type",
    "prompt",
    "exhibits_json",
    "steps_json",
    "schema_tag",
    "source_passage",
    "gen_method",
    "checker_status",
]

_GEN_METHOD = {
    "model": "offline",
    "prompt_version": "v1",
    "retrieval_config": "hybrid",
    "index_version": "test-idx",
    "arm": "hybrid",
    "seed": 0,
}


def _kept_rows() -> list[dict]:
    """One kept Candidate (+bucket) per card_type, with schema-valid payloads."""
    return [
        {
            "item_id": "far-recall-0001",
            "section": "FAR",
            "card_type": "recall",
            "payload": {
                "front": "When is revenue recognized under ASC 606?",
                "back": "When (or as) a performance obligation is satisfied.",
            },
            "source_passage": "Revenue is recognized when a performance obligation is satisfied.",
            "source_id": "openstax_far",
            "locator": "ch5:p2",
            "citation": "ASC 606-10-25",
            "gen_method": _GEN_METHOD,
            "tags": ["sec::FAR", "cog::rote", "topic::revenue_recognition"],
            "bucket": "correct_useful",
        },
        {
            "item_id": "far-mcq-0001",
            "section": "FAR",
            "card_type": "mcq",
            "payload": {
                "prompt": "A $5,000 overhaul extends a machine's useful life. Which treatment applies?",
                "answer_key": "Capitalize",
                "ds_tag": "ds::cost::capitalize",
                "treatments": ["Capitalize", "Expense"],
                "set_id": "capitalize_vs_expense",
            },
            "source_passage": "Costs that extend an asset's useful life are capitalized.",
            "source_id": "openstax_far",
            "locator": "ch9:p4",
            "citation": "ASC 360-10-30",
            "gen_method": _GEN_METHOD,
            "tags": ["sec::FAR", "ds::cost::capitalize"],
            "bucket": "correct_useful",
        },
        {
            "item_id": "far-research-0001",
            "section": "FAR",
            "card_type": "tbs_research",
            "payload": {
                "prompt": "Cite the standard governing lease classification by a lessee.",
                "exhibits": [
                    {"id": "e1", "title": "Scenario", "kind": "text", "body": "A lessee signs a 5-year lease."}
                ],
                "steps": [
                    {
                        "id": "citation",
                        "kind": "citation",
                        "answer_key": ["ASC 842-10-25"],
                        "weight": 1.0,
                        "label": "Governing citation",
                        "corpus_refs": [],
                        "granularity": "paragraph",
                    }
                ],
            },
            "source_passage": "Lease classification for a lessee is governed by ASC 842-10-25.",
            "source_id": "asc",
            "locator": "842-10-25",
            "citation": "ASC 842-10-25",
            "gen_method": _GEN_METHOD,
            # No set_id in payload → deck falls back to slug(topic) == "leases".
            "tags": ["sec::FAR", "ds::lease::finance", "topic::leases"],
            "bucket": "correct_useful",
        },
        {
            "item_id": "far-numeric-0001",
            "section": "FAR",
            "card_type": "tbs_numeric",
            "payload": {
                "prompt": "Compute the price allocated to the equipment (Step 4).",
                "exhibits": [
                    {"id": "e1", "title": "Data", "kind": "text", "body": "Standalone prices given."}
                ],
                "steps": [
                    {
                        "id": "c1",
                        "kind": "numeric",
                        "answer_key": 250000,
                        "weight": 1.0,
                        "label": "Allocated price",
                        "tolerance": 1.0,
                    }
                ],
                "set_id": "revrec_step_selection",
            },
            "source_passage": "The transaction price is allocated to each performance obligation.",
            "source_id": "asc",
            "locator": "606-10-32",
            "citation": "ASC 606-10-32",
            "gen_method": _GEN_METHOD,
            "tags": ["sec::FAR", "ds::revrec::step4", "topic::revenue_recognition"],
            "bucket": "correct_useful",
        },
        {
            "item_id": "far-je-0001",
            "section": "FAR",
            "card_type": "tbs_je",
            "payload": {
                "prompt": "Record the lease commencement entry.",
                "exhibits": [
                    {"id": "e1", "title": "Lease schedule", "kind": "text", "body": "See amortization table."}
                ],
                "steps": [
                    {"id": "l1", "kind": "je", "answer_key": {"account": "ROU Asset", "side": "dr", "amount": 10000}, "weight": 0.5},
                    {"id": "l2", "kind": "je", "answer_key": {"account": "Lease Liability", "side": "cr", "amount": 10000}, "weight": 0.5},
                ],
                "set_id": "operating_vs_finance_lease",
            },
            "source_passage": "At commencement the lessee records a right-of-use asset and a lease liability.",
            "source_id": "asc",
            "locator": "842-20-30",
            "citation": "ASC 842-20-30",
            "gen_method": _GEN_METHOD,
            "tags": ["sec::FAR", "ds::lease::finance"],
            # A non-OK bucket → checker_status must pass through verbatim.
            "bucket": "reworked",
        },
        {
            "item_id": "aud-docreview-0001",
            "section": "AUD",
            "card_type": "tbs_doc_review",
            "payload": {
                "prompt": "Review the memo and correct each blank.",
                "exhibits": [
                    {
                        "id": "doc",
                        "title": "Audit memo",
                        "kind": "document",
                        "role": "document",
                        "body": 'The team obtained <blank step="s1">sufficient</blank> appropriate evidence.',
                    }
                ],
                "steps": [
                    {
                        "id": "s1",
                        "kind": "blank",
                        "answer_key": "o1",
                        "weight": 1.0,
                        "label": "Blank 1",
                        "original_text": "sufficient",
                        "confusion_set_id": "aud_evidence_sufficiency",
                        "options": [
                            {"id": "o1", "kind": "keep", "text": "sufficient"},
                            {"id": "o2", "kind": "replace", "text": "insufficient"},
                        ],
                    }
                ],
                "set_id": "aud_evidence_sufficiency",
            },
            "source_passage": "Sufficient appropriate audit evidence supports the auditor's opinion.",
            "source_id": "pcaob",
            "locator": "AS 1105",
            "citation": "PCAOB AS 1105",
            "gen_method": _GEN_METHOD,
            "tags": ["sec::AUD", "ds::aud::sufficient", "topic::evidence"],
            "bucket": "correct_useful",
        },
    ]


@pytest.fixture()
def cfg() -> RunConfig:
    c = RunConfig(run_id="test-emit-ws", sections=["FAR", "AUD"], offline=True)
    if c.out_dir.exists():
        shutil.rmtree(c.out_dir)
    write_jsonl(c.stage_dir("09-dedup") / "kept.jsonl", _kept_rows())
    return c


def _open_collection(cfg: RunConfig) -> sqlite3.Connection:
    apkg = cfg.out_dir / "cpa_bank.apkg"
    assert apkg.exists(), "emit did not write cpa_bank.apkg"
    assert zipfile.is_zipfile(apkg), "cpa_bank.apkg is not a valid zip"
    with zipfile.ZipFile(apkg) as z:
        assert "collection.anki2" in z.namelist()
        dest = cfg.out_dir / "_extracted"
        z.extract("collection.anki2", dest)
    return sqlite3.connect(dest / "collection.anki2")


def test_emit_writes_valid_apkg_with_app_field_orders(cfg: RunConfig) -> None:
    emit.run(cfg)

    conn = _open_collection(cfg)
    try:
        (models_json,) = conn.execute("SELECT models FROM col").fetchone()
        models = json.loads(models_json)
        by_name = {m["name"]: m for m in models.values()}

        # Both note types present, with EXACT app field names + order.
        assert emit.STUDY_NOTETYPE in by_name
        assert emit.TBS_NOTETYPE in by_name
        study_flds = [f["name"] for f in sorted(by_name[emit.STUDY_NOTETYPE]["flds"], key=lambda f: f["ord"])]
        tbs_flds = [f["name"] for f in sorted(by_name[emit.TBS_NOTETYPE]["flds"], key=lambda f: f["ord"])]
        assert study_flds == STUDY_FIELDS
        assert tbs_flds == TBS_FIELDS

        # Model ids are the stable constants.
        assert int(by_name[emit.STUDY_NOTETYPE]["id"]) == emit.STUDY_MODEL_ID
        assert int(by_name[emit.TBS_NOTETYPE]["id"]) == emit.TBS_MODEL_ID

        study_mid = int(by_name[emit.STUDY_NOTETYPE]["id"])
        tbs_mid = int(by_name[emit.TBS_NOTETYPE]["id"])
        rows = conn.execute("SELECT mid, flds FROM notes").fetchall()
        assert rows, "no notes written"

        study_notes = [flds.split("\x1f") for mid, flds in rows if mid == study_mid]
        tbs_notes = [flds.split("\x1f") for mid, flds in rows if mid == tbs_mid]

        # 1 recall Study note; 4 TBS shapes + 1 MCQ == 5 TBS notes.
        assert len(study_notes) == 1
        assert len(tbs_notes) == 5

        # Study: 5 fields, non-empty provenance (source_passage @2, gen_method @3).
        for f in study_notes:
            assert len(f) == len(STUDY_FIELDS)
            assert f[2].strip(), "study source_passage is empty"
            assert f[3].strip(), "study gen_method is empty"
        # Back carries the citation.
        assert "Source: ASC 606-10-25" in study_notes[0][1]

        # TBS: 8 fields, non-empty provenance (source_passage @5, gen_method @6).
        for f in tbs_notes:
            assert len(f) == len(TBS_FIELDS)
            assert f[5].strip(), "tbs source_passage is empty"
            assert f[6].strip(), "tbs gen_method is empty"
    finally:
        conn.close()


def test_emit_decks_and_checker_status(cfg: RunConfig) -> None:
    emit.run(cfg)

    conn = _open_collection(cfg)
    try:
        (decks_json,) = conn.execute("SELECT decks FROM col").fetchone()
        deck_names = {d["name"] for d in json.loads(decks_json).values()}
    finally:
        conn.close()

    # Study deck uses slug(topic); sealed decks use set_id (payload or topic).
    assert "Ankountant::Study::FAR::revenue_recognition" in deck_names
    assert "Ankountant::Sealed::FAR::capitalize_vs_expense" in deck_names
    assert "Ankountant::Sealed::FAR::leases" in deck_names  # research fell back to topic
    assert "Ankountant::Sealed::AUD::aud_evidence_sufficiency" in deck_names

    # checker_status mapping: correct_useful -> pass, others verbatim.
    manifest = {r["item_id"]: r for r in _read_jsonl(cfg.out_dir / "emitted_manifest.jsonl")}
    assert len(manifest) == 6
    assert manifest["far-recall-0001"]["checker_status"] == "pass"
    assert manifest["far-je-0001"]["checker_status"] == "reworked"


def test_emit_writes_confusable_patch_for_mcq(cfg: RunConfig) -> None:
    emit.run(cfg)

    patch = json.loads((cfg.out_dir / "confusable_patch.json").read_text(encoding="utf-8"))
    assert "capitalize_vs_expense" in patch
    entry = patch["capitalize_vs_expense"]
    assert entry["section"] == "FAR"
    assert entry["set_id"] == "capitalize_vs_expense"
    assert entry["treatments"] == ["Capitalize", "Expense"]
    assert "ds::cost::capitalize" in entry["tags"]


def test_emit_writes_coverage_report(cfg: RunConfig) -> None:
    emit.run(cfg)

    report = (cfg.out_dir / "coverage_report.md").read_text(encoding="utf-8")
    for column in ("Target", "Generated", "Shipped"):
        assert column in report
    # Shipped column reflects the 6 kept candidates.
    assert "Total" in report


def test_emit_writes_clean_leakage_report(cfg: RunConfig) -> None:
    write_jsonl(cfg.stage_dir("08-leak") / "kept.jsonl", _kept_rows())

    emit.run(cfg)

    report = (cfg.out_dir / "leakage_report.md").read_text(encoding="utf-8")
    assert "Sealed references" in report
    assert "| Shipped cards screened | 6 |" in report
    assert "| Dropped as leaks | 0 |" in report
    assert "No leaked shipped cards detected." in report


def test_reports_target_generated_shipped_and_drops(tmp_path) -> None:
    c = RunConfig(run_id="test-reports-ws", sections=["FAR", "AUD"], offline=True)
    if c.out_dir.exists():
        shutil.rmtree(c.out_dir)

    # targets: 3 FAR::revenue_recognition + 1 AUD::evidence
    write_jsonl(
        c.stage_dir("03-worklist") / "worklist.jsonl",
        [
            {"item_id": f"far-{i}", "section": "FAR", "area": "a", "topic": "revenue_recognition",
             "task_id": "t", "skill_level": "applied", "card_type": "recall", "seed": 0}
            for i in range(3)
        ]
        + [
            {"item_id": "aud-0", "section": "AUD", "area": "a", "topic": "evidence",
             "task_id": "t", "skill_level": "applied", "card_type": "tbs_doc_review", "seed": 0}
        ],
    )

    # generated: 2 candidate files for FAR::revenue_recognition (topic via tags)
    for i in range(2):
        write_json(
            c.stage_dir("05-candidates") / f"far-{i}.json",
            {"item_id": f"far-{i}", "section": "FAR", "card_type": "recall",
             "payload": {"front": "q", "back": "a"}, "tags": ["topic::revenue_recognition"]},
        )

    # shipped: 1 FAR::revenue_recognition
    write_jsonl(
        c.stage_dir("09-dedup") / "kept.jsonl",
        [{"item_id": "far-0", "section": "FAR", "card_type": "recall",
          "payload": {"front": "q", "back": "a"}, "tags": ["topic::revenue_recognition"],
          "bucket": "correct_useful"}],
    )

    # drops across the three stages, with reasons
    write_jsonl(c.stage_dir("06-checked") / "dropped.jsonl", [{"item_id": "x1", "reason": "ungrounded"}])
    write_jsonl(c.stage_dir("08-leak") / "kept.jsonl", [{"item_id": "far-0", "bucket": "correct_useful"}])
    write_jsonl(
        c.stage_dir("08-leak") / "dropped.jsonl",
        [{"item_id": "x2", "reason": "leak>0.92", "score": 0.99, "matched_ref": "copied prompt"}],
    )
    write_jsonl(c.stage_dir("09-dedup") / "dropped.jsonl", [{"item_id": "x3", "reason": "dup>0.95"}])

    reports.run(c)
    report = (c.out_dir / "coverage_report.md").read_text(encoding="utf-8")
    leakage_report = (c.out_dir / "leakage_report.md").read_text(encoding="utf-8")

    # Per-topic row: target 3, generated 2, shipped 1.
    assert "| FAR | revenue_recognition | 3 | 2 | 1 |" in report
    # Drop reasons from each stage are aggregated.
    for reason in ("ungrounded", "leak>0.92", "dup>0.95"):
        assert reason in report
    assert "selfcheck" in report and "leakage" in report and "dedup" in report
    assert "**Total dropped** | | 3 |" in report
    assert "| Shipped cards screened | 2 |" in leakage_report
    assert "| Dropped as leaks | 1 |" in leakage_report
    assert "| x2 | leak>0.92 | 0.990 | copied prompt |" in leakage_report


def _read_jsonl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]
