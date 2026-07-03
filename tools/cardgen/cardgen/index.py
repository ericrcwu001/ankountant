"""Stage 3 — Embed & index.

Reads every ``01-chunks/<section>.jsonl``, embeds the chunk texts with
``get_embedder(cfg)`` (the deterministic offline embedder when keyless), and
writes a single LanceDB table ``chunks`` at ``cfg.index_uri`` with a fixed-size
``vector`` column plus all provenance columns. A native BM25 full-text index is
built on ``text`` so retrieval (stage 5) can run hybrid dense + sparse queries.

An ``index_version.txt`` tag (a content hash of the chunk ids + embed model +
dim) is written to ``cfg.index_dir`` so generated cards can record exactly which
index they were grounded against.

The run is idempotent: the table is recreated (overwrite) each time.

``lancedb``/``pyarrow`` are imported lazily inside the functions that use them.
"""

from __future__ import annotations

from typing import Any, Iterator

from .config import RunConfig
from .models import read_jsonl
from .providers.base import get_embedder
from .util import content_hash

TABLE_NAME = "chunks"
CHUNK_STAGE = "01-chunks"
INDEX_VERSION_FILE = "index_version.txt"
_EMBED_BATCH = 128

# Column order for the LanceDB table (contract §Stage 3, plus heading_path).
_COLUMNS = (
    "chunk_id",
    "section",
    "text",
    "vector",
    "source_id",
    "locator",
    "license",
    "heading_path",
)


def _iter_chunks(cfg: RunConfig) -> Iterator[dict]:
    chunk_dir = cfg.stage_dir(CHUNK_STAGE)
    for jsonl in sorted(chunk_dir.glob("*.jsonl")):
        yield from read_jsonl(jsonl)


def _embed_batched(embedder: Any, texts: list[str]) -> list[list[float]]:
    vectors: list[list[float]] = []
    for i in range(0, len(texts), _EMBED_BATCH):
        vectors.extend(embedder.embed(texts[i : i + _EMBED_BATCH]))
    return vectors


def _embed_concurrent(cfg: RunConfig, embedder: Any, texts: list[str]) -> list[list[float]]:
    """Embed batches concurrently (live throughput), reassembled in order.

    Determinism is preserved: results are placed back at their batch index, so
    the vector list is identical to the sequential path.
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed

    batches = [texts[i : i + _EMBED_BATCH] for i in range(0, len(texts), _EMBED_BATCH)]
    results: list[list[list[float]]] = [[] for _ in batches]
    with ThreadPoolExecutor(max_workers=max(1, cfg.embed_concurrency)) as ex:
        futs = {ex.submit(embedder.embed, b): i for i, b in enumerate(batches)}
        for fut in as_completed(futs):
            results[futs[fut]] = fut.result()
    out: list[list[float]] = []
    for r in results:
        out.extend(r)
    return out


def _arrow_table(records: list[dict], dim: int):
    import pyarrow as pa

    schema = pa.schema(
        [
            pa.field("chunk_id", pa.string()),
            pa.field("section", pa.string()),
            pa.field("text", pa.string()),
            pa.field("vector", pa.list_(pa.float32(), dim)),
            pa.field("source_id", pa.string()),
            pa.field("locator", pa.string()),
            pa.field("license", pa.string()),
            pa.field("heading_path", pa.string()),
        ]
    )
    return pa.Table.from_pylist(records, schema=schema)


def run(cfg: RunConfig) -> None:
    import lancedb

    chunks = list(_iter_chunks(cfg))
    if not chunks:
        print("[cardgen] index: no chunks found; nothing to index")
        return

    embedder = get_embedder(cfg)
    dim = embedder.dim
    texts = [c.get("text", "") for c in chunks]
    if cfg.offline or cfg.embed_concurrency <= 1:
        vectors = _embed_batched(embedder, texts)
    else:
        vectors = _embed_concurrent(cfg, embedder, texts)

    records = [
        {
            "chunk_id": c.get("chunk_id", ""),
            "section": c.get("section", ""),
            "text": c.get("text", ""),
            "vector": [float(x) for x in vec],
            "source_id": c.get("source_id", ""),
            "locator": c.get("locator", ""),
            "license": c.get("license", ""),
            "heading_path": c.get("heading_path", ""),
        }
        for c, vec in zip(chunks, vectors)
    ]

    table_data = _arrow_table(records, dim)
    db = lancedb.connect(cfg.index_uri)
    db.drop_table(TABLE_NAME, ignore_missing=True)
    table = db.create_table(TABLE_NAME, table_data, mode="overwrite")
    # Native BM25 full-text index (Tantivy path removed in lancedb 0.33).
    table.create_fts_index("text", replace=True)

    version = content_hash(
        sorted(r["chunk_id"] for r in records), cfg.embed_model, dim
    )
    (cfg.index_dir / INDEX_VERSION_FILE).write_text(version + "\n", encoding="utf-8")
    print(
        f"[cardgen] index: {len(records)} chunk(s) -> table '{TABLE_NAME}' "
        f"(dim={dim}) version={version}"
    )


def open_table(cfg: RunConfig):
    """Open the LanceDB ``chunks`` table for retrieval (stage 5)."""
    import lancedb

    db = lancedb.connect(cfg.index_uri)
    return db.open_table(TABLE_NAME)
