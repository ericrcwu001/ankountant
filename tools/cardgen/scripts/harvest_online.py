#!/usr/bin/env python3
"""Ingest third-party CPA decks downloaded from AnkiWeb into a quality-filtered,
de-duplicated set of "online-sourced" cards.

Reads every ``.apkg`` in ``tools/cardgen/inbox/`` (put there by
``scripts/fetch_ankiweb.mjs`` or by hand), parses the embedded Anki collection,
normalizes each note to a Basic/Cloze card, drops junk (empty / media-only /
non-English / off-topic / too-short / too-long), then de-duplicates the survivors
both against each other AND against the AI/template bank already shipped
(``out/<run_id>/09-dedup/kept.jsonl``) — reusing the same embedding + shingle
near-duplicate clustering the pipeline uses internally.

These cards are NOT grounded in our corpus (no verbatim ``source_passage``), so
they deliberately bypass the grounded self-check/judge gates; provenance is the
source deck (``src::ankiweb`` + ``src::ankiweb::<deck_id>`` tags, and a
``Ankountant::Community::<deck>`` deck on emit). Use ``--triage`` +
``triage_online.py`` for an optional LLM usefulness pass.

Writes under ``out/online/``:
- ``kept.jsonl``    — one row per surviving online card (fed to emit_online.py)
- ``dropped.jsonl`` — drop reasons (audit trail)
- ``report.md``     — per-source + per-reason summary

Usage:
    uv run python scripts/harvest_online.py --run-id tmpl4 \
        [--per-deck-cap 60] [--global-cap 400]
"""

from __future__ import annotations

import argparse
import html as _html
import json
import re
import sqlite3
import sys
import tempfile
import zipfile
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from cardgen.config import ROOT, RunConfig  # noqa: E402
from cardgen.dedup import near_duplicate_clusters  # noqa: E402
from cardgen.leakage import salient_text as _ai_salient  # noqa: E402
from cardgen.models import read_jsonl, write_jsonl  # noqa: E402
from cardgen.providers.base import get_embedder  # noqa: E402
from cardgen.util import content_hash, normalize_text  # noqa: E402

INBOX = ROOT / "inbox"
OUT_DIR = ROOT / "out" / "online"

_FIELD_SEP = "\x1f"

# --- text cleaning ---------------------------------------------------------
_SOUND = re.compile(r"\[sound:[^\]]*\]", re.IGNORECASE)
_ANKI_DIRECTIVE = re.compile(r"\[\[?(?:type|anki):[^\]]*\]\]?", re.IGNORECASE)
_TAG = re.compile(r"<[^>]+>")
_CLOZE = re.compile(r"\{\{c\d+::(.*?)(?:::.*?)?\}\}", re.DOTALL)
_HAS_CLOZE = re.compile(r"\{\{c\d+::")
_IMG = re.compile(r"<img\b", re.IGNORECASE)
_CJK = re.compile(r"[\u3000-\u9fff\uac00-\ud7a3\uf900-\ufaff\uff00-\uffef]")

# Display cleanup: drop presentational noise (inline styles, span/font wrappers,
# editor attributes) but keep structural tags (b/u/i/br/ul/li/div/table) so
# journal-entry tables etc. still render. Cloze markup ({{c1::...}}) is preserved.
_STYLE_ATTR = re.compile(r'\s+(?:style|class|id|dir|face|color|data-[\w-]+)="[^"]*"', re.IGNORECASE)
_WRAP_TAG = re.compile(r"</?(?:span|font)\b[^>]*>", re.IGNORECASE)


def _strip_html(s: str) -> str:
    s = _SOUND.sub(" ", s or "")
    s = _ANKI_DIRECTIVE.sub(" ", s)
    s = s.replace("<br>", " ").replace("<br/>", " ").replace("<br />", " ")
    s = _TAG.sub(" ", s)
    s = _html.unescape(s)
    return normalize_text(s)


def _clean_display(s: str) -> str:
    """Cleaned HTML kept for the emitted card (Anki renders it)."""
    s = _SOUND.sub(" ", s or "")
    s = _ANKI_DIRECTIVE.sub(" ", s)
    s = _WRAP_TAG.sub("", s)
    s = _STYLE_ATTR.sub("", s)
    s = s.replace("\xa0", " ").replace("&nbsp;", " ")
    return normalize_text(s)


def _plaintext(s: str) -> str:
    """Human-readable text with cloze answers inlined (for dedup/relevance)."""
    return _strip_html(_CLOZE.sub(r"\1", s or ""))


def _cjk_ratio(s: str) -> float:
    letters = [c for c in s if c.isalpha()]
    if not letters:
        return 0.0
    return sum(1 for c in letters if _CJK.match(c)) / len(letters)


# --- relevance -------------------------------------------------------------
# Broad accounting / audit / tax / business-law vocabulary. A card is kept only
# if its text (or its deck title) hits at least one — cheap guard against decks
# that merely mention "CPA" but are off-topic (languages, medicine, etc.).
_RELEVANCE = re.compile(
    r"\b(account\w*|audit\w*|assur\w*|tax\w*|asset|liabilit\w*|equity|revenue|"
    r"expense|deprecia\w*|amorti\w*|ledger|journal|debit|credit|gaap|ifrs|fasb|"
    r"gasb|pcaob|sec\b|aicpa|materialit\w*|internal control|cash flow|inventor\w*|"
    r"deferred|accru\w*|balance sheet|income statement|partnership|corporat\w*|"
    r"deduction|capital|dividend|goodwill|lease|bond|receivable|payable|"
    r"depletion|amortization|fiduciar\w*|estate|gift tax|s corp|c corp|llc|"
    r"basis|gain|loss|contribution|distribution|shareholder|retained earnings|"
    r"cpa|far\b|reg\b|aud\b|bec\b|isc\b|tcp\b|bar\b|financial reporting|"
    r"governmental|nonprofit|consolidat\w*|hedge|derivative|impairment|"
    r"disclosure|going concern|substantive|sampling|fraud|control)\b",
    re.IGNORECASE,
)


def _relevance_score(text: str, title: str) -> int:
    return len(_RELEVANCE.findall(f"{text} {title}"))


# --- CPA section category --------------------------------------------------
# Every scraped card is categorized into a CPA exam section (matching the AI
# bank's FAR/AUD/REG/TCP/ISC/BAR organization) via keyword scoring, with the
# source deck's title as a strong prior and a final "GENERAL" fallback.
_SECTION_KEYWORDS: dict[str, list[str]] = {
    "FAR": [
        r"financial statement", r"balance sheet", r"income statement", r"cash flow",
        r"deferred tax", r"\blease", r"lessee", r"lessor", r"\bbond", r"consolidat",
        r"goodwill", r"impairment", r"pension", r"revenue recognition", r"inventor",
        r"deprecia", r"amorti", r"equity method", r"journal entry", r"\bgaap\b",
        r"\bifrs\b", r"fair value", r"governmental", r"fund accounting", r"nonprofit",
        r"comprehensive income", r"retained earnings", r"accru", r"deferred",
    ],
    "AUD": [
        r"\baudit", r"assur", r"internal control", r"materialit", r"sampling",
        r"audit evidence", r"opinion", r"going concern", r"pcaob", r"independen",
        r"risk assessment", r"substantive", r"attestation", r"engagement",
        r"auditor", r"misstatement", r"\bfraud", r"assertion",
    ],
    "REG": [
        r"\btax", r"gross income", r"deduction", r"\birs\b", r"adjusted basis",
        r"capital gain", r"partnership", r"s corp", r"c corp", r"estate", r"gift tax",
        r"recapture", r"ethics", r"business law", r"contract", r"agency", r"\bucc\b",
        r"negligence", r"circular 230",
    ],
    "TCP": [
        r"tax planning", r"tax compliance", r"estimated tax", r"\bamt\b",
        r"passive activity", r"like-kind", r"installment sale", r"net investment income",
        r"\bqbi\b", r"self-employ",
    ],
    "ISC": [
        r"information system", r"\bsoc [12]\b", r"cybersecurit", r"\bnist\b",
        r"access control", r"it general control", r"data governance", r"\bsdlc\b",
        r"encrypt", r"firewall", r"\bnetwork\b",
    ],
    "BAR": [
        r"variance", r"manageri", r"cost accounting", r"ratio analysis", r"\bbudget",
        r"forecast", r"contribution margin", r"break-even", r"working capital",
    ],
}
_SECTION_RE = {sec: re.compile("|".join(kw), re.IGNORECASE) for sec, kw in _SECTION_KEYWORDS.items()}
_SECTION_TOKEN = re.compile(r"\b(FAR|AUD|REG|TCP|ISC|BAR|BEC)\b")
# Old BEC content was split across BAR/ISC/TCP; default it to BAR.
_TOKEN_MAP = {"FAR": "FAR", "AUD": "AUD", "REG": "REG", "TCP": "TCP", "ISC": "ISC", "BAR": "BAR", "BEC": "BAR"}


def _deck_section(title: str) -> str:
    """Best section for a whole deck, from its title (an explicit FAR/AUD/... token,
    else an audit/financial/tax keyword)."""
    m = _SECTION_TOKEN.search(title or "")
    if m:
        return _TOKEN_MAP[m.group(1)]
    t = (title or "").lower()
    if "audit" in t or "assur" in t:
        return "AUD"
    if "financial" in t or "accounting" in t:
        return "FAR"
    if "tax" in t or "regulation" in t:
        return "REG"
    best, score = "", 0
    for sec, rx in _SECTION_RE.items():
        n = len(rx.findall(title or ""))
        if n > score:
            best, score = sec, n
    return best or "GENERAL"


def _classify_section(text: str, title: str, deck_section: str) -> str:
    """Per-card section: keyword winner in the card text, else the deck's section."""
    best, score = "", 0
    for sec, rx in _SECTION_RE.items():
        n = len(rx.findall(text))
        if n > score:
            best, score = sec, n
    if score >= 2:  # a confident card-level signal overrides the deck prior
        return best
    return deck_section if deck_section != "GENERAL" else (best or "GENERAL")


# --- apkg parsing ----------------------------------------------------------
def _open_collection(apkg: Path, workdir: Path) -> sqlite3.Connection | None:
    """Extract the newest readable collection db from an .apkg and open it.

    Handles legacy ``collection.anki2``/``anki21`` (plain sqlite) and, when the
    optional ``zstandard`` package is present, the newer zstd ``collection.anki21b``.
    """
    try:
        z = zipfile.ZipFile(apkg)
    except zipfile.BadZipFile:
        return None
    names = set(z.namelist())
    with z:
        # Prefer newest schema available.
        if "collection.anki21b" in names:
            try:
                import zstandard  # type: ignore
            except Exception:
                # Fall through to a legacy db if the pack also ships one.
                zstandard = None  # type: ignore
            if zstandard is not None:
                raw = z.read("collection.anki21b")
                dbp = workdir / "collection.anki2"
                dbp.write_bytes(zstandard.ZstdDecompressor().decompress(raw, max_output_size=1 << 30))
                return sqlite3.connect(dbp)
        for member in ("collection.anki21", "collection.anki2"):
            if member in names:
                z.extract(member, workdir)
                return sqlite3.connect(workdir / member)
    return None


def _models(conn: sqlite3.Connection) -> dict[int, dict]:
    """mid -> {name, type, field_names}. Legacy ``col.models`` JSON, else the
    newer ``notetypes``/``fields`` tables."""
    try:
        (blob,) = conn.execute("SELECT models FROM col").fetchone()
        raw = json.loads(blob) if blob else {}
        if raw:
            return {
                int(mid): {
                    "name": m.get("name", ""),
                    "type": int(m.get("type", 0)),
                    "field_names": [f["name"] for f in sorted(m.get("flds", []), key=lambda f: f.get("ord", 0))],
                }
                for mid, m in raw.items()
            }
    except Exception:
        pass
    out: dict[int, dict] = {}
    try:
        fields: dict[int, list[tuple[int, str]]] = {}
        for ntid, ord_, name in conn.execute("SELECT ntid, ord, name FROM fields"):
            fields.setdefault(int(ntid), []).append((ord_, name))
        for ntid, name in conn.execute("SELECT id, name FROM notetypes"):
            flds = [n for _, n in sorted(fields.get(int(ntid), []))]
            out[int(ntid)] = {"name": name, "type": 0, "field_names": flds}
    except Exception:
        pass
    return out


def _note_to_card(fields: list[str], model: dict) -> tuple[bool, str, str] | None:
    """(is_cloze, front, back) from a note's raw fields, or None if unusable."""
    vals = [f for f in fields]
    if not vals:
        return None
    # Only a real ``{{c1::...}}`` marker makes a cloze card; a cloze *note type*
    # with no deletion would emit an invalid (blank) cloze, so treat it as basic.
    is_cloze = any(_HAS_CLOZE.search(v) for v in vals)
    names = model.get("field_names") or []
    if is_cloze:
        # Front = the field carrying the cloze markup (prefer one literally
        # named Text, else the first field that has a cloze); back = the rest.
        idx = next((i for i, v in enumerate(vals) if _HAS_CLOZE.search(v)), 0)
        if names:
            named = next((i for i, n in enumerate(names) if n.strip().lower() == "text"), None)
            if named is not None and named < len(vals) and _HAS_CLOZE.search(vals[named]):
                idx = named
        front = vals[idx]
        back = " ".join(v for i, v in enumerate(vals) if i != idx and v.strip())
        return is_cloze, front, back
    front = vals[0]
    back = " ".join(v for v in vals[1:] if v.strip())
    return is_cloze, front, back


# --- filtering -------------------------------------------------------------
def _quality_ok(front_txt: str, back_txt: str, is_cloze: bool, raw_front: str, min_len: int, max_len: int) -> tuple[bool, str]:
    combined = f"{front_txt} {back_txt}".strip()
    if not front_txt:
        return False, "empty_front"
    if not is_cloze and not back_txt:
        return False, "empty_back"
    if _IMG.search(raw_front) and len(combined) < 12:
        return False, "media_only"
    n = len(combined)
    if n < min_len:
        return False, "too_short"
    if n > max_len:
        return False, "too_long"
    if _cjk_ratio(combined) > 0.15:
        return False, "non_english"
    if front_txt.isupper() and not back_txt:
        return False, "heading_only"
    return True, ""


def harvest_deck(apkg: Path, title: str, per_deck_cap: int, min_len: int, max_len: int) -> tuple[list[dict], Counter]:
    deck_id = apkg.stem
    deck_section = _deck_section(title)
    reasons: Counter = Counter()
    rows: list[dict] = []
    seen_norm: set[str] = set()
    with tempfile.TemporaryDirectory() as td:
        conn = _open_collection(apkg, Path(td))
        if conn is None:
            reasons["unreadable_apkg"] += 1
            return rows, reasons
        try:
            models = _models(conn)
            cur = conn.execute("SELECT mid, flds, tags FROM notes")
            for mid, flds, ntags in cur:
                model = models.get(int(mid), {"type": 0, "field_names": []})
                card = _note_to_card((flds or "").split(_FIELD_SEP), model)
                if card is None:
                    reasons["no_fields"] += 1
                    continue
                is_cloze, raw_front, raw_back = card
                front_txt = _plaintext(raw_front)
                back_txt = _plaintext(raw_back)
                ok, why = _quality_ok(front_txt, back_txt, is_cloze, raw_front, min_len, max_len)
                if not ok:
                    reasons[why] += 1
                    continue
                text = f"{front_txt} {back_txt}".strip()
                if _relevance_score(text, title) == 0:
                    reasons["off_topic"] += 1
                    continue
                norm = normalize_text(text).lower()
                if norm in seen_norm:
                    reasons["dup_in_deck"] += 1
                    continue
                seen_norm.add(norm)
                section = _classify_section(text, title, deck_section)
                rows.append(
                    {
                        "item_id": f"aw-{content_hash(deck_id, norm)}",
                        "source": "ankiweb",
                        "source_deck_id": deck_id,
                        "source_title": title,
                        "section": section,
                        "is_cloze": is_cloze,
                        "front": _clean_display(raw_front),
                        "back": _clean_display(raw_back),
                        "text": text,
                        "relevance": _relevance_score(text, title),
                        "tags": ["src::ankiweb", f"src::ankiweb::{deck_id}", f"sec::{section}"],
                    }
                )
        finally:
            conn.close()
    rows.sort(key=lambda r: (-r["relevance"], r["item_id"]))
    if per_deck_cap and len(rows) > per_deck_cap:
        reasons["over_deck_cap"] += len(rows) - per_deck_cap
        rows = rows[:per_deck_cap]
    return rows, reasons


# --- dedup vs the shipped AI bank ------------------------------------------
def _dedup(online: list[dict], anchors: list[dict], cfg: RunConfig) -> tuple[list[dict], list[dict]]:
    """Drop online cards that duplicate each other or any shipped AI card."""
    if not online:
        return [], []
    online_texts = [r["text"] for r in online]
    anchor_texts = [_ai_salient(a) for a in anchors]
    anchor_texts = [t for t in anchor_texts if t]

    texts = online_texts + anchor_texts
    origins = ["online"] * len(online_texts) + ["ai"] * len(anchor_texts)
    embs = get_embedder(cfg).embed(texts)
    clusters = near_duplicate_clusters(texts, embs, cfg.dedup_threshold)

    kept: list[dict] = []
    dropped: list[dict] = []
    for members in clusters:
        online_members = [i for i in members if origins[i] == "online"]
        if not online_members:
            continue
        has_ai = any(origins[i] == "ai" for i in members)
        if has_ai:
            for i in online_members:
                dropped.append({"item_id": online[i]["item_id"], "reason": "dup_of_ai_bank"})
            continue
        rep = min(online_members)  # stable representative
        kept.append(online[rep])
        for i in online_members:
            if i != rep:
                dropped.append(
                    {"item_id": online[i]["item_id"], "reason": "dup_online", "matched_ref": online[rep]["item_id"]}
                )
    kept.sort(key=lambda r: (-r["relevance"], r["item_id"]))
    return kept, dropped


def _write_report(path: Path, kept: list[dict], drop_reasons: Counter, per_source: Counter, dedup_dropped: list[dict]) -> None:
    lines = ["# Online (AnkiWeb) harvest report", ""]
    lines.append(f"- kept: **{len(kept)}** cards from {len(per_source)} source deck(s)")
    lines.append(f"- cloze: {sum(1 for r in kept if r['is_cloze'])} | basic: {sum(1 for r in kept if not r['is_cloze'])}")
    dd = Counter(d["reason"] for d in dedup_dropped)
    by_section = Counter(r.get("section", "GENERAL") for r in kept)
    lines += ["", "## Kept by category (CPA section)", ""]
    for sec, n in by_section.most_common():
        lines.append(f"- {n}: {sec}")
    lines += ["", "## Kept by source deck", ""]
    for src, n in per_source.most_common():
        lines.append(f"- {n}: {src}")
    lines += ["", "## Dropped (quality/relevance filter)", ""]
    for reason, n in drop_reasons.most_common():
        lines.append(f"- {n}: {reason}")
    lines += ["", "## Dropped (dedup)", ""]
    for reason, n in dd.most_common():
        lines.append(f"- {n}: {reason}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description="Ingest AnkiWeb CPA decks -> filtered, deduped online card set.")
    ap.add_argument("--run-id", default="tmpl4", help="AI bank run to dedup against (out/<run_id>/09-dedup/kept.jsonl)")
    ap.add_argument("--inbox", default=str(INBOX), help="Folder of downloaded .apkg files")
    ap.add_argument("--per-deck-cap", type=int, default=60)
    ap.add_argument("--global-cap", type=int, default=400)
    ap.add_argument("--min-len", type=int, default=8)
    ap.add_argument("--max-len", type=int, default=600)
    args = ap.parse_args()

    cfg = RunConfig(run_id=args.run_id)
    inbox = Path(args.inbox)
    apkgs = sorted(inbox.glob("*.apkg"))
    # Deck titles come from the fetcher's manifest.json (downloaded decks) and/or
    # shortlist.json (all enumerated decks); either may be absent.
    titles: dict[str, str] = {}
    for meta_name in ("shortlist.json", "manifest.json"):
        meta = inbox / meta_name
        if not meta.exists():
            continue
        try:
            for m in json.loads(meta.read_text()):
                t = (m.get("title") or "").strip()
                if t:
                    titles[str(m.get("id"))] = t
        except Exception:
            pass

    if not apkgs:
        print(f"[online] no .apkg files in {inbox} — run scripts/fetch_ankiweb.mjs or drop decks there.")
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        write_jsonl(OUT_DIR / "kept.jsonl", [])
        write_jsonl(OUT_DIR / "dropped.jsonl", [])
        return

    all_rows: list[dict] = []
    drop_reasons: Counter = Counter()
    per_source: Counter = Counter()
    for apkg in apkgs:
        title = titles.get(apkg.stem, apkg.stem)
        rows, reasons = harvest_deck(apkg, title, args.per_deck_cap, args.min_len, args.max_len)
        drop_reasons.update(reasons)
        if rows:
            per_source[title] += len(rows)
            all_rows.extend(rows)
        print(f"[online] {apkg.name}: {len(rows)} kept ({title[:48]})")

    # Global pre-cap by relevance before the O(n^2) dedup keeps it tractable.
    all_rows.sort(key=lambda r: (-r["relevance"], r["item_id"]))
    precap = max(args.global_cap * 2, 600)
    if len(all_rows) > precap:
        drop_reasons["over_global_precap"] += len(all_rows) - precap
        all_rows = all_rows[:precap]

    anchors = list(read_jsonl(cfg.stage_dir("09-dedup") / "kept.jsonl"))
    kept, dedup_dropped = _dedup(all_rows, anchors, cfg)

    if args.global_cap and len(kept) > args.global_cap:
        for r in kept[args.global_cap:]:
            dedup_dropped.append({"item_id": r["item_id"], "reason": "over_global_cap"})
        kept = kept[: args.global_cap]

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_jsonl(OUT_DIR / "kept.jsonl", kept)
    write_jsonl(OUT_DIR / "dropped.jsonl", dedup_dropped)
    kept_by_source = Counter(r["source_title"] for r in kept)
    _write_report(OUT_DIR / "report.md", kept, drop_reasons, kept_by_source, dedup_dropped)

    print(
        f"[online] {len(apkgs)} decks -> {len(all_rows)} candidates -> {len(kept)} kept "
        f"({sum(1 for r in kept if r['is_cloze'])} cloze, {sum(1 for r in kept if not r['is_cloze'])} basic); "
        f"dedup dropped {len(dedup_dropped)}. -> {OUT_DIR}/kept.jsonl"
    )


if __name__ == "__main__":
    main()
