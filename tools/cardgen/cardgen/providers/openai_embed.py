"""Live OpenAI embedding backend (`text-embedding-3-*`).

Selected by `get_embedder(cfg)` only when a key is present and the run is not
offline. The offline embedder in `offline.py` is used for all keyless tests, so
nothing here needs to import `openai` at module load time — it is imported lazily
inside `embed` so the package stays importable with no key/network.
"""

from __future__ import annotations

from typing import Iterator

from tenacity import (
    retry,
    retry_if_exception,
    stop_after_attempt,
    wait_random_exponential,
)

# Native output dimensions per model (used for the fixed-size vector column).
_MODEL_DIMS = {
    "text-embedding-3-small": 1536,
    "text-embedding-3-large": 3072,
    "text-embedding-ada-002": 1536,
}

# OpenAI accepts up to 2048 inputs per request; stay well under and also bound
# total tokens per call in practice by using a conservative batch size.
_MAX_BATCH = 1024


def _batched(items: list[str], size: int) -> Iterator[list[str]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def _is_transient(exc: BaseException) -> bool:
    """True for errors worth retrying (rate limit / timeout / 5xx / connection)."""
    try:
        import openai
    except Exception:  # pragma: no cover - openai always present in live mode
        return False
    transient = (
        openai.APIConnectionError,
        openai.APITimeoutError,
        openai.RateLimitError,
        openai.InternalServerError,
    )
    return isinstance(exc, transient)


class OpenAIEmbedder:
    """Embedder backed by the OpenAI embeddings API.

    Attributes
    ----------
    model: the embedding model id (e.g. ``text-embedding-3-small``).
    dim:   the vector dimension for ``model`` (1536 for ``-3-small``).
    """

    def __init__(self, model: str = "text-embedding-3-small") -> None:
        self.model = model
        self.dim = _MODEL_DIMS.get(model, 1536)

    def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        out: list[list[float]] = []
        for batch in _batched(texts, _MAX_BATCH):
            out.extend(self._embed_batch(batch))
        return out

    @retry(
        retry=retry_if_exception(_is_transient),
        wait=wait_random_exponential(min=1, max=30),
        stop=stop_after_attempt(6),
        reraise=True,
    )
    def _embed_batch(self, batch: list[str]) -> list[list[float]]:
        from openai import OpenAI

        client = OpenAI()
        resp = client.embeddings.create(model=self.model, input=batch)
        # The API preserves input order but guard by sorting on `index`.
        ordered = sorted(resp.data, key=lambda d: d.index)
        return [list(d.embedding) for d in ordered]
