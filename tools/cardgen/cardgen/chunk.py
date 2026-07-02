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

    for jsonl in sorted(ingest_dir.glob("*.jsonl")):
        for row in read_jsonl(jsonl):
            source_id = row.get("source_id", jsonl.stem)
            meta = manifest.get(source_id, {})
            section = meta.get("section", "GENERAL") or "GENERAL"
            license = meta.get("license", "")
            locator = row.get("locator", "")
            heading_path = row.get("heading_path", "")

            for idx, piece in enumerate(split_text(row.get("text", ""))):
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
    print(f"[cardgen] chunk: {total} chunk(s) across {len(by_section)} section(s)")
