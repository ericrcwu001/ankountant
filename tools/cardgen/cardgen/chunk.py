"""Stage 2 — Chunk.

Reads ``00-ingest/<source_id>.jsonl`` and produces section-aware, token-sized
chunks that never cross a ``source_id`` (in fact never cross a single ingest
row / locator, so each chunk keeps one precise structural locator).

Sizing: chunks target ~``TARGET_TOKENS`` tokens (comfortably inside the
~400–800 band) with ~``OVERLAP_TOKENS`` overlap, counted with tiktoken's
``cl100k_base`` encoding. Non-final windows are exactly ``TARGET_TOKENS`` tokens;
the trailing window is the remainder. A row shorter than ``TARGET_TOKENS`` yields
a single chunk.

Provenance (``section``, ``license``, ``heading_path``, ``source_id``,
``locator``) is attached here, once, from the manifest, and rides every
downstream stage. ``section`` is the source's manifest section (may be
``GENERAL`` for multi-section sources).

Output: ``01-chunks/<section>.jsonl`` of ``Chunk`` rows.

tiktoken is imported lazily (and cached) so importing this module stays cheap.
"""

from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from .config import RunConfig
from .models import Chunk, read_json, read_jsonl, write_jsonl
from .util import content_hash

CHUNK_STAGE = "01-chunks"
INGEST_STAGE = "00-ingest"

# Token budget for a chunk. TARGET is the window we fill; MIN/MAX describe the
# acceptable band ("~400–800"). TARGET sits below MAX so tokenizer round-trip
# jitter at window boundaries can never push a chunk over MAX.
MIN_TOKENS = 400
MAX_TOKENS = 800
TARGET_TOKENS = 700
OVERLAP_TOKENS = 80

# ---- chunk quality filter --------------------------------------------------
# A chunk must hold enough *answer-bearing prose* to ground a card. We drop
# fragments that are too short, mostly a heading / table-of-contents, a numeric
# table with little prose, or a bare exam question-stem + answer choices (which
# also carries a leakage risk). Thresholds are deliberately lenient so real
# textbook/standard prose (400–800 tokens) is always kept.
MIN_PROSE_TOKENS = 50
_MIN_ALPHA_RATIO = 0.45
_WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]+")
_SENTENCE_END = re.compile(r"[.!?][\"')\]]?\s*$")
_DOTTED_LEADER = re.compile(r"\.{5,}|\u2026\s*\d+\s*$")
_CHOICE_MARKER = re.compile(r"(?m)^\s*(?:[A-Da-d]|[1-5]|[ivx]+)[\.\)]\s+\S")


def _alpha_ratio(text: str) -> float:
    nonspace = sum(1 for c in text if not c.isspace())
    if not nonspace:
        return 0.0
    return sum(1 for c in text if c.isalpha()) / nonspace


def _is_low_value(text: str) -> tuple[bool, str]:
    """Return ``(drop, reason)`` for a candidate chunk.

    Pure + deterministic (unit-tested) so re-runs are reproducible.
    """
    t = (text or "").strip()
    if not t:
        return True, "empty"

    # 1) Too little text to teach a concept (heading / stub / fragment).
    if count_tokens(t) < MIN_PROSE_TOKENS:
        return True, "too_short"

    # 2) Mostly numbers/symbols (a table, a figure caption dump, an index).
    if _alpha_ratio(t) < _MIN_ALPHA_RATIO:
        return True, "low_prose_ratio"

    lines = [ln.strip() for ln in t.splitlines() if ln.strip()]

    # 3) Table-of-contents / index: many lines with dotted page leaders.
    if len(lines) >= 4:
        leadered = sum(1 for ln in lines if _DOTTED_LEADER.search(ln))
        if leadered >= max(3, len(lines) // 2):
            return True, "toc_or_index"

    # 4) Mostly-heading list: many short lines, few of which end a sentence.
    if len(lines) >= 5:
        sentence_lines = sum(1 for ln in lines if _SENTENCE_END.search(ln))
        avg_words = sum(len(_WORD_RE.findall(ln)) for ln in lines) / len(lines)
        if sentence_lines / len(lines) < 0.15 and avg_words < 6:
            return True, "mostly_headings"

    # 5) Bare exam item: a stem plus stacked answer choices (A. B. C. D.).
    if len(_CHOICE_MARKER.findall(t)) >= 4:
        return True, "question_stem"

    return False, ""

_ENC: Any = None


def _encoder() -> Any:
    global _ENC
    if _ENC is None:
        import tiktoken  # heavy: imported lazily and cached

        _ENC = tiktoken.get_encoding("cl100k_base")
    return _ENC


def count_tokens(text: str) -> int:
    """Number of cl100k_base tokens in ``text`` (the chunker's own metric)."""
    return len(_encoder().encode(text or ""))


def split_text(text: str) -> list[str]:
    """Split one ingest row into ~TARGET_TOKENS-token, overlapping chunks."""
    enc = _encoder()
    toks = enc.encode(text or "")
    n = len(toks)
    if n == 0:
        return []
    if n <= TARGET_TOKENS:
        return [enc.decode(toks)]

    step = TARGET_TOKENS - OVERLAP_TOKENS
    pieces: list[str] = []
    start = 0
    while start < n:
        end = min(start + TARGET_TOKENS, n)
        pieces.append(enc.decode(toks[start:end]))
        if end == n:
            break
        start += step
    return pieces


def _section_map(cfg: RunConfig) -> dict[str, dict]:
    p = cfg.corpus_dir / "manifest.json"
    if not p.exists():
        return {}
    data = read_json(p)
    if not isinstance(data, list):
        return {}
    return {m["source_id"]: m for m in data if isinstance(m, dict) and "source_id" in m}


def run(cfg: RunConfig) -> None:
    manifest = _section_map(cfg)
    ingest_dir = cfg.stage_dir(INGEST_STAGE)
    by_section: dict[str, list[Chunk]] = defaultdict(list)
    dropped = 0
    drop_reasons: dict[str, int] = defaultdict(int)

    for jsonl in sorted(ingest_dir.glob("*.jsonl")):
        for row in read_jsonl(jsonl):
            source_id = row.get("source_id", jsonl.stem)
            meta = manifest.get(source_id, {})
            section = meta.get("section", "GENERAL") or "GENERAL"
            license = meta.get("license", "")
            locator = row.get("locator", "")
            heading_path = row.get("heading_path", "")

            for idx, piece in enumerate(split_text(row.get("text", ""))):
                low, reason = _is_low_value(piece)
                if low:
                    dropped += 1
                    drop_reasons[reason] += 1
                    continue
                by_section[section].append(
                    Chunk(
                        chunk_id=content_hash(source_id, locator, idx),
                        source_id=source_id,
                        locator=locator,
                        license=license,
                        heading_path=heading_path,
                        section=section,
                        text=piece,
                    )
                )

    out_dir = cfg.stage_dir(CHUNK_STAGE)
    total = 0
    for section, chunks in sorted(by_section.items()):
        write_jsonl(out_dir / f"{section}.jsonl", chunks)
        total += len(chunks)
        print(f"[cardgen] chunk: {section} -> {len(chunks)} chunk(s)")
    if dropped:
        print(f"[cardgen] chunk: dropped {dropped} low-value chunk(s) {dict(drop_reasons)}")
    print(f"[cardgen] chunk: {total} chunk(s) across {len(by_section)} section(s)")
