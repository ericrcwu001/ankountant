"""Stage 5 — hybrid retrieval.

For each work item we build a topic query and pull top-k passages from the
LanceDB index built in stage 3. Three arms are supported:

- ``vector``: dense search over the offline/live embedding of the query.
- ``bm25``:   full-text (BM25) search.
- ``hybrid``: run both arms and fuse them with Reciprocal-Rank Fusion (k=60);
              this is the arm used by :func:`run` (baseline A/B/C exercises the
              other two).

Passages are section-scoped (``section == item.section`` OR ``"GENERAL"``),
scored, and anything below ``cfg.relevance_floor`` is dropped. If nothing
survives the item is written out as an honest coverage gap (``skipped=True``)
rather than generating ungrounded.

Heavy backends (``lancedb`` and the sibling ``cardgen.index`` module) are
imported lazily inside functions so the module imports cleanly offline and the
RRF helper stays unit-testable without an index.
"""

from __future__ import annotations

from dataclasses import asdict
from typing import Any

from .config import RunConfig
from .models import Passage, read_jsonl, write_json

RRF_K = 60
GENERAL_SECTION = "GENERAL"


# ---- Reciprocal-Rank Fusion (pure, unit-testable, no LanceDB) --------------
def rrf_fuse(ranked_lists: list[list[str]], k: int = RRF_K) -> list[tuple[str, float]]:
    """Fuse several ranked-id lists into one ordering via Reciprocal-Rank Fusion.

    Each input list holds ids ordered best-first. An id's fused score is the sum
    over lists of ``1 / (k + rank)`` (rank is 1-based). Returns ``(id, score)``
    pairs sorted by descending score, with a stable id tie-break so the ordering
    is deterministic.
    """
    scores: dict[str, float] = {}
    for ranked in ranked_lists:
        for rank, key in enumerate(ranked):
            if key is None:
                continue
            scores[key] = scores.get(key, 0.0) + 1.0 / (k + rank + 1)
    return sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))


# ---- query construction ----------------------------------------------------
def _build_query(item: dict) -> str:
    """A topic query from the work item (section / area / topic / task)."""
    parts = [
        item.get("topic", ""),
        item.get("area", ""),
        item.get("section", ""),
        item.get("task_id", ""),
    ]
    return " ".join(p for p in (str(x).strip() for x in parts) if p)


# ---- row -> Passage --------------------------------------------------------
def _row_to_passage(row: dict, score: float) -> Passage:
    return Passage(
        chunk_id=str(row.get("chunk_id", "")),
        text=str(row.get("text", "")),
        source_id=str(row.get("source_id", "")),
        locator=str(row.get("locator", "")),
        score=float(score),
    )


def _vector_score(row: dict) -> float:
    """Turn a LanceDB distance into an ascending similarity-ish score."""
    if "_distance" in row and row["_distance"] is not None:
        return 1.0 / (1.0 + float(row["_distance"]))
    for key in ("_score", "score", "_relevance_score"):
        if row.get(key) is not None:
            return float(row[key])
    return 0.0


def _fts_score(row: dict) -> float:
    for key in ("_score", "score", "_relevance_score"):
        if row.get(key) is not None:
            return float(row[key])
    return 0.0


# ---- LanceDB search arms (lazy) --------------------------------------------
def _vector_search(cfg: RunConfig, table: Any, query: str, limit: int) -> list[dict]:
    from .providers.base import get_embedder

    qvec = get_embedder(cfg).embed([query])[0]
    return list(table.search(qvec).limit(limit).to_list())


def _bm25_search(cfg: RunConfig, table: Any, query: str, limit: int) -> list[dict]:
    return list(table.search(query, query_type="fts").limit(limit).to_list())


def _hybrid_scored(vrows: list[dict], brows: list[dict], k: int = RRF_K) -> list[tuple[dict, float]]:
    """Fuse two arms by RRF over ``chunk_id`` and return ``(row, fused_score)``."""
    ranked_lists = [
        [str(r.get("chunk_id")) for r in vrows if r.get("chunk_id") is not None],
        [str(r.get("chunk_id")) for r in brows if r.get("chunk_id") is not None],
    ]
    rowmap: dict[str, dict] = {}
    for r in [*vrows, *brows]:
        cid = r.get("chunk_id")
        if cid is not None:
            rowmap.setdefault(str(cid), r)
    return [(rowmap[cid], score) for cid, score in rrf_fuse(ranked_lists, k=k) if cid in rowmap]


# ---- public: retrieve_for --------------------------------------------------
def retrieve_for(cfg: RunConfig, item: dict, arm: str = "hybrid", k: int | None = None) -> list[Passage]:
    """Retrieve section-scoped, floor-filtered top-``k`` passages (k defaults to
    ``cfg.top_k``; the baseline uses a larger ``k`` to build an arm-neutral
    reference)."""
    from .index import open_table  # lazy: sibling module (WS-A) + lancedb

    table = open_table(cfg)
    query = _build_query(item)
    section = str(item.get("section", ""))
    top_k = k if k is not None else cfg.top_k
    # Over-fetch so fusion + section filtering still leave a full top_k.
    fetch = max(top_k * 4, 20)

    if arm == "vector":
        scored = [(r, _vector_score(r)) for r in _vector_search(cfg, table, query, fetch)]
    elif arm == "bm25":
        scored = [(r, _fts_score(r)) for r in _bm25_search(cfg, table, query, fetch)]
    else:  # hybrid
        vrows = _vector_search(cfg, table, query, fetch)
        brows = _bm25_search(cfg, table, query, fetch)
        scored = _hybrid_scored(vrows, brows, k=RRF_K)

    passages: list[Passage] = []
    for row, score in scored:
        if str(row.get("section", "")) not in (section, GENERAL_SECTION):
            continue
        if float(score) < cfg.relevance_floor:
            continue
        passages.append(_row_to_passage(row, score))

    passages.sort(key=lambda p: p.score, reverse=True)
    return passages[:top_k]


# ---- public: run -----------------------------------------------------------
def run(cfg: RunConfig) -> None:
    worklist = cfg.stage_dir("03-worklist") / "worklist.jsonl"
    out_dir = cfg.stage_dir("04-retrieved")

    n_items = n_skipped = 0
    for item in read_jsonl(worklist):
        item_id = str(item.get("item_id"))
        if not item_id:
            continue
        n_items += 1
        passages = retrieve_for(cfg, item, arm="hybrid")
        rec: dict[str, Any] = {
            "item_id": item_id,
            "arm": "hybrid",
            "passages": [asdict(p) for p in passages],
        }
        if not passages:
            rec["skipped"] = True
            n_skipped += 1
        write_json(out_dir / f"{item_id}.json", rec)

    print(f"[cardgen] retrieve: {n_items} items, {n_skipped} skipped (no grounded passages)")
