"""Optional OpenAI **Batch API** generation path (Stage 6, live only).

For the full 50k build this is ~50% cheaper than synchronous calls (async, up to
a 24h completion window). It is OFF by default (``cfg.use_batch_api`` /
``--batch-api``); the bounded-concurrency driver in :mod:`cardgen.generate` is
the default live path.

Flow: build one chat-completions request per work item (reusing the exact prompt
+ model-aware body from :class:`OpenAIGenerator`), upload the JSONL, create the
batch, poll to completion, then feed each response through
:func:`cardgen.generate.finalize_candidate` so the Batch and inline paths apply
identical grounding + provenance rules.

Everything here imports ``openai`` lazily; this module never loads in offline
tests. It is inherently live-only, so it has no offline unit test — the pieces it
reuses (prompt build, ``finalize_candidate``) are covered elsewhere.
"""

from __future__ import annotations

import json
import time
from dataclasses import asdict
from pathlib import Path
from typing import TYPE_CHECKING

from ..config import RunConfig
from ..models import Passage, write_json

if TYPE_CHECKING:  # pragma: no cover
    pass

_POLL_SECONDS = 30
# Safety cap on how long we block waiting for a batch (the API window is 24h; a
# long-running build can re-invoke to resume, since finished items are skipped).
_MAX_WAIT_SECONDS = 24 * 60 * 60


def _build_generator(cfg: RunConfig):
    from .openai_generate import OpenAIGenerator

    return OpenAIGenerator(
        cfg.gen_model,
        cfg.prompt_version,
        fallback_model=cfg.gen_fallback_model,
        reasoning_effort=cfg.gen_reasoning_effort,
    )


def run_batch_generation(
    cfg: RunConfig, work: list[tuple[str, dict, list[Passage], Path]]
) -> int:
    """Generate every item in ``work`` via the Batch API; write candidates.

    Returns the number of candidates written. Best-effort: any per-item error is
    logged and skipped (the item becomes a coverage gap).
    """
    from openai import OpenAI

    from ..generate import _gen_request, finalize_candidate

    client = OpenAI()
    gen = _build_generator(cfg)

    index: dict[str, tuple[dict, list[Passage], Path]] = {}
    lines: list[str] = []
    for item_id, item, passages, out_path in work:
        req = _gen_request(cfg, item, passages)
        body = gen.request_body(req)
        lines.append(
            json.dumps(
                {
                    "custom_id": item_id,
                    "method": "POST",
                    "url": "/v1/chat/completions",
                    "body": body,
                },
                ensure_ascii=False,
            )
        )
        index[item_id] = (item, passages, out_path)

    batch_dir = cfg.stage_dir("05-candidates") / "_batch"
    batch_dir.mkdir(parents=True, exist_ok=True)
    in_path = batch_dir / "requests.jsonl"
    in_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"[batch] uploading {len(lines)} request(s)…")
    up = client.files.create(file=in_path.open("rb"), purpose="batch")
    batch = client.batches.create(
        input_file_id=up.id,
        endpoint="/v1/chat/completions",
        completion_window="24h",
    )
    print(f"[batch] created {batch.id}; polling every {_POLL_SECONDS}s (window 24h)")

    waited = 0
    while waited <= _MAX_WAIT_SECONDS:
        batch = client.batches.retrieve(batch.id)
        status = batch.status
        counts = getattr(batch, "request_counts", None)
        print(f"[batch] status={status} counts={counts}")
        if status in ("completed", "failed", "expired", "cancelled"):
            break
        time.sleep(_POLL_SECONDS)
        waited += _POLL_SECONDS

    if batch.status != "completed":
        print(f"[batch] did not complete (status={batch.status}); wrote 0. Re-run to resume.")
        return 0

    out_file_id = batch.output_file_id
    if not out_file_id:
        print("[batch] no output file; wrote 0")
        return 0
    content = client.files.content(out_file_id).text
    (batch_dir / "output.jsonl").write_text(content, encoding="utf-8")

    n_written = 0
    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            cid = obj["custom_id"]
            body = obj["response"]["body"]
            raw = body["choices"][0]["message"]["content"]
        except (json.JSONDecodeError, KeyError, TypeError, IndexError) as exc:
            print(f"[batch] malformed response line ({exc}); skipping")
            continue
        entry = index.get(cid)
        if entry is None:
            continue
        item, passages, out_path = entry
        cand = finalize_candidate(cfg, item, passages, raw)
        if cand is not None:
            write_json(out_path, asdict(cand))
            n_written += 1

    print(f"[batch] wrote {n_written}/{len(work)} candidates")
    return n_written
