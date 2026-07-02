"""Stage 6 — grounded, provenance-emitting generation.

The generator (offline deterministic backend, or the live OpenAI backend) is
handed a :class:`GenRequest` and returns raw JSON
``{"source_passage", "citation", "payload"}``. We then *prove grounding*: the
model's ``source_passage`` must be a whitespace-normalized substring of one of
the retrieved passages. If it is not, we repair it to the leading sentence of
the best passage (so the card stays honestly grounded) — or drop the item if
even that is empty.

Provenance (``source_id`` / ``locator`` / ``gen_method``) and tags
(``sec::`` / ``cog::`` / ``topic::`` / optional ``ds::``) are attached here.
"""

from __future__ import annotations

import json
from dataclasses import asdict
from typing import Any, Optional

from .config import RunConfig
from .models import (
    MCQ,
    RECALL,
    TBS_DOC_REVIEW,
    Candidate,
    GenRequest,
    Passage,
    read_json,
    read_jsonl,
    write_json,
)
from .providers.base import Generator, get_generator
from .util import is_substring_normalized, normalize_text, slugify


# ---- grounding helpers -----------------------------------------------------
def _match_passage(source_passage: str, passages: list[Passage]) -> Optional[Passage]:
    """The first retrieved passage that literally contains ``source_passage``."""
    if not source_passage:
        return None
    for p in passages:
        if is_substring_normalized(source_passage, p.text):
            return p
    return None


def _best_passage(passages: list[Passage]) -> Passage:
    return max(passages, key=lambda p: p.score)


def _leading_sentence(text: str, maxlen: int = 180) -> str:
    """A verbatim leading fragment of ``text`` (mirrors the offline backend)."""
    t = normalize_text(text)
    lead = t.split(". ")[0][:maxlen]
    return lead or t[:maxlen]


# ---- gen_method / tags -----------------------------------------------------
def _read_index_version(cfg: RunConfig) -> str:
    # 02-index/index_version.txt — read without creating the stage dir.
    path = cfg.out_dir / "02-index" / "index_version.txt"
    try:
        if path.exists():
            return path.read_text(encoding="utf-8").strip()
    except OSError:
        pass
    return ""


def _is_remember_understand(skill_level: str) -> bool:
    s = (skill_level or "").strip().lower()
    if not s:
        return False
    if "remember" in s or "understand" in s:
        return True
    return s in {"r&u", "ru", "r_u", "r-u", "remembering & understanding"}


def _derive_ds_tag(payload: dict, topic: str) -> str:
    """A ``ds::`` (distinguishing-set) tag for MCQ / doc-review items."""
    raw = payload.get("ds_tag")
    if raw:
        text = str(raw)
        return text if text.startswith("ds::") else f"ds::{text}"

    cs = payload.get("confusion_set_id")
    if not cs:
        for step in payload.get("steps", []) or []:
            if isinstance(step, dict) and step.get("confusion_set_id"):
                cs = step["confusion_set_id"]
                break
    if cs:
        text = str(cs)
        return text if text.startswith("ds::") else f"ds::{slugify(text)}"

    return f"ds::{slugify(topic)}"


def _build_tags(section: str, topic: str, card_type: str, skill_level: str, payload: dict) -> list[str]:
    cog = "cog::rote" if (card_type == RECALL and _is_remember_understand(skill_level)) else "cog::applied"
    tags = [f"sec::{section}", cog, f"topic::{slugify(topic)}"]
    if card_type in (MCQ, TBS_DOC_REVIEW):
        tags.append(_derive_ds_tag(payload, topic))
    return tags


# ---- public: generate_one --------------------------------------------------
def generate_one(
    cfg: RunConfig,
    item: dict,
    passages: list[Passage],
    gen: Optional[Generator] = None,
) -> Optional[Candidate]:
    """Generate one grounded :class:`Candidate` (or ``None`` if impossible)."""
    if not passages:
        return None

    item_id = str(item.get("item_id", ""))
    section = str(item.get("section", ""))
    card_type = str(item.get("card_type", ""))
    skill_level = str(item.get("skill_level", ""))
    topic = str(item.get("topic", ""))
    seed = int(item.get("seed", 0) or 0)

    req = GenRequest(
        item_id=item_id,
        section=section,
        card_type=card_type,
        skill_level=skill_level,
        topic=topic,
        passages=passages,
        prompt_version=cfg.prompt_version,
        seed=seed,
    )

    generator = gen or get_generator(cfg)
    try:
        data = json.loads(generator.generate(req))
    except (json.JSONDecodeError, TypeError) as exc:
        print(f"[cardgen] generate: {item_id}: unparseable generator output ({exc}); dropping")
        return None

    source_passage = str(data.get("source_passage", "") or "")
    citation = str(data.get("citation", "") or "")
    payload = data.get("payload") if isinstance(data.get("payload"), dict) else {}

    # Grounding proof (or repair, or drop).
    matched = _match_passage(source_passage, passages)
    if matched is None:
        matched = _best_passage(passages)
        repaired = _leading_sentence(matched.text)
        if not repaired:
            print(f"[cardgen] generate: {item_id}: ungrounded source_passage and no repair; dropping")
            return None
        source_passage = repaired

    gen_method: dict[str, Any] = {
        "model": cfg.gen_model,
        "prompt_version": cfg.prompt_version,
        "retrieval_config": {"top_k": cfg.top_k, "arm": "hybrid"},
        "index_version": _read_index_version(cfg),
        "seed": seed,
    }

    return Candidate(
        item_id=item_id,
        section=section,
        card_type=card_type,
        payload=payload,
        source_passage=source_passage,
        source_id=matched.source_id,
        locator=matched.locator,
        citation=citation,
        gen_method=gen_method,
        tags=_build_tags(section, topic, card_type, skill_level, payload),
    )


# ---- public: run -----------------------------------------------------------
def run(cfg: RunConfig) -> None:
    worklist = cfg.stage_dir("03-worklist") / "worklist.jsonl"
    items = {str(it.get("item_id")): it for it in read_jsonl(worklist)}

    retrieved_dir = cfg.stage_dir("04-retrieved")
    out_dir = cfg.stage_dir("05-candidates")
    gen = get_generator(cfg)

    n_written = n_skipped = 0
    for path in sorted(retrieved_dir.glob("*.json")):
        rec = read_json(path)
        item_id = str(rec.get("item_id", path.stem))
        if rec.get("skipped") or not rec.get("passages"):
            n_skipped += 1
            continue
        item = items.get(item_id)
        if item is None:
            print(f"[cardgen] generate: {item_id}: no worklist entry; skipping")
            n_skipped += 1
            continue

        passages = [Passage(**p) for p in rec["passages"]]
        candidate = generate_one(cfg, item, passages, gen=gen)
        if candidate is None:
            n_skipped += 1
            continue
        write_json(out_dir / f"{item_id}.json", asdict(candidate))
        n_written += 1

    print(f"[cardgen] generate: {n_written} candidates, {n_skipped} skipped")
