"""Provider backends: embedder / generator / judge.

`base.get_*` returns the deterministic offline backend when `cfg.offline` is
set (no key / CARDGEN_OFFLINE=1), else the live backend. Live backends
(openai_embed, openai_generate, cursor_judge) are imported lazily so the offline
path never requires them.
"""

from .base import Embedder, Generator, Judge, get_embedder, get_generator, get_judge

__all__ = [
    "Embedder",
    "Generator",
    "Judge",
    "get_embedder",
    "get_generator",
    "get_judge",
]
