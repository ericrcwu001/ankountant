"""Provider protocols + factory. Live backends are imported lazily."""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from ..config import RunConfig
from ..models import GenRequest, Verdict


@runtime_checkable
class Embedder(Protocol):
    dim: int

    def embed(self, texts: list[str]) -> list[list[float]]: ...


@runtime_checkable
class Generator(Protocol):
    """Returns raw JSON text: {"source_passage": str, "citation": str, "payload": dict}."""

    def generate(self, req: GenRequest) -> str: ...


@runtime_checkable
class Judge(Protocol):
    """cards: [{"item_id","card_type","payload","source_passage","citation"}]."""

    def judge(self, cards: list[dict], rubric: str) -> list[Verdict]: ...


def get_embedder(cfg: RunConfig) -> Embedder:
    if cfg.offline:
        from .offline import OfflineEmbedder

        return OfflineEmbedder()
    from .openai_embed import OpenAIEmbedder

    return OpenAIEmbedder(cfg.embed_model)


def get_generator(cfg: RunConfig) -> Generator:
    if cfg.offline:
        from .offline import OfflineGenerator

        return OfflineGenerator()
    from .openai_generate import OpenAIGenerator

    return OpenAIGenerator(
        cfg.gen_model,
        cfg.prompt_version,
        fallback_model=cfg.gen_fallback_model,
        reasoning_effort=cfg.gen_reasoning_effort,
    )


def get_judge(cfg: RunConfig) -> Judge:
    if cfg.offline:
        from .offline import OfflineJudge

        return OfflineJudge()
    from .cursor_judge import CursorSubagentJudge

    return CursorSubagentJudge(cfg)
