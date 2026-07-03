#!/usr/bin/env python3
"""Harvest source-pinned template DATA rows from an ingested corpus.

Reads ``out/<run_id>/00-ingest/*.jsonl`` (produced by ``cardgen ingest``) and
writes ``data/*.yaml`` fill rows for the template families. Every row's
``source_passage`` is a VERBATIM substring of a single ingest page, so the
template stage's grounding check passes and each card traces to a named source.

Seams harvested (max-volume, low per-card error):
- NIST SP 800-53 controls  -> data/nist_controls.yaml  (tbs_research, ISC, public)
- AU-C references          -> data/auc_citations.yaml  (tbs_research, AUD, personal-use)
- IRS dollar thresholds    -> data/irs_cloze.yaml      (recall cloze, REG/TCP, public)

Usage:
    uv run python scripts/harvest_templates.py --run-id tmpl3 [--irs-cap 60]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from cardgen.config import RunConfig  # noqa: E402
from cardgen.models import read_jsonl  # noqa: E402

# IRS pub -> CPA section (for cloze rows).
IRS_SECTION = {
    "irs_p17": "REG", "irs_p501": "REG", "irs_p970": "REG", "irs_p505": "REG",
    "irs_p535": "REG", "irs_p946": "REG", "irs_pcir230": "REG",
    "irs_p334": "TCP", "irs_p541": "TCP", "irs_p542": "TCP", "irs_p544": "TCP",
    "irs_p550": "TCP", "irs_p551": "TCP",
}

_WS = re.compile(r"\s+")


def _norm(s: str) -> str:
    return _WS.sub(" ", s).strip()


def _pages(cfg: RunConfig, source_id: str) -> list[tuple[str, str]]:
    """(locator, page_text) for each ingest row of a source."""
    path = cfg.stage_dir("00-ingest") / f"{source_id}.jsonl"
    return [(r.get("locator", "whole"), r.get("text", "")) for r in read_jsonl(path)]


# ---------------------------------------------------------------------------
# NIST SP 800-53 controls
# ---------------------------------------------------------------------------
_NIST = re.compile(
    r"\b([A-Z]{2}-\d{1,2})\s+([A-Z][A-Z0-9 ,/&\-]{4,60}?)\s+(Control:\s*[a-z]\.\s*[^\n]{20,220}?[.;])",
)


def harvest_nist(cfg: RunConfig) -> list[dict]:
    rows: list[dict] = []
    seen: set[str] = set()
    for locator, text in _pages(cfg, "nist_800_53"):
        for cid, name, stmt in _NIST.findall(text):
            cid = cid.strip()
            if cid in seen:
                continue
            name = _norm(name)
            stmt = _norm(stmt)
            # Verbatim header+statement (grounds the ID -> answer mapping).
            passage = _norm(f"{cid} {name} {stmt}")
            if passage not in _norm(text):
                continue  # must be a real single-page substring
            seen.add(cid)
            rows.append({
                "row_id": f"nist_{cid.replace('-', '_').lower()}",
                "control_id": cid,
                "topic": name.lower(),
                "citations": [f"NIST SP 800-53 {cid}"],
                "display_citation": f"NIST SP 800-53, Rev. 5, {cid}",
                "source_id": "nist_800_53",
                "locator": locator,
                "source_passage": passage,
                "redact": [cid, name],
                "license": "public",
            })
    return rows


# ---------------------------------------------------------------------------
# AU-C references
# ---------------------------------------------------------------------------
_AUC_SENT = re.compile(r"([A-Z][^.]{30,240}?\(AU-C\s*(\d{3})\)[^.]{0,40}\.)")


def harvest_auc(cfg: RunConfig, per_id: int = 2) -> list[dict]:
    rows: list[dict] = []
    counts: dict[str, int] = {}
    for locator, text in _pages(cfg, "cpa_aud_review"):
        for sent, num in _AUC_SENT.findall(text):
            sent = _norm(sent)
            if len(sent) > 240 or counts.get(num, 0) >= per_id:
                continue
            if sent not in _norm(text):
                continue
            counts[num] = counts.get(num, 0) + 1
            rows.append({
                "row_id": f"auc_{num}_{counts[num]}",
                "topic": "the matter described in the exhibit",
                "citations": [f"AU-C {num}"],
                "display_citation": f"AU-C {num}",
                "source_id": "cpa_aud_review",
                "locator": locator,
                "source_passage": sent,
                "redact": [f"(AU-C {num})", f"AU-C {num}"],
                "license": "personal_use",
            })
    return rows


# ---------------------------------------------------------------------------
# IRS dollar-threshold cloze
# ---------------------------------------------------------------------------
_MONEY = re.compile(r"\$[\d,]{3,}(?:\.\d+)?")
_SENT = re.compile(r"([A-Z][^.]{25,180}?\$[\d,]{3,}[^.]{0,90}?\.)")


def harvest_irs_cloze(cfg: RunConfig, cap_per_source: int = 30) -> list[dict]:
    rows: list[dict] = []
    for source_id, section in IRS_SECTION.items():
        n = 0
        for locator, text in _pages(cfg, source_id):
            if n >= cap_per_source:
                break
            for sent in _SENT.findall(text):
                if n >= cap_per_source:
                    break
                sent = _norm(sent)
                amounts = _MONEY.findall(sent)
                if not (1 <= len(amounts) <= 3):
                    continue
                if sent not in _norm(text):
                    continue
                cloze = sent
                for a in amounts:
                    cloze = cloze.replace(a, "_____", 1)
                rows.append({
                    "row_id": f"{source_id}_{locator}_{n}",
                    "section": section,
                    "topic": "Individual and entity thresholds",
                    "cloze": cloze,
                    "answer": ", ".join(amounts),
                    "display_citation": f"{source_id} {locator}",
                    "source_id": source_id,
                    "locator": locator,
                    "source_passage": sent,
                    "license": "public",
                })
                n += 1
    return rows


def _write(cfg: RunConfig, name: str, section_hint: str, rows: list[dict]) -> None:
    cfg.data_dir.mkdir(parents=True, exist_ok=True)
    (cfg.data_dir / name).write_text(
        yaml.safe_dump({"section": section_hint, "rows": rows}, sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    )
    print(f"[harvest] {name}: {len(rows)} rows")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser("harvest_templates")
    ap.add_argument("--run-id", default="tmpl3")
    ap.add_argument("--irs-cap", type=int, default=30, help="max cloze rows per IRS source")
    args = ap.parse_args(argv)
    cfg = RunConfig(run_id=args.run_id)

    _write(cfg, "nist_controls.yaml", "ISC", harvest_nist(cfg))
    _write(cfg, "auc_citations.yaml", "AUD", harvest_auc(cfg))
    _write(cfg, "irs_cloze.yaml", "REG", harvest_irs_cloze(cfg, args.irs_cap))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
