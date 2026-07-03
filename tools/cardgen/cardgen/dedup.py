"""Stage 10 — Within-corpus near-duplicate dedup.

Keeps the shipped set *distinct*: cluster surviving cards by embedding cosine
(≥ ``cfg.dedup_threshold``) **and/or** high MinHash/Jaccard shingle overlap on
their normalized text, then keep one representative per cluster — preferring the
higher judge ``faithful`` score, then the better bucket. Prevents a dozen
near-identical "capitalize the freight-in" cards from shipping.

Reads : ``08-leak/kept.jsonl``
Writes: ``09-dedup/kept.jsonl`` + ``09-dedup/dropped.jsonl``

:func:`near_duplicate_clusters` is a pure, import-safe helper unit-tested
directly in ``tests/test_eval.py``.
"""

from __future__ import annotations

from typing import Sequence

from .config import RunConfig
from .leakage import SHINGLE_K, SHINGLE_THRESHOLD, jaccard, salient_text, word_shingles
from .models import BUCKET_BAD, BUCKET_OK, BUCKET_WRONG, read_jsonl, write_jsonl
from .providers.base import get_embedder
from .util import cosine

# Best (lowest) rank ships as the cluster representative.
_BUCKET_RANK = {BUCKET_OK: 0, BUCKET_BAD: 1, BUCKET_WRONG: 2}


# ---------------------------------------------------------------------------
# Pure clustering helper
# ---------------------------------------------------------------------------
def near_duplicate_clusters(
    texts: Sequence[str],
    embs: Sequence[Sequence[float]],
    threshold: float,
    *,
    shingle_threshold: float = SHINGLE_THRESHOLD,
    shingle_k: int = SHINGLE_K,
    block_keys: Sequence[str] | None = None,
) -> list[list[int]]:
    """Cluster indices whose cards are near-duplicates.

    Two cards join the same cluster when their embedding cosine ≥ ``threshold``
    **or** their word-shingle Jaccard ≥ ``shingle_threshold``. Uses union-find so
    duplication is transitive (A~B, B~C => one cluster). Returns a list of
    clusters (each a sorted list of indices), ordered by their smallest index —
    fully deterministic.

    ``block_keys`` (optional, one per card) makes dedup *template-aware*: two
    cards are never merged when their block keys differ, so legitimately distinct
    parametric variants of one template (e.g. Single vs MFJ, or two tax years)
    are kept even when their wording overlaps ≥ the shingle bar. Cards with an
    empty block key (RAG cards) cluster normally.
    """
    n = len(texts)
    parent = list(range(n))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    shingles = [word_shingles(t, shingle_k) for t in texts]
    have_embs = len(embs) == n and n > 0

    for i in range(n):
        for j in range(i + 1, n):
            if block_keys is not None and block_keys[i] != block_keys[j]:
                continue  # never merge across distinct template variants
            near = False
            if have_embs and cosine(embs[i], embs[j]) >= threshold:
                near = True
            elif jaccard(shingles[i], shingles[j]) >= shingle_threshold:
                near = True
            if near:
                union(i, j)

    groups: dict[int, list[int]] = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    return [sorted(members) for _, members in sorted(groups.items())]


# ---------------------------------------------------------------------------
# Representative selection
# ---------------------------------------------------------------------------
def _rep_sort_key(row: dict) -> tuple:
    """Lower is better: highest faithful first, then best bucket, then stable id."""
    faithful = row.get("faithful", 0.0)
    try:
        faithful = float(faithful)
    except (TypeError, ValueError):
        faithful = 0.0
    bucket_rank = _BUCKET_RANK.get(row.get("bucket"), 3)
    return (-faithful, bucket_rank, str(row.get("item_id", "")))


def _dedup_block_key(row: dict) -> str:
    """Distinct-variant identity for template cards (never merged across); empty
    for RAG cards so they cluster by similarity as before."""
    gm = row.get("gen_method") or {}
    if gm.get("method") == "template":
        return f"{gm.get('template_id', '')}::{gm.get('variant_key', '')}"
    return ""


# ---------------------------------------------------------------------------
# Stage entry point
# ---------------------------------------------------------------------------
def run(cfg: RunConfig) -> None:
    rows = list(read_jsonl(cfg.stage_dir("08-leak") / "kept.jsonl"))
    out_dir = cfg.stage_dir("09-dedup")

    kept: list[dict] = []
    dropped: list[dict] = []

    if rows:
        texts = [salient_text(r) for r in rows]
        embs = get_embedder(cfg).embed(texts)
        block_keys = [_dedup_block_key(r) for r in rows]
        clusters = near_duplicate_clusters(texts, embs, cfg.dedup_threshold, block_keys=block_keys)

        for members in clusters:
            ranked = sorted(members, key=lambda idx: _rep_sort_key(rows[idx]))
            rep_idx = ranked[0]
            kept.append(rows[rep_idx])
            for idx in ranked[1:]:
                score = round(cosine(embs[rep_idx], embs[idx]), 6) if embs else 0.0
                dropped.append(
                    {
                        "item_id": rows[idx].get("item_id"),
                        "reason": "dedup",
                        "matched_ref": rows[rep_idx].get("item_id"),
                        "score": score,
                    }
                )

    write_jsonl(out_dir / "kept.jsonl", kept)
    write_jsonl(out_dir / "dropped.jsonl", dropped)
    print(
        f"[dedup] {len(rows)} in -> {len(kept)} representatives, {len(dropped)} near-duplicates dropped"
    )
