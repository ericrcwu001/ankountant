"""Small shared helpers used across stages (keep dependency-free / stdlib)."""

from __future__ import annotations

import hashlib
import math
import re
import unicodedata
from typing import Sequence


def content_hash(*parts: object) -> str:
    """Stable short hash for idempotency keys / ids."""
    h = hashlib.sha256()
    for p in parts:
        h.update(repr(p).encode("utf-8"))
        h.update(b"\x00")
    return h.hexdigest()[:16]


def slugify(s: str, maxlen: int = 60) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "_", s).strip("_").lower()
    return s[:maxlen] or "x"


_WS = re.compile(r"\s+")


def normalize_text(s: str) -> str:
    return _WS.sub(" ", (s or "").strip())


def cosine(a: Sequence[float], b: Sequence[float]) -> float:
    num = sum(x * y for x, y in zip(a, b))
    da = math.sqrt(sum(x * x for x in a)) or 1.0
    db = math.sqrt(sum(x * x for x in b)) or 1.0
    return num / (da * db)


def is_substring_normalized(needle: str, haystack: str) -> bool:
    """Grounding proof: is `needle` a (whitespace-normalized) substring of `haystack`?"""
    return normalize_text(needle).lower() in normalize_text(haystack).lower()
