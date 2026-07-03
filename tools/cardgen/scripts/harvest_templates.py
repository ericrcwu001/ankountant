#!/usr/bin/env python3
"""Harvest source-pinned template DATA rows from an ingested corpus.

Reads ``out/<run_id>/00-ingest/*.jsonl`` (produced by ``cardgen ingest``) and
writes ``data/*.yaml`` fill rows for the template families. Every row's
``source_passage`` is a VERBATIM substring of a single ingest page, so the
template stage's grounding check passes and each card traces to a named source.

Seams harvested (max-volume, high per-card precision):
- NIST SP 800-53 controls  -> data/nist_controls.yaml  (tbs_research, ISC, public)
- AU-C references          -> data/auc_citations.yaml  (tbs_research, AUD, personal-use)
- IRS dollar thresholds    -> data/irs_cloze.yaml      (recall cloze, REG/TCP, public)

The IRS cloze filter is tuned against the judge's own labels from a prior run:
it keeps rule/threshold statements tied to a NAMED provision and rejects
worked-example figures, proper-name narratives, worksheet/formula fragments,
anaphoric ("this/your deduction ...") fragments, and multi-value tables. This
lifts the cloze judge ship-rate well above the naive "blank any $ sentence"
harvester while growing the pool by iterating every ingested IRS pub.

Usage:
    uv run python scripts/harvest_templates.py --run-id tmpl4 \
        [--irs-cap 120] [--auc-cap 4]
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

# Friendly, human-readable citations for the card front.
PUB_NAMES = {
    "irs_p17": "IRS Pub. 17", "irs_p334": "IRS Pub. 334", "irs_p501": "IRS Pub. 501",
    "irs_p505": "IRS Pub. 505", "irs_p535": "IRS Pub. 535", "irs_p541": "IRS Pub. 541",
    "irs_p542": "IRS Pub. 542", "irs_p544": "IRS Pub. 544", "irs_p550": "IRS Pub. 550",
    "irs_p551": "IRS Pub. 551", "irs_p946": "IRS Pub. 946", "irs_p970": "IRS Pub. 970",
    "irs_pcir230": "Treasury Circular 230",
}

_WS = re.compile(r"\s+")
# OCR line-break de-hyphenation: "sepa- rately" -> "separately" (display only).
_HYPH = re.compile(r"([A-Za-z])-\s+([a-z])")


def _norm(s: str) -> str:
    return _WS.sub(" ", s).strip()


def _dehyphenate(s: str) -> str:
    """Clean OCR column line-breaks for the DISPLAY text (front/answer).

    The ``source_passage`` stays verbatim so grounding still matches; only the
    rendered cloze/answer are cleaned so cards read professionally.
    """
    return _WS.sub(" ", _HYPH.sub(r"\1\2", s)).strip()


def _pages(cfg: RunConfig, source_id: str) -> list[tuple[str, str]]:
    """(locator, page_text) for each ingest row of a source."""
    path = cfg.stage_dir("00-ingest") / f"{source_id}.jsonl"
    if not path.exists():
        return []
    return [(r.get("locator", "whole"), r.get("text", "")) for r in read_jsonl(path)]


# ---------------------------------------------------------------------------
# NIST SP 800-53 controls (block-aware: ID / NAME / Control: / a. <stmt>)
# ---------------------------------------------------------------------------
# The catalog renders each base control as three lines then the first item,
# with the statement wrapping across line breaks -- so a single-line regex only
# caught the few short ones. This block regex spans the wrap and stops at the
# next lettered item / Discussion / Related Controls.
_NIST_BLOCK = re.compile(
    r"(?m)^([A-Z]{2}-\d{1,2})\s*\n"
    r"([A-Z][A-Z0-9 ,/&()'\-]{3,70})\s*\n"
    r"Control:\s*\n?\s*a\.\s*(.+?)"
    r"(?=\n\s*[b-z]\.\s|\n\s*Discussion:|\n\s*Related Controls:|\n\s*References:|\Z)",
    re.DOTALL,
)
_NIST_STMT_MAX = 220


def harvest_nist(cfg: RunConfig) -> list[dict]:
    rows: list[dict] = []
    seen: set[str] = set()
    for locator, text in _pages(cfg, "nist_800_53"):
        norm_page = _norm(text).lower()
        for cid, name, stmt in _NIST_BLOCK.findall(text):
            cid = cid.strip()
            # Skip the "-1 POLICY AND PROCEDURES" boilerplate: it repeats almost
            # verbatim across every family, so redacted exhibits collide.
            if cid in seen or cid.endswith("-1"):
                continue
            name = _norm(name)
            stmt = _norm(stmt)
            if len(stmt) < 20 or "12-10-2020" in stmt or "Editorial" in name:
                continue
            if len(stmt) > _NIST_STMT_MAX:
                # Truncate at a word boundary WITHOUT an ellipsis so the passage
                # stays a verbatim (prefix) substring of the source page.
                stmt = stmt[:_NIST_STMT_MAX].rsplit(" ", 1)[0]
            passage = _norm(f"{cid} {name} Control: a. {stmt}")
            if passage.lower() not in norm_page:
                continue
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
# AU-C references (broadened: citation with or without parentheses)
# ---------------------------------------------------------------------------
_AUC_SENT = re.compile(r"([A-Z][^.]{40,240}?\(?AU-C\s*(\d{3})\)?[^.]{0,40}\.)")


def harvest_auc(cfg: RunConfig, per_id: int = 4) -> list[dict]:
    rows: list[dict] = []
    counts: dict[str, int] = {}
    seen: set[str] = set()
    for locator, text in _pages(cfg, "cpa_aud_review"):
        norm_page = _norm(text).lower()
        for sent, num in _AUC_SENT.findall(text):
            sent = _norm(sent)
            key = sent.lower()
            if len(sent) > 240 or counts.get(num, 0) >= per_id or key in seen:
                continue
            if sent.lower() not in norm_page:
                continue
            counts[num] = counts.get(num, 0) + 1
            seen.add(key)
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
# IRS dollar-threshold cloze (precision-tuned)
# ---------------------------------------------------------------------------
_MONEY = re.compile(r"\$[\d,]{3,}(?:\.\d+)?")
# Candidate sentences: start with a capital, contain >=1 dollar amount, end at ".".
_SENT = re.compile(r"([A-Z][^.]{25,230}?\$[\d,]{3,}[^.]{0,120}?\.)")

# --- keep signals -----------------------------------------------------------
_THRESHOLD = re.compile(
    r"\b(maximum|minimum|up to|no more than|not more than|more than|less than|"
    r"at least|or more|or less|in excess of|over|under|exceed\w*|limit\w*|"
    r"cannot exceed|can'?t exceed|threshold|phase[ -]?out|reduced by|"
    r"increased to|has increased|subject to|must file|allowance|"
    r"deduct up to|first \$)\b",
    re.IGNORECASE,
)
# Named provision so the blank is answerable by recall (bare "deduction"/"credit"
# are intentionally excluded -- too generic -> ambiguous cards).
_PROVISION = re.compile(
    r"\b(section\s*\d+|\d+\(k\)|\d+\(b\)|401\(k\)|403\(b\)|IRA|Roth|HSA|"
    r"Thrift Savings|self[- ]?employ\w*|social security|medicare|"
    r"railroad retirement|adoption (?:credit|benefit)|standard deduction|"
    r"child tax credit|earned income credit|dependent care|premium tax credit|"
    r"estimated tax|capital loss deduction|catch[- ]?up contribution|"
    r"elective deferral|salary reduction|section 179|bonus depreciation|"
    r"standard mileage|gift tax|estate tax|excise tax|\btips\b|overtime|"
    r"net earnings|net investment income|passenger vehicle|clean vehicle|"
    r"charitable contribution|home mortgage|student loan interest|tuition|"
    r"special allowance|passive activity|foreign earned income|cash payment|"
    r"Form \d+|below-market loan|de minimis|sound recording|"
    r"qualified business income|QBI|American opportunity|lifetime learning|"
    r"saver'?s credit)\b",
    re.IGNORECASE,
)
# Topic label = the specific provision matched (nicer tags/decks).
_TOPIC = re.compile(
    r"\b(section\s*\d+|401\(k\)|403\(b\)|IRA|Roth|HSA|self[- ]?employment|"
    r"social security|medicare|adoption|standard deduction|child tax credit|"
    r"earned income credit|estimated tax|catch[- ]?up|section 179|"
    r"bonus depreciation|standard mileage|gift tax|estate tax|excise tax|tips|"
    r"overtime|net investment income|passenger vehicle|charitable|"
    r"home mortgage|student loan|tuition|special allowance|passive activity|"
    r"foreign earned income|American opportunity|lifetime learning|saver'?s)\b",
    re.IGNORECASE,
)

# --- reject signals ---------------------------------------------------------
_ANAPHORA = re.compile(r"^(this|that|these|those|it)\b", re.IGNORECASE)
_GENERIC_SUBJ = re.compile(
    r"^(the amount|the amounts|the maximum (?:amount|deduction|credit|is)|"
    r"the deduction|the credit is|the limit is|the total|"
    r"your deduction|your credit|agi is|magi (?:is|over|of)|your magi)\b",
    re.IGNORECASE,
)
# Proper-name possessive ("Reid's", "Chin Ho's") — handles straight AND curly '.
_NAME_POSS = re.compile(r"\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?['\u2019]s\b")
_NAME_VERB = re.compile(
    r"\b(?!You|Your|The|This|That|These|Those|If|For|When|While|Married|Single|"
    r"Head|Qualifying|Report|File|Form|Beginning|Gift|Also|However)"
    r"[A-Z][a-z]{2,}\s+(paid|received|sold|bought|earned|owes?|owns?|gave|made|"
    r"invested|deposited|contributed|borrowed|was awarded)\b"
)
# Personal actor performing a specific transaction -> worked example, not a rule.
_ACTOR = re.compile(
    r"\b(the |your |their |his |her )?"
    r"(parent|parents|child|children|taxpayer|employee|partner|shareholder|"
    r"beneficiary|spouse|student|son|daughter|grandchild)s?\s+"
    r"(receives?|received|contributed|contributes?|spends?|spent|gets?|got|"
    r"paid|pays?|earned|earns?|owns?|sold|bought|enters?|entered|figures?)\b",
    re.IGNORECASE,
)
_NARRATIVE = re.compile(
    r"\b(inherited|assumed|awarded|borrowed|a cost of|cost basis|"
    r"adjusted basis (?:of|in|is|was)|realized gain|recognized gain|"
    r"fair market value|\bFMV\b|sale price|selling price|proceeds|results in|"
    r"offsets?|leaving a net|net capital (?:gain|loss) (?:of|for)|"
    r"received a refund|claimed (?:an?|the)[^.]{0,30}of \$|"
    r"expenses of \$[\d,]+ over|paid \$[\d,]+ down|entered into|"
    r"\bgets? \$|\bgot \$|is entitled to|is to receive|distributed to you)\b",
    re.IGNORECASE,
)
# Two-word Title Case name as an example subject: "Paul Lamb, a ..." / "Divya is".
_FULLNAME = re.compile(
    r"\b(?!New York|United States|Social Security|Thrift Savings|Roth IRA)"
    r"[A-Z][a-z]+\s+[A-Z][a-z]+,\s+a\b"
)
_EXAMPLE = re.compile(r"\b(for example|for instance|example|assume|suppose)\b", re.IGNORECASE)
# Specific calendar date (month + day) -> a scenario instance, not a standing rule.
_DATE = re.compile(
    r"\b(January|February|March|April|May|June|July|August|September|October|"
    r"November|December)\s+\d{1,2}\b",
    re.IGNORECASE,
)
# Worksheet / line-entry mechanics -> not a recall-able rule.
_WORKSHEET = re.compile(r"\b(on line \d|line \d+[a-z]?\b|you enter|enter \$|you figure)\b", re.IGNORECASE)
_FOR_AMT = re.compile(
    r"\b(sold|bought|purchased|paid|entered into)\b[^.]{0,40}\bfor \$[\d,]+|paid \$[\d,]+ for\b",
    re.IGNORECASE,
)
_PAST_INCOME = re.compile(r"\b(earned|unearned|gross|taxable) income (?:was|were)\b", re.IGNORECASE)
_FORMULA = re.compile(
    r"[=\u00d7\u00f7]|\u2212|\$[\d,]+\s*[-+\u2013\u2014]\s*\$|"
    r"\b(minus|plus|divided by|equals)\b"
)


def _cloze_ok(sp: str) -> bool:
    """Precision gate: keep source-grounded RULE/THRESHOLD statements, reject
    worked examples, proper-name narratives, formulas, tables, and anaphoric
    fragments. Tuned to ~90% recall / ~11% leakage on the prior judge labels."""
    if not (1 <= len(_MONEY.findall(sp)) <= 3):
        return False
    if len(sp) < 28 or len(sp) > 250:
        return False
    if _NAME_POSS.search(sp) or _NAME_VERB.search(sp) or _ACTOR.search(sp) or _FULLNAME.search(sp):
        return False
    if _NARRATIVE.search(sp) or _EXAMPLE.search(sp) or _FOR_AMT.search(sp):
        return False
    if _DATE.search(sp) or _WORKSHEET.search(sp):
        return False
    if _PAST_INCOME.search(sp) or _FORMULA.search(sp) or sp.count("\u2022") >= 2:
        return False
    if _GENERIC_SUBJ.match(sp):
        return False
    has_prov = bool(_PROVISION.search(sp))
    has_thr = bool(_THRESHOLD.search(sp))
    if _ANAPHORA.match(sp) and not (has_prov and has_thr):
        return False
    return has_prov or has_thr


def _blank(sentence: str) -> tuple[str, list[str]]:
    """Blank every dollar amount left-to-right; return (cloze, [answers])."""
    answers: list[str] = []

    def repl(m: re.Match) -> str:
        answers.append(m.group(0))
        return "_____"

    return _MONEY.sub(repl, sentence), answers


def _topic_of(sp: str, default: str) -> str:
    m = _TOPIC.search(sp)
    return m.group(1).lower() if m else default


def harvest_irs_cloze(cfg: RunConfig, cap_per_source: int = 120) -> list[dict]:
    rows: list[dict] = []
    seen_cloze: set[str] = set()
    for source_id, section in IRS_SECTION.items():
        n = 0
        for locator, text in _pages(cfg, source_id):
            if n >= cap_per_source:
                break
            norm_page = _norm(text).lower()
            for raw in _SENT.findall(text):
                if n >= cap_per_source:
                    break
                sp_raw = _norm(raw)               # verbatim (for grounding)
                display = _dehyphenate(sp_raw)     # cleaned (for the card)
                if not _cloze_ok(display):
                    continue
                if sp_raw.lower() not in norm_page:
                    continue
                cloze, amounts = _blank(display)
                if not amounts:
                    continue
                dedup_key = _WS.sub(" ", cloze.lower())
                if dedup_key in seen_cloze:
                    continue
                seen_cloze.add(dedup_key)
                pub = PUB_NAMES.get(source_id, source_id)
                rows.append({
                    "row_id": f"{source_id}_{locator}_{n}",
                    "section": section,
                    "topic": _topic_of(display, "individual and entity thresholds"),
                    "cloze": cloze,
                    "answer": ", ".join(amounts),
                    "display_citation": f"{pub} ({locator})",
                    "source_id": source_id,
                    "locator": locator,
                    "source_passage": sp_raw,
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
    ap.add_argument("--run-id", default="tmpl4")
    ap.add_argument("--irs-cap", type=int, default=120, help="max cloze rows per IRS source")
    ap.add_argument("--auc-cap", type=int, default=4, help="max sentences per AU-C section")
    args = ap.parse_args(argv)
    cfg = RunConfig(run_id=args.run_id)

    _write(cfg, "nist_controls.yaml", "ISC", harvest_nist(cfg))
    _write(cfg, "auc_citations.yaml", "AUD", harvest_auc(cfg, args.auc_cap))
    _write(cfg, "irs_cloze.yaml", "REG", harvest_irs_cloze(cfg, args.irs_cap))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
