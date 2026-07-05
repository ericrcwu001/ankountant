"""Stage 0 (snapshot/manifest) + Stage 1 (ingest & normalize).

Stage 0 lives in `register_source`: it copies a local source file into
`corpus/<source_id>/`, computes its sha256, and appends a license-bearing entry
to `corpus/manifest.json` (the root of the provenance chain).

Stage 1 lives in `run`: it reads the manifest and extracts clean, structurally
located text for each source:

- PDF (`.pdf`)      -> one row per page, locator ``p{n}`` (1-based).
- Markdown (`.md`)  -> one row per heading section, locator ``s{i}``.
- HTML (`.html`)    -> one row per heading section, locator ``s{i}``.
- Text (`.txt`/*)   -> a single whole-document row, locator ``whole``.

Empty pages/sections are skipped. Because *all* ingested text — even
public-domain — is an untrusted prompt-injection surface, obvious
"ignore previous instructions"-style lines are stripped here (and counted), per
doc 6's guardrails. We keep this conservative: only whole lines that clearly
match an override pattern are removed.

Output: ``00-ingest/<source_id>.jsonl`` rows ``{source_id, locator,
heading_path, text}``.

Heavy parsers (``pymupdf``) are imported lazily inside the functions that need
them so importing this module stays cheap and keyless.
"""

from __future__ import annotations

import hashlib
import re
from datetime import datetime, timezone
from pathlib import Path

from .config import RunConfig
from .models import read_json, write_json, write_jsonl

MANIFEST_NAME = "manifest.json"
INGEST_STAGE = "00-ingest"

# ---- prompt-injection sanitization ----------------------------------------
# Deliberately narrow: strip only whole lines that clearly try to override
# instructions. We note the count; we do not aggressively rewrite prose.
_INJECTION_PATTERNS = [
    re.compile(r"ignore\s+(all\s+)?(the\s+)?previous\s+instructions", re.I),
    re.compile(r"ignore\s+(all\s+)?(the\s+)?(above|prior|foregoing)\s+instructions", re.I),
    re.compile(r"disregard\s+(all\s+)?(the\s+)?(previous|prior|above)\s+instructions", re.I),
    re.compile(r"forget\s+(all\s+)?(your\s+)?(previous|prior)\s+instructions", re.I),
    re.compile(r"you\s+are\s+now\s+(a\s+|an\s+)?(different|new)\b", re.I),
]

_BLANKS = re.compile(r"\n{3,}")


def _looks_injected(line: str) -> bool:
    return any(p.search(line) for p in _INJECTION_PATTERNS)


def _clean_text(raw: str) -> tuple[str, int]:
    """Return (cleaned_text, n_injection_lines_removed)."""
    removed = 0
    kept: list[str] = []
    for line in (raw or "").splitlines():
        line = line.rstrip()
        if line and _looks_injected(line):
            removed += 1
            continue
        kept.append(line)
    text = _BLANKS.sub("\n\n", "\n".join(kept)).strip()
    return text, removed


# ---- manifest helpers ------------------------------------------------------
def _manifest_path(cfg: RunConfig) -> Path:
    return cfg.corpus_dir / MANIFEST_NAME


def load_manifest(cfg: RunConfig) -> list[dict]:
    p = _manifest_path(cfg)
    if not p.exists():
        return []
    data = read_json(p)
    return [m for m in data if isinstance(m, dict)] if isinstance(data, list) else []


def _resolve_source_path(cfg: RunConfig, entry: dict) -> Path:
    """Find the on-disk file for a manifest entry, tolerant of how `path` was
    recorded (absolute, relative-to-corpus, or bare filename under source dir)."""
    raw = str(entry.get("path", ""))
    p = Path(raw)
    candidates: list[Path] = []
    if p.is_absolute():
        candidates.append(p)
    candidates.append(cfg.corpus_dir / p)
    if raw:
        candidates.append(cfg.corpus_dir / entry.get("source_id", "") / p.name)
    candidates.append(p)
    for c in candidates:
        if c.exists():
            return c
    return candidates[0]


def register_source(
    cfg: RunConfig,
    path: str | Path,
    source_id: str,
    title: str,
    tier: str = "A",
    license: str = "",
    section: str = "GENERAL",
) -> dict:
    """Stage 0: copy a local file into ``corpus/<source_id>/`` and record a
    manifest entry (with sha256). Re-registering the same ``source_id`` replaces
    its entry, so this is idempotent.
    """
    src = Path(path)
    raw = src.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()

    dest_dir = cfg.corpus_dir / source_id
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / src.name
    if src.resolve() != dest.resolve():
        dest.write_bytes(raw)

    entry = {
        "source_id": source_id,
        "title": title,
        "path": str(dest.relative_to(cfg.corpus_dir)),
        "tier": tier,
        "license": license,
        "section": section,
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
        "sha256": sha,
    }
    manifest = [m for m in load_manifest(cfg) if m.get("source_id") != source_id]
    manifest.append(entry)
    write_json(_manifest_path(cfg), manifest)
    return entry


# ---- extraction ------------------------------------------------------------
def _extract_pdf(path: Path) -> list[tuple[str, str, str]]:
    import pymupdf  # heavy: imported lazily

    rows: list[tuple[str, str, str]] = []
    with pymupdf.open(path) as doc:
        for i, page in enumerate(doc, start=1):
            rows.append((f"p{i}", "", page.get_text("text")))
    return rows


def _heading_path(stack: list[tuple[int, str]]) -> str:
    return " > ".join(title for _, title in stack)


def _split_markdown(raw: str) -> list[tuple[str, str, str]]:
    stack: list[tuple[int, str]] = []
    buf: list[str] = []
    cur_hp = ""
    sections: list[tuple[str, str]] = []

    def flush() -> None:
        body = "\n".join(buf).strip()
        if body:
            sections.append((cur_hp, body))

    for line in (raw or "").splitlines():
        m = re.match(r"^(#{1,6})\s+(.*\S)\s*$", line)
        if m:
            flush()
            buf.clear()
            level = len(m.group(1))
            title = m.group(2).strip()
            stack = [(lvl, t) for (lvl, t) in stack if lvl < level]
            stack.append((level, title))
            cur_hp = _heading_path(stack)
        else:
            buf.append(line)
    flush()
    return [(f"s{i}", hp, body) for i, (hp, body) in enumerate(sections)]


def _split_html(raw: str) -> list[tuple[str, str, str]]:
    from html.parser import HTMLParser

    void_tags = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}

    def hidden(attrs) -> bool:
        values = {str(k).lower(): str(v or "").lower() for k, v in attrs}
        if "hidden" in values:
            return True
        if values.get("aria-hidden") == "true":
            return True
        style = values.get("style", "").replace(" ", "")
        return "display:none" in style or "visibility:hidden" in style

    class _Extractor(HTMLParser):
        def __init__(self) -> None:
            super().__init__(convert_charrefs=True)
            self.sections: list[tuple[str, str]] = []
            self.stack: list[tuple[int, str]] = []
            self.cur_hp = ""
            self.buf: list[str] = []
            self._skip = 0
            self._heading_level: int | None = None
            self._heading_text: list[str] = []

        def _flush(self) -> None:
            body = " ".join("".join(self.buf).split()).strip()
            if body:
                self.sections.append((self.cur_hp, body))
            self.buf = []

        def handle_starttag(self, tag: str, attrs) -> None:
            tag = tag.lower()
            if self._skip:
                if tag not in void_tags:
                    self._skip += 1
                return
            if tag in ("script", "style") or hidden(attrs):
                if tag not in void_tags:
                    self._skip = 1
                return
            if re.fullmatch(r"h[1-6]", tag):
                self._flush()
                self._heading_level = int(tag[1])
                self._heading_text = []

        def handle_endtag(self, tag: str) -> None:
            tag = tag.lower()
            if self._skip:
                self._skip -= 1
                return
            if re.fullmatch(r"h[1-6]", tag) and self._heading_level is not None:
                title = " ".join("".join(self._heading_text).split()).strip()
                level = self._heading_level
                self.stack = [(lvl, t) for (lvl, t) in self.stack if lvl < level]
                if title:
                    self.stack.append((level, title))
                self.cur_hp = _heading_path(self.stack)
                self._heading_level = None

        def handle_data(self, data: str) -> None:
            if self._skip:
                return
            if self._heading_level is not None:
                self._heading_text.append(data)
            else:
                self.buf.append(data)

    ex = _Extractor()
    ex.feed(raw or "")
    ex._flush()
    return [(f"s{i}", hp, body) for i, (hp, body) in enumerate(ex.sections)]


def _extract(path: Path) -> list[tuple[str, str, str]]:
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        return _extract_pdf(path)
    text = path.read_text(encoding="utf-8", errors="replace")
    if suffix in (".md", ".markdown"):
        return _split_markdown(text)
    if suffix in (".html", ".htm"):
        return _split_html(text)
    return [("whole", "", text)]


def run(cfg: RunConfig) -> None:
    manifest = load_manifest(cfg)
    out_dir = cfg.stage_dir(INGEST_STAGE)
    total_rows = 0
    total_injection = 0

    for entry in manifest:
        source_id = entry.get("source_id")
        if not source_id:
            continue
        src = _resolve_source_path(cfg, entry)
        if not src.exists():
            print(f"[cardgen] ingest: WARNING missing file for {source_id}: {src}")
            write_jsonl(out_dir / f"{source_id}.jsonl", [])
            continue

        rows: list[dict] = []
        for locator, heading_path, text in _extract(src):
            clean, removed = _clean_text(text)
            total_injection += removed
            if not clean:
                continue  # skip empty pages/sections
            rows.append(
                {
                    "source_id": source_id,
                    "locator": locator,
                    "heading_path": heading_path,
                    "text": clean,
                }
            )
        write_jsonl(out_dir / f"{source_id}.jsonl", rows)
        total_rows += len(rows)
        print(f"[cardgen] ingest: {source_id} -> {len(rows)} row(s)")

    if total_injection:
        print(
            f"[cardgen] ingest: sanitized {total_injection} suspected "
            f"prompt-injection line(s)"
        )
    print(f"[cardgen] ingest: {total_rows} row(s) from {len(manifest)} source(s)")
