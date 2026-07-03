"""Template / Automatic Item Generation stage (Stage 6, alternate mode).

Expands curated template families x source-pinned data rows into fully-formed
:class:`~cardgen.models.Candidate` records — **no per-card LLM call**. Each family
lives in ``templates/<id>.yaml`` (the skeleton with ``{slot}`` placeholders) and
draws fill rows either inline (``rows:``) or from ``data/<file>.yaml``
(``data_file:``). Every row carries its own provenance (``source_id``,
``locator``, verbatim ``source_passage``, ``citation``), so cards are grounded in
a named public source without any retrieval.

Numeric answers are COMPUTED from a small deterministic ``FORMULAS`` registry so
they are exact and testable; MCQ distractors are curated strings in the data.

Output: ``05-candidates/<item_id>.json`` — identical schema to the RAG path, so
downstream ``selfcheck -> judge -> leakage -> dedup -> emit`` is reused unchanged.

Grounding is verified here (the RAG substring proof happens in ``generate``): a
card's ``source_passage`` must be a substantive, verbatim (whitespace-normalized)
substring of its source's ``00-ingest`` text when that ingest is available.
"""

from __future__ import annotations

import re
from dataclasses import asdict
from pathlib import Path
from typing import Any

import yaml

from .config import RunConfig
from .generate import _build_tags, _substantive
from .models import (
    CARD_TYPES,
    MCQ,
    RECALL,
    TBS_NUMERIC,
    TBS_RESEARCH,
    Candidate,
    read_jsonl,
    write_json,
)
from .util import content_hash, is_substring_normalized

TEMPLATE_STAGE = "05-candidates"
INGEST_STAGE = "00-ingest"

# Deterministic numeric formulas referenced by tbs_numeric step `answer_formula`.
FORMULAS: dict[str, Any] = {
    "lookup": lambda v: v,
    "subtract": lambda a, b: a - b,
    "add": lambda a, b: a + b,
    "multiply": lambda a, b: a * b,
    "straight_line": lambda cost, salvage, life: round((cost - salvage) / life, 2),
    "re_rollforward": lambda beg, ni, div: beg + ni - div,
    "gross_profit": lambda sales, cogs: sales - cogs,
}

_SLOT = re.compile(r"\{([a-zA-Z0-9_]+)(?::(money|int))?\}")


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def _render(text: str, row: dict) -> str:
    """Substitute ``{slot}`` / ``{slot:money}`` / ``{slot:int}`` from ``row``."""
    def repl(m: re.Match) -> str:
        key, fmt = m.group(1), m.group(2)
        if key not in row:
            raise KeyError(f"template slot '{key}' missing from data row")
        v = row[key]
        if fmt == "money":
            return f"{int(round(float(v))):,}"
        if fmt == "int":
            return f"{int(round(float(v)))}"
        return str(v)

    return _SLOT.sub(repl, text)


def _render_obj(obj: Any, row: dict) -> Any:
    if isinstance(obj, str):
        return _render(obj, row)
    if isinstance(obj, list):
        return [_render_obj(x, row) for x in obj]
    if isinstance(obj, dict):
        return {k: _render_obj(v, row) for k, v in obj.items()}
    return obj


def _compute(formula: dict, row: dict) -> float:
    fn = FORMULAS[formula["fn"]]
    args = [row[a] if isinstance(a, str) and a in row else a for a in formula.get("args", [])]
    val = fn(*args)
    return float(val)


# ---------------------------------------------------------------------------
# Payload builders (per card_type)
# ---------------------------------------------------------------------------
def _payload_recall(tpl: dict, row: dict) -> dict:
    return {"front": _render(tpl["front"], row), "back": _render(tpl["back"], row)}


def _payload_mcq(tpl: dict, row: dict) -> dict:
    treatments: list[str] = []
    for t in tpl["treatments"]:
        rendered = _render(t, row)
        if rendered not in treatments:  # keep distractors distinct
            treatments.append(rendered)
    answer_key = _render(tpl["treatments"][tpl.get("answer_index", 0)], row)
    if answer_key not in treatments:
        treatments.insert(0, answer_key)
    return {
        "prompt": _render(tpl["prompt"], row),
        "answer_key": answer_key,
        "ds_tag": _render(tpl.get("ds_tag", "ds::{item_slug}"), row),
        "treatments": treatments,
    }


def _redact_tokens(text: str, tokens: list[str]) -> str:
    """Blank out citation strings so a research exhibit never gives away its answer."""
    for t in tokens:
        if t and len(t) >= 3:
            text = re.sub(re.escape(t), "[citation redacted]", text, flags=re.IGNORECASE)
    return text


def _payload_research(tpl: dict, row: dict) -> dict:
    citations = [str(c) for c in row["citations"]] if isinstance(row.get("citations"), list) else [str(row.get("citations", ""))]
    exhibits = _render_obj(tpl.get("exhibits", [{"title": "Scenario", "kind": "text", "body": "{source_passage}"}]), row)
    # Never reveal the answer: strip the citation(s) — and any row-specified extra
    # tokens (e.g. a control ID/name printed in the requirement) — from exhibits.
    redact = list(citations) + [str(row.get("display_citation", ""))] + [str(t) for t in (row.get("redact") or [])]
    for ex in exhibits:
        if isinstance(ex, dict) and ex.get("body"):
            ex["body"] = _redact_tokens(str(ex["body"]), redact)
    return {
        "prompt": _render(tpl["prompt"], row),
        "exhibits": exhibits,
        "steps": [
            {
                "id": "citation",
                "kind": "citation",
                "answer_key": citations,
                "weight": 1.0,
                "label": _render(tpl.get("step_label", "Governing citation"), row),
                "corpus_refs": [],
                "granularity": "paragraph",
            }
        ],
    }


def _payload_numeric(tpl: dict, row: dict) -> dict:
    steps = []
    for st in tpl["steps"]:
        answer = _compute(st["answer_formula"], row) if "answer_formula" in st else float(row[st["answer_from"]])
        steps.append(
            {
                "id": st.get("id", "c1"),
                "kind": "numeric",
                "answer_key": answer,
                "weight": float(st.get("weight", 1.0)),
                "label": _render(st.get("label", "Amount"), row),
                "tolerance": float(st.get("tolerance", 0.0)),
            }
        )
    exhibits = _render_obj(tpl.get("exhibits", [{"title": "Data", "kind": "text", "body": "{source_passage}"}]), row)
    return {"prompt": _render(tpl["prompt"], row), "exhibits": exhibits, "steps": steps}


_BUILDERS = {
    RECALL: _payload_recall,
    MCQ: _payload_mcq,
    TBS_RESEARCH: _payload_research,
    TBS_NUMERIC: _payload_numeric,
}


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------
def _load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict):
        raise ValueError(f"expected a mapping at top of {path}")
    return data


def load_family(cfg: RunConfig, tpl_path: Path) -> tuple[dict, list[dict]]:
    """Return ``(template, rows)`` for a family file (inline ``rows`` or ``data_file``)."""
    tpl = _load_yaml(tpl_path)
    rows = tpl.get("rows")
    if rows is None and tpl.get("data_file"):
        data_path = cfg.data_dir / tpl["data_file"]
        if data_path.exists():
            rows = (_load_yaml(data_path) or {}).get("rows", [])
        else:
            print(f"[templates] {tpl_path.name}: data_file '{tpl['data_file']}' not found "
                  f"(run scripts/harvest_templates.py); skipping this family")
            rows = []
    return tpl, list(rows or [])


# ---------------------------------------------------------------------------
# Expansion + grounding
# ---------------------------------------------------------------------------
def expand_row(cfg: RunConfig, tpl: dict, row: dict, idx: int) -> Candidate:
    card_type = tpl["card_type"]
    if card_type not in CARD_TYPES:
        raise ValueError(f"template {tpl.get('template_id')}: bad card_type {card_type}")
    section = str(tpl.get("section", row.get("section", "")))
    topic = _render(str(tpl.get("topic", row.get("topic", "core"))), row)
    skill_level = str(tpl.get("skill_level", "Application"))

    payload = _BUILDERS[card_type](tpl, row)
    variant_key = _render(str(tpl.get("variant_key", "{__idx__}")), {**row, "__idx__": idx})
    template_id = str(tpl["template_id"])
    item_id = content_hash(template_id, variant_key)

    gen_method = {
        "method": "template",
        "template_id": template_id,
        "template_version": str(tpl.get("template_version", "v1")),
        "data_file": str(tpl.get("data_file", tpl.get("_src", ""))),
        "data_row_id": str(row.get("id", variant_key)),
        "variant_key": variant_key,
    }
    if "tax_year" in row:
        gen_method["tax_year"] = row["tax_year"]
    if row.get("license"):
        gen_method["license"] = str(row["license"])

    return Candidate(
        item_id=item_id,
        section=section,
        card_type=card_type,
        payload=payload,
        source_passage=str(row.get("source_passage", "")),
        source_id=str(row.get("source_id", "")),
        locator=str(row.get("locator", "whole")),
        citation=_render(str(tpl.get("citation", row.get("citation", ""))), row),
        gen_method=gen_method,
        tags=_build_tags(section, topic, card_type, skill_level, payload),
    )


def _ingest_text(cfg: RunConfig, source_id: str, cache: dict[str, str]) -> str | None:
    """Concatenated 00-ingest text for a source (None if not ingested)."""
    if source_id in cache:
        return cache[source_id] or None
    path = cfg.stage_dir(INGEST_STAGE) / f"{source_id}.jsonl"
    if not path.exists():
        cache[source_id] = ""
        return None
    text = " ".join(str(r.get("text", "")) for r in read_jsonl(path))
    cache[source_id] = text
    return text or None


def verify_grounding(cfg: RunConfig, cand: Candidate, cache: dict[str, str]) -> tuple[bool, str]:
    """A template card must have a substantive citation + source_passage, and the
    passage must be verbatim in the source's ingest text (when available)."""
    if not cand.citation.strip():
        return False, "empty citation"
    if not _substantive(cand.source_passage):
        return False, "source_passage not substantive"
    text = _ingest_text(cfg, cand.source_id, cache)
    if text is None:
        return True, "ingest-missing (grounding unverified)"
    if not is_substring_normalized(cand.source_passage, text):
        return False, "source_passage not found in source ingest"
    return True, ""


# ---------------------------------------------------------------------------
# Stage entry point
# ---------------------------------------------------------------------------
def run(cfg: RunConfig) -> None:
    out_dir = cfg.stage_dir(TEMPLATE_STAGE)
    templates_dir = cfg.templates_dir
    if not templates_dir.exists():
        print(f"[templates] no templates dir at {templates_dir}; nothing to expand")
        return

    cache: dict[str, str] = {}
    n_written = n_dropped = n_unverified = 0
    drop_reasons: dict[str, int] = {}
    seen_ids: set[str] = set()

    for tpl_path in sorted(templates_dir.glob("*.yaml")):
        tpl, rows = load_family(cfg, tpl_path)
        tpl.setdefault("_src", tpl_path.name)
        for idx, row in enumerate(rows):
            try:
                cand = expand_row(cfg, tpl, row, idx)
            except (KeyError, ValueError) as exc:
                n_dropped += 1
                drop_reasons[str(exc)[:40]] = drop_reasons.get(str(exc)[:40], 0) + 1
                continue
            if cfg.sections and cand.section not in cfg.sections:
                continue
            if cand.item_id in seen_ids:
                continue  # idempotent / de-collide identical variant keys
            ok, reason = verify_grounding(cfg, cand, cache)
            if not ok:
                n_dropped += 1
                drop_reasons[reason] = drop_reasons.get(reason, 0) + 1
                continue
            if reason:
                n_unverified += 1
            seen_ids.add(cand.item_id)
            write_json(out_dir / f"{cand.item_id}.json", asdict(cand))
            n_written += 1

    print(f"[templates] expanded {n_written} card(s), dropped {n_dropped} {dict(drop_reasons)}")
    if n_unverified:
        print(f"[templates] WARNING {n_unverified} card(s) grounded but unverified (source not ingested)")
