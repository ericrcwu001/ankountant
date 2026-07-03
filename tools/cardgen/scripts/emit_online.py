#!/usr/bin/env python3
"""Emit the online (AnkiWeb) cards into ``online_bank.apkg`` (genanki).

Reads ``out/online/kept_triaged.jsonl`` when present (the LLM-triaged set), else
``out/online/kept.jsonl``, and writes ``out/<run_id>/online_bank.apkg`` next to
the AI ``cpa_bank.apkg`` so the desktop one-click loader imports both.

Each card becomes an ordinary Basic/Cloze note under a section-categorized deck
``Ankountant::Community::<SECTION>::<deck-slug>`` and keeps its provenance tags
(``src::ankiweb``, ``src::ankiweb::<deck_id>``, ``sec::<SECTION>``). GUIDs are
deterministic from ``item_id`` so re-imports update in place.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from cardgen.config import ROOT, RunConfig  # noqa: E402
from cardgen.models import read_jsonl, write_jsonl  # noqa: E402
from cardgen.util import slugify  # noqa: E402

ONLINE = ROOT / "out" / "online"

# Fixed genanki model ids (distinct from emit.py's 1_607_400_00x AI models).
BASIC_MODEL_ID = 1_607_500_001
CLOZE_MODEL_ID = 1_607_500_002
BASIC_NOTETYPE = "Ankountant Community Basic"
CLOZE_NOTETYPE = "Ankountant Community Cloze"
_EPOCH = 1_700_000_000.0

_WS_TAG = re.compile(r"\s+")
_SRC_STYLE = 'color:#8a8a8a;font-size:12px'


def _safe_tag(t: str) -> str:
    return _WS_TAG.sub("_", (t or "").strip())


def _deck_id(name: str) -> int:
    h = int(hashlib.sha256(name.encode("utf-8")).hexdigest(), 16)
    return (h % (1 << 30)) + (1 << 30)


def _build_models(genanki):
    basic = genanki.Model(
        BASIC_MODEL_ID,
        BASIC_NOTETYPE,
        fields=[{"name": "Front"}, {"name": "Back"}, {"name": "Source"}],
        templates=[
            {
                "name": "Card 1",
                "qfmt": "{{Front}}",
                "afmt": (
                    "{{FrontSide}}\n\n<hr id=answer>\n\n{{Back}}"
                    f'\n\n<div style="{_SRC_STYLE}">{{{{Source}}}}</div>'
                ),
            }
        ],
    )
    cloze = genanki.Model(
        CLOZE_MODEL_ID,
        CLOZE_NOTETYPE,
        fields=[{"name": "Text"}, {"name": "Back Extra"}, {"name": "Source"}],
        model_type=genanki.Model.CLOZE,
        templates=[
            {
                "name": "Cloze",
                "qfmt": "{{cloze:Text}}",
                "afmt": (
                    "{{cloze:Text}}\n\n{{Back Extra}}"
                    f'\n\n<div style="{_SRC_STYLE}">{{{{Source}}}}</div>'
                ),
            }
        ],
    )
    return basic, cloze


def run(run_id: str) -> None:
    import genanki

    cfg = RunConfig(run_id=run_id)
    src = ONLINE / "kept_triaged.jsonl"
    triaged = src.exists()
    if not triaged:
        src = ONLINE / "kept.jsonl"
    rows = list(read_jsonl(src))

    basic_model, cloze_model = _build_models(genanki)
    decks: dict[str, "genanki.Deck"] = {}

    def deck_for(name: str):
        d = decks.get(name)
        if d is None:
            d = genanki.Deck(_deck_id(name), name)
            decks[name] = d
        return d

    manifest: list[dict] = []
    by_section: Counter = Counter()
    by_source: Counter = Counter()

    for r in rows:
        section = r.get("section") or "GENERAL"
        deck_slug = slugify(r.get("source_title") or r.get("source_deck_id") or "community")
        deck_name = f"Ankountant::Community::{section}::{deck_slug}"
        source_label = f"AnkiWeb · {r.get('source_title', '')}".strip(" ·")
        tags = [_safe_tag(t) for t in (r.get("tags") or [])]

        if r.get("is_cloze"):
            note = genanki.Note(
                model=cloze_model,
                fields=[r.get("front", ""), r.get("back", ""), source_label],
                tags=tags,
                guid=genanki.guid_for(r["item_id"]),
            )
            note_type = CLOZE_NOTETYPE
        else:
            note = genanki.Note(
                model=basic_model,
                fields=[r.get("front", ""), r.get("back", ""), source_label],
                tags=tags,
                guid=genanki.guid_for(r["item_id"]),
            )
            note_type = BASIC_NOTETYPE

        deck_for(deck_name).add_note(note)
        by_section[section] += 1
        by_source[r.get("source_title") or r.get("source_deck_id")] += 1
        manifest.append(
            {
                "item_id": r["item_id"],
                "note_type": note_type,
                "deck": deck_name,
                "section": section,
                "tags": tags,
            }
        )

    out_path = cfg.out_dir / "online_bank.apkg"
    genanki.Package(list(decks.values())).write_to_file(str(out_path), timestamp=_EPOCH)
    write_jsonl(ONLINE / "emitted_manifest.jsonl", manifest)

    print(
        f"[online-emit] {len(manifest)} notes across {len(decks)} decks -> {out_path.name} "
        f"(source: {'kept_triaged' if triaged else 'kept'}.jsonl)"
    )
    print(f"[online-emit] by section: {dict(by_section.most_common())}")
    print(f"[online-emit] by deck: {dict(by_source.most_common())}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Emit online-sourced cards into online_bank.apkg")
    ap.add_argument("--run-id", default="tmpl4")
    args = ap.parse_args()
    run(args.run_id)


if __name__ == "__main__":
    main()
