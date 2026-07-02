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

# Judge modes (Stage 8). ``full`` judges every shipped candidate; ``audit``
# judges a deterministic statistical sample (+ every self-check-flagged card) and
# lets deterministic self-check gate the remainder — the tractable path at 50k.
JUDGE_FULL = "full"
JUDGE_AUDIT = "audit"


def has_openai_key() -> bool:
    return bool(os.environ.get("OPENAI_API_KEY"))


def offline_forced() -> bool:
    return os.environ.get("CARDGEN_OFFLINE", "") in ("1", "true", "True")


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, "") or default)
    except (TypeError, ValueError):
        return default


def _env_flag(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


@dataclass
class RunConfig:
    """One pipeline run. `offline` auto-enables when no key is present or forced."""

    run_id: str = "proof"
    sections: list[str] = field(default_factory=lambda: list(SECTIONS))
    target_total: int = 900
    offline: bool = False
    # Generator: default to gpt-5-mini (a reasoning model — the API params are made
    # model-aware in openai_generate.py) with a plain-chat fallback on 404.
    gen_model: str = field(default_factory=lambda: os.environ.get("CARDGEN_GEN_MODEL", "gpt-5-mini"))
    gen_fallback_model: str = field(
        default_factory=lambda: os.environ.get("CARDGEN_GEN_FALLBACK_MODEL", "gpt-4o")
    )
    # Reasoning effort for gpt-5*/o* models (minimal|low|medium|high); ignored for
    # 4o-family models. "low" keeps cost/latency down for card writing.
    gen_reasoning_effort: str = field(
        default_factory=lambda: os.environ.get("CARDGEN_REASONING_EFFORT", "low")
    )
    embed_model: str = field(
        default_factory=lambda: os.environ.get("CARDGEN_EMBED_MODEL", "text-embedding-3-small")
    )
    judge_batch: int = 25
    top_k: int = 6
    relevance_floor: float = 0.0
    leakage_threshold: float = 0.92
    dedup_threshold: float = 0.95
    # v2 prompt adds the decline rule ({"skip": true}) + no schema placeholders +
    # TBS numbers-must-be-in-the-passage discipline (see openai_generate.py).
    prompt_version: str = field(default_factory=lambda: os.environ.get("CARDGEN_PROMPT_VERSION", "v2"))
    seed: int = 0

    # ---- retrieval reranker (Stage 5) --------------------------------------
    # Rerank the fused hybrid arm; deterministic lexical fallback offline / on any
    # LLM error, so the offline path stays reproducible.
    rerank: bool = field(default_factory=lambda: _env_flag("CARDGEN_RERANK", True))
    rerank_model: str = field(
        default_factory=lambda: os.environ.get("CARDGEN_RERANK_MODEL", "gpt-4o-mini")
    )

    # ---- throughput fan-out (Stages 3 / 6) ---------------------------------
    # Bounded concurrency for the live generation + embedding drivers. Offline
    # stays sequential + deterministic regardless of these.
    gen_concurrency: int = field(default_factory=lambda: _env_int("CARDGEN_CONCURRENCY", 24))
    embed_concurrency: int = field(default_factory=lambda: _env_int("CARDGEN_EMBED_CONCURRENCY", 8))
    # Optional OpenAI Batch API path for the big (50k) live generation (~50% off,
    # async/overnight). Off by default; the concurrent driver is the default.
    use_batch_api: bool = field(default_factory=lambda: _env_flag("CARDGEN_BATCH_API", False))

    # ---- judging at scale (Stage 8) ----------------------------------------
    judge_mode: str = field(default_factory=lambda: os.environ.get("CARDGEN_JUDGE_MODE", JUDGE_FULL))
    # audit mode: judge max(audit_min, audit_fraction*N) cards; the rest are
    # gated by deterministic self-check (already passed to reach Stage 8).
    audit_fraction: float = 0.10
    audit_min: int = 50
    # How many parallel Cursor judge subagents the wave-plan targets.
    judge_parallelism: int = field(default_factory=lambda: _env_int("CARDGEN_JUDGE_PARALLELISM", 8))

    def __post_init__(self) -> None:
        if not self.offline:
            self.offline = offline_forced() or not has_openai_key()
        if self.judge_mode not in (JUDGE_FULL, JUDGE_AUDIT):
            self.judge_mode = JUDGE_FULL

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
