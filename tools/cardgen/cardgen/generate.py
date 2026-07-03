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
import re
from dataclasses import asdict
from pathlib import Path
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


# A grounded source_passage must be a real sentence, not a heading/label/stub
# ("K-1", "Example 1", "(B) Ethics"). We require a minimum of substantive words.
MIN_SP_WORDS = 6
_SP_WORDS = re.compile(r"[A-Za-z][A-Za-z'-]+")
_SENT_SPLIT = re.compile(r"(?<=[.!?])\s+")


def _substantive(text: str) -> bool:
    """True if ``text`` has enough real words to teach/ground a card."""
    return len(_SP_WORDS.findall(text or "")) >= MIN_SP_WORDS


def _first_substantive_sentence(text: str, maxlen: int = 240) -> str:
    """First sentence of ``text`` with >= ``MIN_SP_WORDS`` words (else "").

    Verbatim (whitespace-normalized) substring of ``text`` so grounding still
    proves out in self-check.
    """
    t = normalize_text(text)
    for part in _SENT_SPLIT.split(t):
        if _substantive(part):
            return part[:maxlen]
    return ""


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


# ---- finalize (shared by the sync + Batch-API paths) -----------------------
def finalize_candidate(
    cfg: RunConfig, item: dict, passages: list[Passage], raw: str
) -> Optional[Candidate]:
    """Turn one generator ``raw`` JSON string into a grounded :class:`Candidate`.

    Returns ``None`` when the model declined (v2 ``{"skip": true}``), the output
    is unparseable, or grounding cannot be established/repaired. Shared by the
    inline generator and the OpenAI Batch-API collector so both apply the exact
    same grounding + provenance rules.
    """
    item_id = str(item.get("item_id", ""))
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, TypeError) as exc:
        print(f"[cardgen] generate: {item_id}: unparseable generator output ({exc}); dropping")
        return None
    if not isinstance(data, dict):
        print(f"[cardgen] generate: {item_id}: generator output not a JSON object; dropping")
        return None

    # v2 decline rule: the model may return {"skip": true, "reason": ...}.
    if data.get("skip"):
        reason = str(data.get("reason", "") or "unsupported")
        print(f"[cardgen] generate: {item_id}: declined ({reason})")
        return None

    section = str(item.get("section", ""))
    card_type = str(item.get("card_type", ""))
    skill_level = str(item.get("skill_level", ""))
    topic = str(item.get("topic", ""))
    seed = int(item.get("seed", 0) or 0)

    source_passage = str(data.get("source_passage", "") or "")
    citation = str(data.get("citation", "") or "")
    payload = data.get("payload") if isinstance(data.get("payload"), dict) else {}

    # Grounding proof (or repair, or drop). The source_passage must be a real,
    # substantive sentence — never a heading/label/stub. If the model's passage
    # isn't a genuine substring, or is too thin, repair to the first substantive
    # sentence of the grounding chunk; drop the card if none exists.
    matched = _match_passage(source_passage, passages)
    if matched is None:
        matched = _best_passage(passages)
        source_passage = ""
    if not _substantive(source_passage):
        repaired = _first_substantive_sentence(matched.text)
        if not repaired:
            print(f"[cardgen] generate: {item_id}: no substantive grounded sentence; dropping")
            return None
        source_passage = repaired

    gen_method: dict[str, Any] = {
        "model": cfg.gen_model,
        "prompt_version": cfg.prompt_version,
        "retrieval_config": {"top_k": cfg.top_k, "arm": "hybrid", "rerank": bool(cfg.rerank)},
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


def _gen_request(cfg: RunConfig, item: dict, passages: list[Passage]) -> GenRequest:
    return GenRequest(
        item_id=str(item.get("item_id", "")),
        section=str(item.get("section", "")),
        card_type=str(item.get("card_type", "")),
        skill_level=str(item.get("skill_level", "")),
        topic=str(item.get("topic", "")),
        passages=passages,
        prompt_version=cfg.prompt_version,
        seed=int(item.get("seed", 0) or 0),
    )


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
    generator = gen or get_generator(cfg)
    req = _gen_request(cfg, item, passages)
    return finalize_candidate(cfg, item, passages, generator.generate(req))


def _gen_and_write(
    cfg: RunConfig, item: dict, passages: list[Passage], out_path: Path, gen: Generator
) -> bool:
    """Generate one candidate and persist it (returns True iff written).

    Per-item exceptions are swallowed (logged) so one failure never aborts a
    large run; the item simply becomes a coverage gap.
    """
    item_id = str(item.get("item_id", out_path.stem))
    try:
        cand = generate_one(cfg, item, passages, gen=gen)
    except Exception as exc:  # noqa: BLE001 - keep a 50k run alive past one failure
        print(f"[cardgen] generate: {item_id}: generation error ({type(exc).__name__}: {exc}); skipping")
        return False
    if cand is None:
        return False
    write_json(out_path, asdict(cand))
    return True


def _collect_work(cfg: RunConfig) -> list[tuple[str, dict, list[Passage], Path]]:
    """(item_id, item, passages, out_path) for every retrieved item still needing
    a candidate. Already-written candidates are skipped (resumable/idempotent)."""
    worklist = cfg.stage_dir("03-worklist") / "worklist.jsonl"
    items = {str(it.get("item_id")): it for it in read_jsonl(worklist)}
    retrieved_dir = cfg.stage_dir("04-retrieved")
    out_dir = cfg.stage_dir("05-candidates")

    work: list[tuple[str, dict, list[Passage], Path]] = []
    for path in sorted(retrieved_dir.glob("*.json")):
        rec = read_json(path)
        item_id = str(rec.get("item_id", path.stem))
        if rec.get("skipped") or not rec.get("passages"):
            continue
        item = items.get(item_id)
        if item is None:
            print(f"[cardgen] generate: {item_id}: no worklist entry; skipping")
            continue
        out_path = out_dir / f"{item_id}.json"
        if out_path.exists() and out_path.stat().st_size > 0:
            continue  # resume: already generated
        passages = [Passage(**p) for p in rec["passages"]]
        work.append((item_id, item, passages, out_path))
    return work


def _run_concurrent(cfg: RunConfig, work: list, gen: Generator) -> int:
    """Bounded-concurrency live driver (asyncio + semaphore, sync gen off-thread)."""
    import asyncio

    async def _driver() -> list[bool]:
        sem = asyncio.Semaphore(max(1, cfg.gen_concurrency))

        async def _one(entry: tuple) -> bool:
            _item_id, item, passages, out_path = entry
            async with sem:
                return await asyncio.to_thread(_gen_and_write, cfg, item, passages, out_path, gen)

        return list(await asyncio.gather(*(_one(e) for e in work)))

    return sum(asyncio.run(_driver()))


# ---- public: run -----------------------------------------------------------
def run(cfg: RunConfig) -> None:
    work = _collect_work(cfg)
    gen = get_generator(cfg)
    total = len(work)

    if not work:
        print("[cardgen] generate: nothing to do (all candidates present or no passages)")
        return

    if cfg.use_batch_api and not cfg.offline:
        from .providers.openai_batch import run_batch_generation

        n_written = run_batch_generation(cfg, work)
    elif cfg.offline or cfg.gen_concurrency <= 1:
        # Offline / single-threaded: strictly sequential + deterministic.
        n_written = sum(
            _gen_and_write(cfg, item, passages, out_path, gen)
            for _item_id, item, passages, out_path in work
        )
    else:
        n_written = _run_concurrent(cfg, work, gen)

    print(f"[cardgen] generate: {n_written} candidates written, {total - n_written} skipped/declined")
