#!/usr/bin/env python3
"""Corpus discovery + registration for the RAG card generator (Stage 0).

Fetches **Tier-A public** sources (public-domain U.S. government + openly-licensed
OER) over HTTP and registers each via
:func:`cardgen.ingest.register_source`, which snapshots the file under
``corpus/<source_id>/`` and records a license-bearing manifest entry. Then
(optionally) re-ingests + re-indexes so retrieval picks the new corpus up.

Every source is best-effort: a failed download is logged as a **shortfall** and
skipped (never fabricated), matching the pipeline's honest-coverage posture.

Tier-B (copyrighted review texts / standards) is allowed for this personal-use
build per ADR 0009 but is **agent/MCP-driven**, not fetched here: drive
``annas-mcp`` (``book_search`` -> ``book_download`` with ``ANNAS_SECRET_KEY`` +
``ANNAS_DOWNLOAD_PATH``) or ``paper-search-mcp`` from a Cursor session, then run
this script with ``--register-local <file> --source-id ... --section ...
--tier B --license "personal-use"`` to fold the download into the manifest.

Usage
-----
    # list the built-in Tier-A catalog
    uv run python scripts/fetch_corpus.py --list
    # fetch all reachable Tier-A sources, then re-ingest + re-index (offline)
    uv run python scripts/fetch_corpus.py --reindex
    # only some sections
    uv run python scripts/fetch_corpus.py --sections FAR,REG,ISC --reindex
    # register a file obtained out-of-band (e.g. via annas-mcp) as Tier-B
    uv run python scripts/fetch_corpus.py --register-local ~/book.pdf \
        --source-id cpa_review_far --title "CPA Review (FAR)" --section FAR \
        --tier B --license "personal-use (not redistributed)"
"""

from __future__ import annotations

import argparse
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

# Make ``cardgen`` importable when run as a plain script (tools/cardgen/scripts/).
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from cardgen.config import SECTIONS, RunConfig  # noqa: E402
from cardgen import ingest  # noqa: E402

_UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120 Safari/537.36"
)
_MAX_BYTES = 80 * 1024 * 1024  # per-source safety cap

# Curated Tier-A public sources. `url` is a direct download; `ext` picks the
# ingest parser (.pdf via pymupdf, .txt whole-doc, .md/.html heading-split).
# License notes: U.S. Government works are public domain; OpenStax is CC BY-NC-SA
# 4.0 (attribution retained in the manifest; personal-use, not redistributed).
TIER_A_SOURCES: list[dict] = [
    # --- REG / TCP: IRS publications (public domain) ---
    {
        "source_id": "irs_p17",
        "title": "IRS Pub 17 — Your Federal Income Tax",
        "section": "REG",
        "url": "https://www.irs.gov/pub/irs-pdf/p17.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p334",
        "title": "IRS Pub 334 — Tax Guide for Small Business",
        "section": "TCP",
        "url": "https://www.irs.gov/pub/irs-pdf/p334.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p946",
        "title": "IRS Pub 946 — How To Depreciate Property",
        "section": "REG",
        "url": "https://www.irs.gov/pub/irs-pdf/p946.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p542",
        "title": "IRS Pub 542 — Corporations",
        "section": "TCP",
        "url": "https://www.irs.gov/pub/irs-pdf/p542.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p535",
        "title": "IRS Pub 535 — Business Expenses",
        "section": "REG",
        "url": "https://www.irs.gov/pub/irs-pdf/p535.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    # --- REG: more IRS pubs + Circular 230 (public domain) ---
    {
        "source_id": "irs_pcir230",
        "title": "Treasury Circular 230 — Practice Before the IRS",
        "section": "REG",
        "url": "https://www.irs.gov/pub/irs-pdf/pcir230.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p505",
        "title": "IRS Pub 505 — Tax Withholding and Estimated Tax",
        "section": "REG",
        "url": "https://www.irs.gov/pub/irs-pdf/p505.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p970",
        "title": "IRS Pub 970 — Tax Benefits for Education",
        "section": "REG",
        "url": "https://www.irs.gov/pub/irs-pdf/p970.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p501",
        "title": "IRS Pub 501 — Dependents, Standard Deduction, and Filing Information",
        "section": "REG",
        "url": "https://www.irs.gov/pub/irs-pdf/p501.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    # --- TCP: entity + advanced individual IRS pubs (public domain) ---
    {
        "source_id": "irs_p541",
        "title": "IRS Pub 541 — Partnerships",
        "section": "TCP",
        "url": "https://www.irs.gov/pub/irs-pdf/p541.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p544",
        "title": "IRS Pub 544 — Sales and Other Dispositions of Assets",
        "section": "TCP",
        "url": "https://www.irs.gov/pub/irs-pdf/p544.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p550",
        "title": "IRS Pub 550 — Investment Income and Expenses",
        "section": "TCP",
        "url": "https://www.irs.gov/pub/irs-pdf/p550.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "irs_p551",
        "title": "IRS Pub 551 — Basis of Assets",
        "section": "TCP",
        "url": "https://www.irs.gov/pub/irs-pdf/p551.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    # --- ISC: NIST Special Publications (public domain) ---
    {
        "source_id": "nist_800_12",
        "title": "NIST SP 800-12r1 — An Introduction to Information Security",
        "section": "ISC",
        "url": "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-12r1.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "nist_800_100",
        "title": "NIST SP 800-100 — Information Security Handbook: A Guide for Managers",
        "section": "ISC",
        "url": "https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-100.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    {
        "source_id": "nist_800_53",
        "title": "NIST SP 800-53r5 — Security and Privacy Controls for Information Systems",
        "section": "ISC",
        "url": "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf",
        "ext": ".pdf",
        "license": "US-Govt public domain",
    },
    # --- FAR / BAR: OpenStax OER (CC BY-NC-SA 4.0), full text via Internet Archive ---
    {
        "source_id": "openstax_far_v1",
        "title": "OpenStax Principles of Accounting, Vol 1: Financial Accounting",
        "section": "FAR",
        "url": "https://archive.org/stream/FinancialAccounting_201906/FinancialAccounting-OP_VzAhRvu_djvu.txt",
        "ext": ".txt",
        "license": "CC BY-NC-SA 4.0 (OpenStax; personal-use)",
    },
    {
        "source_id": "openstax_bar_v2",
        "title": "OpenStax Principles of Accounting, Vol 2: Managerial Accounting",
        "section": "BAR",
        "url": "https://archive.org/download/managerial-accounting_202008/Managerial%20Accounting_djvu.txt",
        "ext": ".txt",
        "license": "CC BY-NC-SA 4.0 (OpenStax; personal-use)",
    },
]


def _download(url: str, dest: Path) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": _UA, "Referer": "https://www.google.com/"})
    total = 0
    with urllib.request.urlopen(req, timeout=60) as resp, dest.open("wb") as fh:  # noqa: S310
        while True:
            chunk = resp.read(1 << 16)
            if not chunk:
                break
            total += len(chunk)
            if total > _MAX_BYTES:
                raise ValueError(f"exceeded {_MAX_BYTES} byte cap")
            fh.write(chunk)
    return total


def fetch_source(cfg: RunConfig, src: dict, tmp: Path) -> bool:
    tmp_path = tmp / f"{src['source_id']}{src['ext']}"
    try:
        size = _download(src["url"], tmp_path)
    except (urllib.error.URLError, urllib.error.HTTPError, ValueError, TimeoutError, OSError) as exc:
        print(f"[fetch] SHORTFALL {src['source_id']} ({src['section']}): {type(exc).__name__}: {exc}")
        return False
    entry = ingest.register_source(
        cfg,
        tmp_path,
        source_id=src["source_id"],
        title=src["title"],
        tier=src.get("tier", "A"),
        license=src.get("license", ""),
        section=src["section"],
    )
    print(f"[fetch] OK {src['source_id']} ({src['section']}) {size / 1024:.0f} KiB -> {entry['path']}")
    return True


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser("fetch_corpus")
    ap.add_argument("--list", action="store_true", help="print the Tier-A catalog and exit")
    ap.add_argument("--sections", default=",".join(SECTIONS), help="comma list to include")
    ap.add_argument("--reindex", action="store_true", help="run ingest+chunk+index after fetching")
    ap.add_argument("--run-id", default="proof")
    # Register a file obtained out-of-band (e.g. Tier-B via annas-mcp).
    ap.add_argument("--register-local", default=None, help="path to a local file to register")
    ap.add_argument("--source-id", default=None)
    ap.add_argument("--title", default=None)
    ap.add_argument("--section", default="GENERAL")
    ap.add_argument("--tier", default="A")
    ap.add_argument("--license", default="")
    args = ap.parse_args(argv)

    want = {s.strip().upper() for s in args.sections.split(",") if s.strip()}

    if args.list:
        for s in TIER_A_SOURCES:
            print(f"{s['source_id']:>16}  {s['section']:<4}  {s['title']}")
        return 0

    # Offline is fine for register + reindex (offline embedder); a live key only
    # matters at generate/judge time.
    cfg = RunConfig(run_id=args.run_id)

    if args.register_local:
        if not (args.source_id and args.title):
            ap.error("--register-local requires --source-id and --title")
        entry = ingest.register_source(
            cfg,
            args.register_local,
            source_id=args.source_id,
            title=args.title,
            tier=args.tier,
            license=args.license,
            section=args.section,
        )
        print(f"[fetch] registered local {entry['source_id']} ({entry['section']}, tier {entry['tier']})")
    else:
        ok = 0
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            for src in TIER_A_SOURCES:
                if src["section"] not in want:
                    continue
                ok += fetch_source(cfg, src, tmp)
        total = sum(1 for s in TIER_A_SOURCES if s["section"] in want)
        print(f"[fetch] registered {ok}/{total} requested Tier-A source(s)")

    if args.reindex:
        from cardgen import chunk, index

        print("[fetch] re-ingesting + re-indexing…")
        ingest.run(cfg)
        chunk.run(cfg)
        index.run(cfg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
