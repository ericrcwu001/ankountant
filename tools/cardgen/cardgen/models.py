"""Shared data contracts for every pipeline stage.

These dataclasses + constants are the authoritative in-memory contract; the
on-disk artifact schemas are documented in
docs_ankountant/rag/07-implementation-contract.md.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator

# ---- card types (our internal taxonomy) -----------------------------------
RECALL = "recall"
MCQ = "mcq"
TBS_RESEARCH = "tbs_research"
TBS_NUMERIC = "tbs_numeric"
TBS_JE = "tbs_je"
TBS_DOC_REVIEW = "tbs_doc_review"
CARD_TYPES = [RECALL, MCQ, TBS_RESEARCH, TBS_NUMERIC, TBS_JE, TBS_DOC_REVIEW]

# maps our card_type -> the app's `tbs_type` field string (for TBS/MCQ notes)
TBS_TYPE_FOR = {
    MCQ: "mcq",
    TBS_RESEARCH: "research",
    TBS_NUMERIC: "numeric",
    TBS_JE: "journal_entry",
    TBS_DOC_REVIEW: "doc_review",
}

# ---- judge buckets (the 3-bucket gate) ------------------------------------
BUCKET_OK = "correct_useful"   # ship
BUCKET_WRONG = "wrong"          # auto-block
BUCKET_BAD = "bad_teaching"     # quarantine
BUCKETS = [BUCKET_OK, BUCKET_WRONG, BUCKET_BAD]


@dataclass
class Chunk:
    chunk_id: str
    source_id: str
    locator: str
    license: str
    heading_path: str
    section: str
    text: str


@dataclass
class Passage:
    chunk_id: str
    text: str
    source_id: str
    locator: str
    score: float = 0.0


@dataclass
class WorkItem:
    item_id: str
    section: str
    area: str
    topic: str
    task_id: str
    skill_level: str
    card_type: str
    seed: int = 0
    category: str = ""
    category_tags: list[str] = field(default_factory=list)
    treatments: list[str] = field(default_factory=list)


@dataclass
class GenRequest:
    """Structured input to a Generator (the backend builds the prompt itself)."""

    item_id: str
    section: str
    card_type: str
    skill_level: str
    topic: str
    passages: list[Passage]
    prompt_version: str = "v1"
    seed: int = 0


@dataclass
class Candidate:
    """A generated card + full provenance, before gating."""

    item_id: str
    section: str
    card_type: str
    payload: dict[str, Any]
    source_passage: str
    source_id: str
    locator: str
    citation: str
    gen_method: dict[str, Any] = field(default_factory=dict)
    tags: list[str] = field(default_factory=list)


@dataclass
class Verdict:
    item_id: str
    bucket: str
    reason: str = ""
    faithful: float = 1.0


# ---- jsonl helpers ---------------------------------------------------------
def _row(obj: Any) -> dict:
    if isinstance(obj, dict):
        return obj
    return asdict(obj)


def write_jsonl(path: str | Path, rows: Iterable[Any]) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(_row(r), ensure_ascii=False) + "\n")
    return path


def read_jsonl(path: str | Path) -> Iterator[dict]:
    path = Path(path)
    if not path.exists():
        return
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def write_json(path: str | Path, obj: Any) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def read_json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))
