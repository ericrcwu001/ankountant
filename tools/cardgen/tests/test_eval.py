"""Offline tests for Stage 9 (leakage), Stage 10 (dedup), Stage 11 (baseline).

Everything runs with the deterministic offline backends — no key, no network,
no LanceDB — and never imports the sibling stages (retrieve/generate/selfcheck/
judge), which may not exist yet: they are monkeypatched or fixtured.

    cd tools/cardgen && UV_PROJECT_ENVIRONMENT=.venv CARDGEN_OFFLINE=1 \
        uv run pytest tests/test_eval.py -q
"""

from __future__ import annotations

from cardgen import baseline, dedup, leakage
from cardgen.baseline import (
    answer_relevancy,
    bucket_one_rate,
    card_faithfulness,
    context_precision,
    context_recall,
    decide_pass,
    passage_relevant,
)
from cardgen.config import RunConfig
from cardgen.dedup import near_duplicate_clusters
from cardgen.leakage import is_leak, jaccard, salient_text, word_shingles
from cardgen.models import (
    BUCKET_BAD,
    BUCKET_OK,
    BUCKET_WRONG,
    Candidate,
    Passage,
    read_json,
    read_jsonl,
    write_jsonl,
)
from cardgen.providers.offline import OfflineEmbedder, OfflineJudge


def _cfg(run_id: str) -> RunConfig:
    return RunConfig(run_id=run_id, offline=True)


# ===========================================================================
# Stage 10 — dedup
# ===========================================================================
def test_near_duplicate_clusters_cosine() -> None:
    # Two vectors near-parallel, one orthogonal -> {0,1} and {2}.
    texts = ["alpha one", "beta two", "gamma three"]  # no shared trigrams
    embs = [[1.0, 0.0, 0.0], [0.99, 0.01, 0.0], [0.0, 0.0, 1.0]]

    clusters = near_duplicate_clusters(texts, embs, threshold=0.9)

    assert clusters == [[0, 1], [2]]


def test_near_duplicate_clusters_shingle_only() -> None:
    # No embeddings -> clustering falls back to word-shingle Jaccard.
    a = "the quick brown fox jumps over the lazy dog near the river"
    b = a + " bank"  # near-identical
    c = "wholly unrelated sentence about accounting standards and audits"

    clusters = near_duplicate_clusters([a, b, c], embs=[], threshold=0.95)

    assert clusters == [[0, 1], [2]]


def test_dedup_run_removes_duplicates() -> None:
    cfg = _cfg("test_dedup")
    payload = {"front": "Is freight-in capitalized?", "back": "Yes, add it to the asset cost."}
    rows = [
        {"item_id": "d1", "payload": payload, "bucket": BUCKET_OK, "faithful": 1.0},
        # exact-duplicate salient text, lower faithful -> should be the one dropped
        {"item_id": "d2", "payload": dict(payload), "bucket": BUCKET_OK, "faithful": 0.5},
        {
            "item_id": "d3",
            "payload": {"front": "What is straight-line depreciation?", "back": "Equal expense."},
            "bucket": BUCKET_OK,
            "faithful": 1.0,
        },
    ]
    write_jsonl(cfg.stage_dir("08-leak") / "kept.jsonl", rows)

    dedup.run(cfg)

    kept = list(read_jsonl(cfg.stage_dir("09-dedup") / "kept.jsonl"))
    dropped = list(read_jsonl(cfg.stage_dir("09-dedup") / "dropped.jsonl"))

    assert {r["item_id"] for r in kept} == {"d1", "d3"}
    assert [r["item_id"] for r in dropped] == ["d2"]
    assert dropped[0]["reason"] == "dedup"
    assert dropped[0]["matched_ref"] == "d1"  # higher-faithful representative survives


def test_dedup_representative_prefers_higher_faithful_then_bucket() -> None:
    from cardgen.dedup import _rep_sort_key

    high = {"item_id": "a", "faithful": 0.9, "bucket": BUCKET_BAD}
    low = {"item_id": "b", "faithful": 0.2, "bucket": BUCKET_OK}
    assert _rep_sort_key(high) < _rep_sort_key(low)  # faithful dominates

    same_faith_ok = {"item_id": "c", "faithful": 0.5, "bucket": BUCKET_OK}
    same_faith_bad = {"item_id": "d", "faithful": 0.5, "bucket": BUCKET_WRONG}
    assert _rep_sort_key(same_faith_ok) < _rep_sort_key(same_faith_bad)  # bucket breaks ties


# ===========================================================================
# Stage 9 — leakage
# ===========================================================================
def test_load_sealed_refs_reads_bank() -> None:
    refs = leakage.load_sealed_refs(_cfg("probe"))
    # 52 mcq + 22 tbs + 10 section_item prompts, all unique.
    assert len(refs) == 84
    assert all(isinstance(r, str) and r for r in refs)


def test_is_leak_cosine_exact_match() -> None:
    emb = OfflineEmbedder()
    ref = "Goodwill is tested for impairment at least annually under ASC 350."
    (ref_vec,) = emb.embed([ref])

    # Identical text -> identical vector -> cosine 1.0 >= threshold.
    (card_vec,) = emb.embed([ref])
    leaked, reason, matched, score = is_leak(
        ref, card_vec, [ref], [ref_vec], cosine_threshold=0.92
    )
    assert leaked and reason == "leakage_cosine"
    assert matched == ref
    assert score >= 0.99

    # A distinct card is kept (offline embeddings are near-orthogonal).
    distinct = "Straight-line depreciation allocates cost evenly over useful life."
    (distinct_vec,) = emb.embed([distinct])
    leaked2, _, _, score2 = is_leak(
        distinct, distinct_vec, [ref], [ref_vec], cosine_threshold=0.92
    )
    assert not leaked2
    assert score2 < 0.92


def test_is_leak_shingle_path() -> None:
    emb = OfflineEmbedder()
    ref = "the quick brown fox jumps over the lazy dog near the river"
    card = ref + " bank"  # near-copy: low cosine, high shingle overlap
    (ref_vec,) = emb.embed([ref])
    (card_vec,) = emb.embed([card])

    # Sanity: near-copy has high Jaccard but the hash embedder disagrees.
    assert jaccard(word_shingles(card), word_shingles(ref)) >= 0.8

    leaked, reason, _, score = is_leak(card, card_vec, [ref], [ref_vec], cosine_threshold=0.92)
    assert leaked and reason == "leakage_shingle"
    assert score >= 0.8


def test_leakage_run_drops_leaks_keeps_distinct(monkeypatch) -> None:
    cfg = _cfg("test_leak")
    ref = "A company capitalizes freight-in and installation costs on new equipment."

    graded = [
        # exact copy of a sealed ref -> dropped
        {"item_id": "leak1", "payload": {"prompt": ref}, "bucket": BUCKET_OK},
        # distinct, shipped -> kept
        {
            "item_id": "clean1",
            "payload": {"front": "Define materiality.", "back": "Would influence a user."},
            "bucket": BUCKET_OK,
        },
        # not shipped (wrong) -> filtered out entirely, never screened
        {"item_id": "wrong1", "payload": {"prompt": ref}, "bucket": BUCKET_WRONG},
    ]
    write_jsonl(cfg.stage_dir("07-judge") / "graded.jsonl", graded)

    # Hermetic: fixed single-ref bank + no-op judge step.
    monkeypatch.setattr(leakage, "load_sealed_refs", lambda c, **k: [ref])
    monkeypatch.setattr(leakage, "ensure_graded", lambda c: None)

    leakage.run(cfg)

    kept = list(read_jsonl(cfg.stage_dir("08-leak") / "kept.jsonl"))
    dropped = list(read_jsonl(cfg.stage_dir("08-leak") / "dropped.jsonl"))

    assert {r["item_id"] for r in kept} == {"clean1"}
    assert {r["item_id"] for r in dropped} == {"leak1"}
    assert dropped[0]["reason"] == "leakage_cosine"
    assert dropped[0]["score"] >= 0.99


def test_salient_text_prefers_front_back_then_prompt() -> None:
    assert salient_text({"payload": {"front": "Q", "back": "A"}}) == "Q A"
    assert salient_text({"payload": {"prompt": "  hello   world "}}) == "hello world"
    assert salient_text({"payload": {}, "source_passage": "fallback text"}) == "fallback text"


# ===========================================================================
# Stage 11 — baseline metric primitives (pure)
# ===========================================================================
def test_answer_relevancy_overlap() -> None:
    assert answer_relevancy("cash revenue debit", "record the cash revenue entry") > 0.5
    assert answer_relevancy("alpha", "beta gamma") == 0.0
    assert answer_relevancy("", "anything") == 0.0


def test_passage_relevant_substring_and_overlap() -> None:
    sp = "goodwill impairment"
    assert passage_relevant("annual goodwill impairment testing", sp)
    assert not passage_relevant("unrelated office supplies expense", sp)


def test_context_precision_rewards_relevant_first() -> None:
    sp = "goodwill impairment"
    rel = "goodwill impairment is tested annually"
    irrel = "office supplies are expensed"
    first = context_precision([rel, irrel], sp)
    last = context_precision([irrel, rel], sp)
    assert first == 1.0
    assert first > last > 0.0
    assert context_precision([irrel, irrel], sp) == 0.0


def test_context_recall_fraction() -> None:
    sp = "goodwill impairment annual"
    assert context_recall(["goodwill impairment tested on an annual basis"], sp) == 1.0
    assert abs(context_recall(["goodwill only"], sp) - 1 / 3) < 1e-9
    assert context_recall([], sp) == 0.0


def test_card_faithfulness_rules() -> None:
    passages = ["Goodwill is tested for impairment at least annually."]
    assert card_faithfulness("tested for impairment", passages, BUCKET_OK) == 1.0
    # grounded but judged wrong -> not faithful
    assert card_faithfulness("tested for impairment", passages, BUCKET_WRONG) == 0.0
    # ungrounded -> not faithful
    assert card_faithfulness("fabricated claim", passages, BUCKET_OK) == 0.0


def test_bucket_one_rate() -> None:
    assert abs(bucket_one_rate([BUCKET_OK, BUCKET_OK, BUCKET_WRONG]) - 2 / 3) < 1e-9
    assert bucket_one_rate([]) == 0.0


def test_decide_pass_rule() -> None:
    strong = {
        "bm25": {"faithfulness": 0.4, "bucket1_rate": 0.5},
        "vector": {"faithfulness": 0.6, "bucket1_rate": 0.55},
        "hybrid": {"faithfulness": 0.8, "bucket1_rate": 0.7},
    }
    assert decide_pass(strong) is True

    # hybrid ties on faithfulness but regresses on bucket-1 vs vector -> FAIL
    weak = {
        "bm25": {"faithfulness": 0.4, "bucket1_rate": 0.5},
        "vector": {"faithfulness": 0.6, "bucket1_rate": 0.9},
        "hybrid": {"faithfulness": 0.8, "bucket1_rate": 0.7},
    }
    assert decide_pass(weak) is False


# ===========================================================================
# Stage 11 — baseline end-to-end (fixtured, offline)
# ===========================================================================
_STRONG = "Goodwill is tested for impairment at least annually under ASC 350."
_WEAK = "Office supplies are expensed as incurred and are unrelated to the prompt."


def _fake_retrieve_for(cfg, item, arm, k=None):
    # Hybrid surfaces the reference card's grounding chunk (src, ASC 350); the
    # plain arms return a different chunk, so only hybrid scores a chunk-hit.
    if arm == "hybrid":
        return [Passage(chunk_id="c1", text=_STRONG, source_id="src", locator="ASC 350", score=1.0)]
    return [Passage(chunk_id="c2", text=_WEAK, source_id="src", locator="OTHER", score=1.0)]


def _fake_generate_one(cfg, item, passages):
    text = passages[0].text
    if "Goodwill" in text:  # strong (hybrid) context -> grounded, clean card
        payload = {"front": "When is goodwill tested?", "back": "At least annually under ASC 350."}
        source_passage = "Goodwill is tested for impairment"
    else:  # weak (baseline) context -> ungrounded + defect marker
        payload = {"front": "When is goodwill tested?", "back": "__wrong__ it is never tested."}
        source_passage = "a fabricated claim not present in the passage"
    return Candidate(
        item_id=item["item_id"],
        section=item.get("section", "FAR"),
        card_type="recall",
        payload=payload,
        source_passage=source_passage,
        source_id="src",
        locator="ASC 350",
        citation="ASC 350",
    )


def test_baseline_run_three_arms_and_verdict(monkeypatch) -> None:
    cfg = _cfg("test_baseline")
    worklist = [
        {
            "item_id": f"it{i}",
            "section": "FAR",
            "area": "Intangibles",
            "topic": "Goodwill",
            "task_id": "t1",
            "skill_level": "applying",
            "card_type": "recall",
            "seed": i,
        }
        for i in range(3)
    ]
    write_jsonl(cfg.stage_dir("03-worklist") / "worklist.jsonl", worklist)

    monkeypatch.setattr(baseline, "retrieve_for", _fake_retrieve_for)
    monkeypatch.setattr(baseline, "generate_one", _fake_generate_one)
    monkeypatch.setattr(baseline, "get_judge", lambda c: OfflineJudge())

    metrics = baseline.run(cfg)

    # 3 arms present in the on-disk metrics.
    on_disk = read_json(cfg.stage_dir("10-baseline") / "metrics.json")
    assert on_disk["arms"] == ["bm25", "vector", "hybrid"]
    assert set(on_disk["metrics"]) == {"bm25", "vector", "hybrid"}
    assert on_disk["held_out_n"] == 3

    # Reference generated once (from hybrid=strong); only retrieval varies. Hybrid
    # surfaces the evidence, the baselines (weak passage) don't -> hybrid wins on
    # faithfulness/retrieval_hit while bucket1 ties (card judged once) -> PASS.
    m = metrics["metrics"]
    assert m["hybrid"]["faithfulness"] == 1.0
    assert m["bm25"]["faithfulness"] == 0.0
    assert m["vector"]["faithfulness"] == 0.0
    assert m["hybrid"]["retrieval_hit"] == 1.0
    assert m["bm25"]["retrieval_hit"] == 0.0
    # bucket is judged once per item, so bucket-1 rate ties across arms.
    assert m["hybrid"]["bucket1_rate"] == m["bm25"]["bucket1_rate"] == 1.0
    assert metrics["pass"] is True

    # Report artifact exists and records the verdict.
    report = (cfg.out_dir / "baseline_report.md").read_text(encoding="utf-8")
    assert "Verdict: **PASS**" in report
    assert "`hybrid`" in report


def test_baseline_reuse_uses_graded_chunk_hit(monkeypatch) -> None:
    """When graded cards exist, the baseline reuses them and scores each arm on
    whether its top-k surfaces the card's grounding chunk (source_id+locator)."""
    cfg = _cfg("test_baseline_reuse")
    worklist = [
        {"item_id": f"it{i}", "section": "FAR", "area": "Intangibles", "topic": "Goodwill",
         "task_id": "t1", "skill_level": "applying", "card_type": "recall", "seed": i}
        for i in range(4)
    ]
    write_jsonl(cfg.stage_dir("03-worklist") / "worklist.jsonl", worklist)
    graded = [
        {"item_id": f"it{i}", "section": "FAR", "card_type": "recall",
         "payload": {"front": "When is goodwill tested?", "back": "At least annually."},
         "source_passage": "Goodwill is tested for impairment at least annually.",
         "source_id": "src", "locator": f"loc{i}", "bucket": BUCKET_OK}
        for i in range(4)
    ]
    write_jsonl(cfg.stage_dir("07-judge") / "graded.jsonl", graded)

    def fake_retrieve(cfg, item, arm, k=None):
        # Hybrid surfaces the item's own grounding chunk; plain arms miss it.
        loc = f"loc{item['item_id'][2:]}" if arm == "hybrid" else "MISS"
        return [Passage(chunk_id="c", text="Goodwill is tested for impairment at least annually.",
                        source_id="src", locator=loc, score=1.0)]

    monkeypatch.setattr(baseline, "retrieve_for", fake_retrieve)

    metrics = baseline.run(cfg)
    m = metrics["metrics"]
    assert metrics["held_out_n"] == 4  # reused all 4 graded cards, no regeneration
    assert m["hybrid"]["faithfulness"] == 1.0
    assert m["bm25"]["faithfulness"] == 0.0 and m["vector"]["faithfulness"] == 0.0
    assert m["hybrid"]["retrieval_hit"] == 1.0
    assert metrics["pass"] is True


def test_render_report_ragas_column_well_formed() -> None:
    arms_metrics = {
        a: {
            "n": 1,
            "faithfulness": f,
            "answer_relevancy": 0.5,
            "context_precision": 0.5,
            "context_recall": 0.5,
            "bucket1_rate": f,
        }
        for a, f in (("bm25", 0.2), ("vector", 0.3), ("hybrid", 0.9))
    }
    per_arm = {
        a: [{"item_id": "i0", "faithful": m["faithfulness"], "bucket": BUCKET_OK}]
        for a, m in arms_metrics.items()
    }
    ragas = {"hybrid": {"faithfulness": 0.88, "answer_relevancy": 0.77}}

    report = baseline._render_report(_cfg("test_render"), 1, arms_metrics, per_arm, ragas, True)

    assert "ragas_faithfulness" in report and "ragas_answer_relevancy" in report
    header = next(ln for ln in report.splitlines() if ln.startswith("| arm |"))
    hybrid_row = next(ln for ln in report.splitlines() if ln.startswith("| `hybrid`"))
    # A well-formed markdown row has the same number of pipes as its header.
    assert header.count("|") == hybrid_row.count("|") == 10


def test_baseline_handles_empty_retrieval(monkeypatch) -> None:
    cfg = _cfg("test_baseline_empty")
    write_jsonl(
        cfg.stage_dir("03-worklist") / "worklist.jsonl",
        [{"item_id": "x0", "section": "FAR", "topic": "T", "card_type": "recall"}],
    )
    monkeypatch.setattr(baseline, "retrieve_for", lambda c, i, a, k=None: [])
    monkeypatch.setattr(baseline, "generate_one", lambda c, i, p: None)
    monkeypatch.setattr(baseline, "get_judge", lambda c: OfflineJudge())

    metrics = baseline.run(cfg)
    # Empty retrieval => zeroed metrics, no crash; all arms tie at 0.0 so the
    # >= rule yields a (degenerate) PASS. The point is a deterministic verdict.
    assert metrics["metrics"]["hybrid"]["faithfulness"] == 0.0
    assert metrics["pass"] is True
