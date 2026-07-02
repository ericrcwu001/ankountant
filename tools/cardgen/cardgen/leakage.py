"""Stage 9 — Leakage check (guards the app's sealed-bank firewall).

Every judged ``correct_useful`` card is compared against the **sealed
performance bank + held-out test set** (the mcq / section-item / tbs *prompts*
in ``rslib/src/ankountant/seed_content.json``). A study card that is a near-copy
of a sealed evaluation item would corrupt the readiness signal (SPOV-5), so it
is dropped: either its salient text is too close in embedding space
(cosine ≥ ``cfg.leakage_threshold``) or it shares too many text shingles with a
sealed prompt (MinHash / Jaccard overlap ≥ :data:`SHINGLE_THRESHOLD`).

Reads : ``07-judge/graded.jsonl`` (via :func:`cardgen.judge.ensure_graded`)
Writes: ``08-leak/kept.jsonl`` + ``08-leak/dropped.jsonl``

The pure helpers (:func:`salient_text`, :func:`word_shingles`, :func:`jaccard`,
:class:`MinHash`, :func:`is_leak`) are import-safe with no sibling modules and
are unit-tested directly in ``tests/test_eval.py``.
"""

from __future__ import annotations

import hashlib
import random
import re
from pathlib import Path
from typing import Any, Iterable, Sequence

from .config import ROOT, RunConfig
from .models import BUCKET_OK, read_json, read_jsonl, write_jsonl
from .providers.base import get_embedder
from .util import cosine, normalize_text

# High shingle overlap => a near-copy even if the embedder disagrees.
SHINGLE_THRESHOLD = 0.80
# Word-shingle size for MinHash / Jaccard.
SHINGLE_K = 3

# Repo root: tools/cardgen/ -> tools/ -> <repo>/
_SEED_CONTENT = ROOT.parent.parent / "rslib" / "src" / "ankountant" / "seed_content.json"

_WORD = re.compile(r"[a-z0-9]+")


# ---------------------------------------------------------------------------
# Sealed reference bank
# ---------------------------------------------------------------------------
def load_sealed_refs(cfg: RunConfig, *, path: str | Path | None = None) -> list[str]:
    """Return the sealed-bank / held-out reference *texts*.

    These are the **prompts** of the sealed performance items in
    ``seed_content.json``: every ``mcqs[*][*].prompt``, every ``tbs[*].prompt``,
    and every ``section_items[*].prompt``. Recall cards are ordinary study
    material (not sealed) and are intentionally excluded.
    """
    seed_path = Path(path) if path is not None else _SEED_CONTENT
    if not seed_path.exists():
        print(f"[leakage] WARNING: sealed bank not found at {seed_path}; no refs loaded")
        return []

    data = read_json(seed_path)
    refs: list[str] = []

    mcqs = data.get("mcqs", {})
    if isinstance(mcqs, dict):
        for group in mcqs.values():
            for item in group or []:
                _add_prompt(refs, item)
    for item in data.get("tbs", []) or []:
        _add_prompt(refs, item)
    for item in data.get("section_items", []) or []:
        _add_prompt(refs, item)

    # De-dup identical refs while preserving order (stable, deterministic).
    seen: set[str] = set()
    out: list[str] = []
    for r in refs:
        if r and r not in seen:
            seen.add(r)
            out.append(r)
    return out


def _add_prompt(refs: list[str], item: Any) -> None:
    if isinstance(item, dict):
        prompt = item.get("prompt")
        if isinstance(prompt, str) and prompt.strip():
            refs.append(normalize_text(prompt))


# ---------------------------------------------------------------------------
# Salient text extraction (front+back or prompt)
# ---------------------------------------------------------------------------
def salient_text(row: dict) -> str:
    """The comparable text of a card: front+back (recall) or prompt (mcq/tbs).

    Falls back to the grounded ``source_passage`` when a payload carries neither
    (so a card is never compared as an empty string).
    """
    payload = row.get("payload") or {}
    parts: list[str] = []
    for key in ("front", "back", "prompt"):
        val = payload.get(key)
        if isinstance(val, str) and val.strip():
            parts.append(val)
    if not parts:
        sp = row.get("source_passage")
        if isinstance(sp, str) and sp.strip():
            parts.append(sp)
    return normalize_text(" ".join(parts))


# ---------------------------------------------------------------------------
# Shingle / Jaccard / MinHash helpers (pure, deterministic)
# ---------------------------------------------------------------------------
def word_shingles(text: str, k: int = SHINGLE_K) -> set[str]:
    """Set of overlapping ``k``-word shingles of the normalized text."""
    words = _WORD.findall(normalize_text(text).lower())
    if len(words) < k:
        return {" ".join(words)} if words else set()
    return {" ".join(words[i : i + k]) for i in range(len(words) - k + 1)}


def jaccard(a: set[str], b: set[str]) -> float:
    """Exact Jaccard similarity of two shingle sets (what MinHash estimates)."""
    if not a and not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0


_MERSENNE = (1 << 61) - 1


def _shingle_hash(s: str) -> int:
    return int.from_bytes(hashlib.blake2b(s.encode("utf-8"), digest_size=8).digest(), "big")


class MinHash:
    """Deterministic MinHash for scalable Jaccard estimation (50k corpus path).

    Seeded, so signatures are reproducible; :func:`estimated_jaccard` approaches
    the exact :func:`jaccard` as ``num_perm`` grows.
    """

    def __init__(self, num_perm: int = 64, seed: int = 1) -> None:
        self.num_perm = num_perm
        rng = random.Random(seed)
        self._a = [rng.randrange(1, _MERSENNE) for _ in range(num_perm)]
        self._b = [rng.randrange(0, _MERSENNE) for _ in range(num_perm)]

    def signature(self, shingles: Iterable[str]) -> tuple[int, ...]:
        sig = [_MERSENNE] * self.num_perm
        for sh in shingles:
            h = _shingle_hash(sh) % _MERSENNE
            for i in range(self.num_perm):
                v = (self._a[i] * h + self._b[i]) % _MERSENNE
                if v < sig[i]:
                    sig[i] = v
        return tuple(sig)

    @staticmethod
    def estimated_jaccard(sig_a: Sequence[int], sig_b: Sequence[int]) -> float:
        if not sig_a or not sig_b or len(sig_a) != len(sig_b):
            return 0.0
        return sum(1 for x, y in zip(sig_a, sig_b) if x == y) / len(sig_a)


# ---------------------------------------------------------------------------
# Core leakage decision (pure)
# ---------------------------------------------------------------------------
def is_leak(
    card_text: str,
    card_emb: Sequence[float],
    ref_texts: Sequence[str],
    ref_embs: Sequence[Sequence[float]],
    *,
    cosine_threshold: float,
    shingle_threshold: float = SHINGLE_THRESHOLD,
    shingle_k: int = SHINGLE_K,
) -> tuple[bool, str, str, float]:
    """Decide whether ``card_text`` leaks a sealed ref.

    Returns ``(leaked, reason, matched_ref, score)``. Cosine is checked first
    (semantic near-copy); shingle Jaccard is the OR fallback for lexical copies
    the embedder might miss. ``score`` is the triggering similarity; when nothing
    triggers it is the best cosine seen (for auditing the closest miss).
    """
    best_cos = -1.0
    best_cos_ref = ""
    for ref, ref_emb in zip(ref_texts, ref_embs):
        c = cosine(card_emb, ref_emb)
        if c > best_cos:
            best_cos = c
            best_cos_ref = ref
    if best_cos >= cosine_threshold:
        return True, "leakage_cosine", best_cos_ref, round(best_cos, 6)

    card_sh = word_shingles(card_text, shingle_k)
    if card_sh:
        best_jac = 0.0
        best_jac_ref = ""
        for ref in ref_texts:
            j = jaccard(card_sh, word_shingles(ref, shingle_k))
            if j > best_jac:
                best_jac = j
                best_jac_ref = ref
        if best_jac >= shingle_threshold:
            return True, "leakage_shingle", best_jac_ref, round(best_jac, 6)

    return False, "", best_cos_ref, round(max(best_cos, 0.0), 6)


# ---------------------------------------------------------------------------
# Stage entry point
# ---------------------------------------------------------------------------
def ensure_graded(cfg: RunConfig) -> Any:
    """Lazy, monkeypatchable shim to :func:`cardgen.judge.ensure_graded`.

    Kept as a module-level name so unit tests can replace it without importing
    the (integration-time) ``cardgen.judge`` module.
    """
    from . import judge as _judge

    return _judge.ensure_graded(cfg)


def _graded_rows(cfg: RunConfig) -> list[dict]:
    graded_path = cfg.stage_dir("07-judge") / "graded.jsonl"
    result = ensure_graded(cfg)
    if isinstance(result, list):
        return [r for r in result if isinstance(r, dict)]
    if isinstance(result, (str, Path)):
        p = Path(result)
        if p.exists():
            return list(read_jsonl(p))
    return list(read_jsonl(graded_path))


def _truncate(text: str, n: int = 240) -> str:
    text = normalize_text(text)
    return text if len(text) <= n else text[: n - 1] + "\u2026"


def run(cfg: RunConfig) -> None:
    refs = load_sealed_refs(cfg)
    ref_embs = get_embedder(cfg).embed(refs) if refs else []

    graded = _graded_rows(cfg)
    shipped = [r for r in graded if r.get("bucket") == BUCKET_OK]

    out_dir = cfg.stage_dir("08-leak")
    kept: list[dict] = []
    dropped: list[dict] = []

    if not shipped:
        write_jsonl(out_dir / "kept.jsonl", kept)
        write_jsonl(out_dir / "dropped.jsonl", dropped)
        print(f"[leakage] {len(graded)} graded, 0 shipped -> nothing to screen")
        return

    texts = [salient_text(r) for r in shipped]
    embedder = get_embedder(cfg)
    card_embs = embedder.embed(texts)

    for row, text, emb in zip(shipped, texts, card_embs):
        leaked, reason, matched_ref, score = is_leak(
            text, emb, refs, ref_embs, cosine_threshold=cfg.leakage_threshold
        )
        if leaked:
            dropped.append(
                {
                    "item_id": row.get("item_id"),
                    "reason": reason,
                    "matched_ref": _truncate(matched_ref),
                    "score": score,
                }
            )
        else:
            kept.append(row)

    write_jsonl(out_dir / "kept.jsonl", kept)
    write_jsonl(out_dir / "dropped.jsonl", dropped)
    print(
        f"[leakage] screened {len(shipped)} shipped cards vs {len(refs)} sealed refs: "
        f"kept {len(kept)}, dropped {len(dropped)}"
    )
