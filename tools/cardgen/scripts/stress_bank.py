#!/usr/bin/env python3
"""Duplicate the finalized CPA bank up to a target size for app scale-testing.

This is a LOAD TEST artifact, not new study material: it reads the emitted packs
(``cpa_bank.apkg`` + ``online_bank.apkg``), then replicates every note ``ceil(
target / base)`` times with fresh, unique GUIDs (and an invisible per-copy marker
so first-fields are unique too), writing ``out/<run_id>/stress_bank.apkg`` with
>= ``--target`` notes. Content is intentionally identical across copies — the
point is to see whether the app handles tens of thousands of cards.

Copies land under ``Ankountant::Stress::<original-deck>`` (mirroring the source
deck tree under a Stress:: prefix) and are tagged ``stress`` + ``dup::<n>`` so the
whole set is easy to find and delete after testing. The real note types are
preserved (rebuilt from each pack's model definitions), so this exercises the
same rendering paths at scale.

Usage:
    uv run python scripts/stress_bank.py --run-id tmpl4 --target 51000
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from cardgen.config import RunConfig  # noqa: E402

_FIELD_SEP = "\x1f"
_EPOCH = 1_700_000_000.0


def _deck_id(name: str) -> int:
    h = int(hashlib.sha256(name.encode("utf-8")).hexdigest(), 16)
    return (h % (1 << 30)) + (1 << 30)


def _stress_deck(name: str) -> str:
    """Re-home a source deck under the Stress:: subtree (kept separate from the
    real bank so it can be studied or deleted independently)."""
    prefix = "Ankountant::"
    if name.startswith(prefix):
        return f"Ankountant::Stress::{name[len(prefix):]}"
    return f"Ankountant::Stress::{name or 'Default'}"


def _read_pack(apkg: Path) -> tuple[dict[int, dict], list[tuple[int, list[str], list[str], str]]]:
    """Return (models_by_mid, rows) where each row is (mid, fields, tags, deck_name)."""
    with tempfile.TemporaryDirectory() as td:
        z = zipfile.ZipFile(apkg)
        names = z.namelist()
        member = next((m for m in ("collection.anki21", "collection.anki2") if m in names), None)
        if member is None:
            z.close()
            return {}, []
        z.extract(member, td)
        z.close()
        conn = sqlite3.connect(Path(td) / member)
        try:
            models = json.loads(conn.execute("SELECT models FROM col").fetchone()[0])
            decks = json.loads(conn.execute("SELECT decks FROM col").fetchone()[0])
            did_to_name = {int(k): v.get("name", "Default") for k, v in decks.items()}
            nid_to_did: dict[int, int] = {}
            for nid, did in conn.execute("SELECT nid, did FROM cards"):
                nid_to_did.setdefault(int(nid), int(did))
            rows: list[tuple[int, list[str], list[str], str]] = []
            for nid, mid, flds, tags in conn.execute("SELECT id, mid, flds, tags FROM notes"):
                deck = did_to_name.get(nid_to_did.get(int(nid), -1), "Default")
                rows.append((int(mid), (flds or "").split(_FIELD_SEP), (tags or "").split(), deck))
            models_by_mid = {int(m["id"]): m for m in models.values()}
            return models_by_mid, rows
        finally:
            conn.close()


def _to_genanki_model(genanki, m: dict):
    return genanki.Model(
        int(m["id"]),
        m["name"],
        fields=[{"name": f["name"]} for f in sorted(m["flds"], key=lambda f: f.get("ord", 0))],
        templates=[
            {"name": t["name"], "qfmt": t["qfmt"], "afmt": t["afmt"]}
            for t in sorted(m["tmpls"], key=lambda t: t.get("ord", 0))
        ],
        model_type=int(m.get("type", 0)),
        css=m.get("css", ""),
    )


def run(run_id: str, target: int) -> None:
    import genanki

    cfg = RunConfig(run_id=run_id)
    packs = [cfg.out_dir / "cpa_bank.apkg", cfg.out_dir / "online_bank.apkg"]
    packs = [p for p in packs if p.exists()]
    if not packs:
        raise SystemExit(f"no source packs in {cfg.out_dir} (expected cpa_bank.apkg / online_bank.apkg)")

    models_by_mid: dict[int, dict] = {}
    base_rows: list[tuple[int, list[str], list[str], str]] = []
    for pack in packs:
        m, rows = _read_pack(pack)
        models_by_mid.update(m)
        base_rows.extend(rows)
    if not base_rows:
        raise SystemExit("no notes found in source packs")

    genanki_models = {mid: _to_genanki_model(genanki, m) for mid, m in models_by_mid.items()}

    copies = max(1, math.ceil(target / len(base_rows)))
    decks: dict[str, "genanki.Deck"] = {}

    def deck_for(name: str):
        d = decks.get(name)
        if d is None:
            d = genanki.Deck(_deck_id(name), name)
            decks[name] = d
        return d

    idx = 0
    for copy in range(copies):
        for mid, fields, tags, deck in base_rows:
            model = genanki_models.get(mid)
            if model is None:
                continue
            f = list(fields)
            # Invisible per-copy marker => unique first field (belt-and-suspenders
            # with the unique GUID) so nothing collapses on import.
            f[0] = f"{f[0]}<!--s{idx}-->"
            note = genanki.Note(
                model=model,
                fields=f,
                tags=[*tags, "stress", f"dup::{copy}"],
                guid=genanki.guid_for(f"stress-{idx}"),
            )
            deck_for(_stress_deck(deck)).add_note(note)
            idx += 1

    out_path = cfg.out_dir / "stress_bank.apkg"
    genanki.Package(list(decks.values())).write_to_file(str(out_path), timestamp=_EPOCH)
    print(
        f"[stress] base={len(base_rows)} x copies={copies} -> {idx} notes "
        f"across {len(decks)} decks -> {out_path.name} (target was {target})"
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="Replicate the CPA bank to >= --target notes for scale testing.")
    ap.add_argument("--run-id", default="tmpl4")
    ap.add_argument("--target", type=int, default=51000, help="minimum number of notes to emit")
    args = ap.parse_args()
    run(args.run_id, args.target)


if __name__ == "__main__":
    main()
