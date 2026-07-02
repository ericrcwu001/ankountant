"""Run configuration, paths, and secret/offline detection."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

try:
    from dotenv import load_dotenv
except Exception:  # pragma: no cover - dotenv optional at import time
    load_dotenv = None

# tools/cardgen/
ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = ROOT / ".env"

if load_dotenv is not None and ENV_PATH.exists():
    load_dotenv(ENV_PATH)

SECTIONS = ["FAR", "REG", "AUD", "BAR", "ISC", "TCP"]


def has_openai_key() -> bool:
    return bool(os.environ.get("OPENAI_API_KEY"))


def offline_forced() -> bool:
    return os.environ.get("CARDGEN_OFFLINE", "") in ("1", "true", "True")


@dataclass
class RunConfig:
    """One pipeline run. `offline` auto-enables when no key is present or forced."""

    run_id: str = "proof"
    sections: list[str] = field(default_factory=lambda: list(SECTIONS))
    target_total: int = 900
    offline: bool = False
    gen_model: str = field(default_factory=lambda: os.environ.get("CARDGEN_GEN_MODEL", "gpt-4o-mini"))
    embed_model: str = field(
        default_factory=lambda: os.environ.get("CARDGEN_EMBED_MODEL", "text-embedding-3-small")
    )
    judge_batch: int = 25
    top_k: int = 6
    relevance_floor: float = 0.0
    leakage_threshold: float = 0.92
    dedup_threshold: float = 0.95
    prompt_version: str = "v1"
    seed: int = 0

    def __post_init__(self) -> None:
        if not self.offline:
            self.offline = offline_forced() or not has_openai_key()

    # ---- paths -------------------------------------------------------------
    @property
    def out_dir(self) -> Path:
        return ROOT / "out" / self.run_id

    def stage_dir(self, name: str) -> Path:
        d = self.out_dir / name
        d.mkdir(parents=True, exist_ok=True)
        return d

    @property
    def corpus_dir(self) -> Path:
        d = ROOT / "corpus"
        d.mkdir(parents=True, exist_ok=True)
        return d

    @property
    def taxonomy_dir(self) -> Path:
        return ROOT / "taxonomy"

    @property
    def gold_dir(self) -> Path:
        return ROOT / "gold"

    @property
    def index_dir(self) -> Path:
        return self.stage_dir("02-index")

    @property
    def index_uri(self) -> str:
        return str(self.index_dir / "lancedb")
