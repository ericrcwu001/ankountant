"""Offline tests for Stage 5 (retrieve) + Stage 6 (generate).

Everything runs with the deterministic offline backends — no key, no network,
no LanceDB. Full retrieval against a live index is validated at integration by
the orchestrator; here we unit-test the RRF fusion helper and the grounded
generation path.

    cd tools/cardgen && UV_PROJECT_ENVIRONMENT=.venv CARDGEN_OFFLINE=1 \
        uv run pytest tests/test_retrieve_generate.py -q
"""

from __future__ import annotations

import pytest
from cardgen.config import RunConfig
from cardgen.generate import generate_one
from cardgen.models import (
    CARD_TYPES,
    MCQ,
    RECALL,
    TBS_DOC_REVIEW,
    TBS_JE,
    TBS_NUMERIC,
    TBS_RESEARCH,
    Passage,
)
from cardgen.providers.offline import OfflineGenerator
from cardgen.retrieve import rrf_fuse
from cardgen.util import is_substring_normalized

PASSAGE_TEXT = (
    "Revenue is recognized when a performance obligation is satisfied by "
    "transferring a promised good or service to a customer. The transaction "
    "price is allocated to each obligation based on relative standalone prices."
)

# Top-level payload keys required per card shape (contract doc 07, Emit section).
EXPECTED_PAYLOAD_KEYS = {
    RECALL: {"front", "back"},
    MCQ: {"prompt", "answer_key", "treatments"},
    TBS_RESEARCH: {"prompt", "exhibits", "steps"},
    TBS_NUMERIC: {"prompt", "exhibits", "steps"},
    TBS_JE: {"prompt", "exhibits", "steps"},
    TBS_DOC_REVIEW: {"prompt", "exhibits", "steps"},
}


def _cfg() -> RunConfig:
    return RunConfig(run_id="test", offline=True)


def _item(card_type: str) -> dict:
    return {
        "item_id": f"it_{card_type}",
        "section": "FAR",
        "area": "Revenue",
        "topic": "Revenue Recognition",
        "task_id": "t1",
        "skill_level": "remembering_understanding",
        "card_type": card_type,
        "seed": 7,
    }


def _passages() -> list[Passage]:
    return [
        Passage(
            chunk_id="c1",
            text=PASSAGE_TEXT,
            source_id="openstax_far",
            locator="ASC 606-10-25",
            score=0.9,
        )
    ]


# ---- Stage 6: generation ---------------------------------------------------
@pytest.mark.parametrize("card_type", CARD_TYPES)
def test_generate_one_offline_grounded(card_type: str) -> None:
    cand = generate_one(_cfg(), _item(card_type), _passages(), gen=OfflineGenerator())

    assert cand is not None, f"{card_type}: expected a Candidate"

    # Grounding: source_passage is a normalized substring of the retrieved chunk.
    assert is_substring_normalized(cand.source_passage, PASSAGE_TEXT)

    # Provenance carried from the matched passage.
    assert cand.source_id == "openstax_far"
    assert cand.locator == "ASC 606-10-25"

    # Tags include section + topic axes.
    assert any(t.startswith("sec::") for t in cand.tags)
    assert any(t.startswith("topic::") for t in cand.tags)
    assert any(t.startswith("cog::") for t in cand.tags)

    # gen_method fully populated + records the hybrid retrieval config.
    assert cand.gen_method.get("model")
    assert cand.gen_method.get("prompt_version") == "v1"
    assert cand.gen_method.get("retrieval_config", {}).get("arm") == "hybrid"
    assert cand.gen_method.get("retrieval_config", {}).get("top_k") == _cfg().top_k
    assert cand.gen_method.get("seed") == 7
    assert "index_version" in cand.gen_method

    # Per-shape payload keys present.
    assert EXPECTED_PAYLOAD_KEYS[card_type].issubset(cand.payload.keys()), (
        f"{card_type}: payload missing keys, got {sorted(cand.payload)}"
    )


def test_generate_one_mcq_and_docreview_get_ds_tag() -> None:
    for card_type in (MCQ, TBS_DOC_REVIEW):
        cand = generate_one(_cfg(), _item(card_type), _passages(), gen=OfflineGenerator())
        assert cand is not None
        assert any(t.startswith("ds::") for t in cand.tags), f"{card_type}: expected a ds:: tag"


def test_generate_one_recall_is_rote_for_low_skill() -> None:
    cand = generate_one(_cfg(), _item(RECALL), _passages(), gen=OfflineGenerator())
    assert cand is not None
    assert "cog::rote" in cand.tags


def test_generate_one_no_passages_returns_none() -> None:
    assert generate_one(_cfg(), _item(RECALL), [], gen=OfflineGenerator()) is None


def test_generate_one_repairs_ungrounded_source_passage() -> None:
    """A generator that hallucinates source_passage is repaired to a real one."""

    class Hallucinating:
        def generate(self, req) -> str:  # type: ignore[no-untyped-def]
            import json

            return json.dumps(
                {
                    "source_passage": "this text is nowhere in the passage",
                    "citation": "ASC 606",
                    "payload": {"front": "Q?", "back": "A."},
                }
            )

    cand = generate_one(_cfg(), _item(RECALL), _passages(), gen=Hallucinating())
    assert cand is not None
    # Repaired to a genuine substring of the retrieved passage.
    assert is_substring_normalized(cand.source_passage, PASSAGE_TEXT)
    assert cand.source_passage != "this text is nowhere in the passage"


# ---- Stage 5: RRF fusion helper (no LanceDB) -------------------------------
def test_rrf_fuse_ordering() -> None:
    # "B" ranks high in both lists -> should win overall.
    list_a = ["A", "B", "C"]
    list_b = ["B", "C", "D"]

    fused = rrf_fuse([list_a, list_b], k=60)
    order = [key for key, _ in fused]

    assert order == ["B", "C", "A", "D"]
    assert set(order) == {"A", "B", "C", "D"}

    scores = dict(fused)
    assert scores["B"] > scores["C"] > scores["A"] > scores["D"]


def test_rrf_fuse_single_list_preserves_rank() -> None:
    fused = rrf_fuse([["x", "y", "z"]], k=60)
    assert [key for key, _ in fused] == ["x", "y", "z"]


def test_rrf_fuse_rewards_agreement_over_single_top_rank() -> None:
    # An item ranked 2nd in BOTH lists beats an item ranked 1st in only one.
    fused = dict(rrf_fuse([["top1", "agree"], ["top2", "agree"]], k=60))
    assert fused["agree"] > fused["top1"]
    assert fused["agree"] > fused["top2"]
