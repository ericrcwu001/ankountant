"""Stage 12 — emit gated cards into an Anki ``.apkg`` (genanki).

This is where generated cards become *ordinary* Anki notes the app imports.
Reads ``09-dedup/kept.jsonl`` (``Candidate`` rows, each carrying a judge
``bucket``) and writes, under ``cfg.out_dir``:

- ``cpa_bank.apkg``       — the importable pack (two note types, one per shape)
- ``confusable_patch.json`` — CONFUSABLE map additions for MCQ/confusion items
- ``emitted_manifest.jsonl`` — one row per emitted note (audit trail)
- ``coverage_report.md`` / ``leakage_report.md`` — via :mod:`cardgen.reports`

The two genanki models mirror the app note types EXACTLY (names + field order,
see ``rslib/src/ankountant/notetypes.rs``) so imported notes bind to the app's
lazily-created ``Ankountant Study`` / ``Ankountant TBS`` note types. Note GUIDs
are deterministic (``genanki.guid_for(item_id)``), so re-importing an updated
pack *updates* notes in place instead of duplicating them.

Two integration caveats the importer/app must handle (an ``.apkg`` can't express
either, so they are deliberately out of scope here):

(a) **Sealed-deck cards must be suspended post-import.** The ``.apkg`` format
    cannot carry per-card suspension, so every ``Ankountant::Sealed::…`` card
    lands *unsuspended*; a follow-up must suspend them (the app's sealed
    firewall relies on suspension — see ``seed.rs::suspend_note_cards``).
(b) **``confusable_patch.json`` must be applied via a config load.** The
    CONFUSABLE map lives in ``col`` config (``ankountant.confusable.<section>``),
    which an ``.apkg`` cannot set; the treatments for MCQ/confusion items are
    therefore emitted to this sidecar for a small follow-up (extend the
    seed/config loader) to merge in.
"""

from __future__ import annotations

import hashlib
import json
import re

from .config import RunConfig
from .models import (
    BUCKET_OK,
    MCQ,
    RECALL,
    TBS_DOC_REVIEW,
    TBS_JE,
    TBS_NUMERIC,
    TBS_RESEARCH,
    TBS_TYPE_FOR,
    Candidate,
    read_jsonl,
    write_json,
    write_jsonl,
)
from .util import slugify
from . import reports

# --- Stable, fixed genanki model IDs ---------------------------------------
# Anki matches note types by NAME on import (see notetypes.rs — created lazily
# by name), so these ids only need to be stable + unique within the pack; kept
# as fixed constants so re-imports are consistent. Both sit in genanki's
# recommended 31-bit range [2**30, 2**31).
STUDY_MODEL_ID = 1_607_400_001
TBS_MODEL_ID = 1_607_400_002

# App note-type names + field orders, mirrored EXACTLY from notetypes.rs.
STUDY_NOTETYPE = "Ankountant Study"
TBS_NOTETYPE = "Ankountant TBS"
STUDY_FIELDS = ["Front", "Back", "source_passage", "gen_method", "checker_status"]
TBS_FIELDS = [
    "tbs_type",
    "prompt",
    "exhibits_json",
    "steps_json",
    "schema_tag",
    "source_passage",
    "gen_method",
    "checker_status",
]

# card_type values that map to the TBS note type (MCQ is handled separately).
_TBS_CARD_TYPES = frozenset({TBS_RESEARCH, TBS_NUMERIC, TBS_JE, TBS_DOC_REVIEW})

# Fixed timestamp → hermetic, reproducible package (note/card ids are a stable
# counter; GUIDs come from item_id). 2023-11-14T22:13:20Z.
_EPOCH = 1_700_000_000.0


_WS_TAG = re.compile(r"\s+")


def _safe_tag(t: str) -> str:
    """Anki tags cannot contain spaces. Collapse whitespace to underscores while
    preserving case and the ``::`` hierarchy (so ``sec::FAR`` and
    ``ds::cost::capitalize`` still match the app / CONFUSABLE map)."""
    return _WS_TAG.sub("_", (t or "").strip())


def _deck_id(name: str) -> int:
    """Deterministic 31-bit deck id from the deck name (stable across runs)."""
    h = int(hashlib.sha256(name.encode("utf-8")).hexdigest(), 16)
    return (h % (1 << 30)) + (1 << 30)


def _checker_status(bucket: str) -> str:
    """Judge bucket → note ``checker_status`` (``correct_useful`` ⇒ ``pass``)."""
    return "pass" if bucket == BUCKET_OK else bucket


def _topic_of(cand: Candidate) -> str:
    """The card's topic, from a ``topic::`` tag, else payload, else ``core``."""
    for t in cand.tags:
        if t.startswith("topic::"):
            return t[len("topic::") :]
    return cand.payload.get("topic") or "core"


def _ds_tag_of(cand: Candidate) -> str:
    """The card's ``ds::`` (discrimination-set) tag, from tags or payload."""
    for t in cand.tags:
        if t.startswith("ds::"):
            return t
    return cand.payload.get("ds_tag") or cand.payload.get("schema_tag") or ""


def _sec_tag_of(cand: Candidate) -> str:
    """The card's ``sec::`` tag (from tags, else derived from the section)."""
    for t in cand.tags:
        if t.startswith("sec::"):
            return t
    return f"sec::{cand.section}"


def _set_id_of(cand: Candidate) -> str:
    """The sealed-bank set id: payload ``set_id`` else slug of the topic."""
    if cand.payload.get("set_id"):
        return cand.payload["set_id"]
    if cand.card_type == MCQ:
        ds_tag = _ds_tag_of(cand)
        if ds_tag:
            return slugify(ds_tag.removeprefix("ds::"))
    return slugify(_topic_of(cand))


def _candidate_from_row(row: dict) -> tuple[Candidate, str]:
    """Split a kept.jsonl row into a ``Candidate`` + its judge ``bucket``."""
    bucket = row.get("bucket", BUCKET_OK)
    cand = Candidate(
        item_id=row["item_id"],
        section=row["section"],
        card_type=row["card_type"],
        payload=row.get("payload") or {},
        source_passage=row.get("source_passage", ""),
        source_id=row.get("source_id", ""),
        locator=row.get("locator", ""),
        citation=row.get("citation", ""),
        gen_method=row.get("gen_method") or {},
        tags=list(row.get("tags") or []),
    )
    return cand, bucket


def _build_models(genanki):
    """The two note-type models, mirroring the app field orders exactly."""
    study = genanki.Model(
        STUDY_MODEL_ID,
        STUDY_NOTETYPE,
        fields=[{"name": n} for n in STUDY_FIELDS],
        templates=[
            {
                "name": "Card 1",
                "qfmt": "{{Front}}",
                "afmt": "{{FrontSide}}\n\n<hr id=answer>\n\n{{Back}}",
            }
        ],
    )
    # TBS notes are rendered by the app's own TBS UI; the template only needs to
    # be a valid q/a referencing the first field (mirrors build_hidden_notetype).
    tbs = genanki.Model(
        TBS_MODEL_ID,
        TBS_NOTETYPE,
        fields=[{"name": n} for n in TBS_FIELDS],
        templates=[
            {
                "name": "Card 1",
                "qfmt": "{{tbs_type}}",
                "afmt": "{{FrontSide}}\n\n<hr id=answer>\n\n{{tbs_type}}",
            }
        ],
    )
    return study, tbs


def run(cfg: RunConfig) -> None:
    import genanki

    cfg.out_dir.mkdir(parents=True, exist_ok=True)
    kept_path = cfg.stage_dir("09-dedup") / "kept.jsonl"

    study_model, tbs_model = _build_models(genanki)

    decks: dict[str, "genanki.Deck"] = {}

    def deck_for(name: str):
        d = decks.get(name)
        if d is None:
            d = genanki.Deck(_deck_id(name), name)
            decks[name] = d
        return d

    manifest: list[dict] = []
    confusable_patch: dict[str, dict] = {}

    for row in read_jsonl(kept_path):
        cand, bucket = _candidate_from_row(row)
        status = _checker_status(bucket)
        gen_method_json = json.dumps(cand.gen_method, ensure_ascii=False)
        p = cand.payload

        if cand.card_type == RECALL:
            back = f"{p['back']}\n\nSource: {cand.citation}"
            fields = [p["front"], back, cand.source_passage, gen_method_json, status]
            deck_name = f"Ankountant::Study::{cand.section}::{slugify(_topic_of(cand))}"
            tags = [_safe_tag(t) for t in cand.tags]
            note = genanki.Note(
                model=study_model,
                fields=fields,
                tags=tags,
                guid=genanki.guid_for(cand.item_id),
            )
            note_type = STUDY_NOTETYPE
        else:
            # MCQ + the four TBS shapes all become "Ankountant TBS" notes.
            if cand.card_type == MCQ:
                tbs_type = "mcq"
                prompt = p["prompt"]
                exhibits_json = "[]"
                steps_json = json.dumps(
                    [{"id": "choice", "answer_key": p["answer_key"], "weight": 1.0}],
                    ensure_ascii=False,
                )
                schema_tag = _safe_tag(p["ds_tag"])
                set_id = _set_id_of(cand)
                # Treatments live in the CONFUSABLE map, not the note (.apkg
                # can't carry col config) — collect the additions here.
                entry = confusable_patch.setdefault(
                    set_id,
                    {
                        "section": cand.section,
                        "set_id": set_id,
                        "tags": [],
                        "treatments": list(p.get("treatments", [])),
                    },
                )
                if schema_tag and schema_tag not in entry["tags"]:
                    entry["tags"].append(schema_tag)
                if p.get("treatments"):
                    entry["treatments"] = list(p["treatments"])
            else:
                tbs_type = TBS_TYPE_FOR[cand.card_type]
                prompt = p["prompt"]
                exhibits_json = json.dumps(p.get("exhibits", []), ensure_ascii=False)
                steps_json = json.dumps(p.get("steps", []), ensure_ascii=False)
                schema_tag = _safe_tag(_ds_tag_of(cand))
                set_id = _set_id_of(cand)

            fields = [
                tbs_type,
                prompt,
                exhibits_json,
                steps_json,
                schema_tag,
                cand.source_passage,
                gen_method_json,
                status,
            ]
            deck_name = f"Ankountant::Sealed::{cand.section}::{set_id}"
            tags = [_safe_tag(t) for t in (_sec_tag_of(cand), schema_tag) if t]
            note = genanki.Note(
                model=tbs_model,
                fields=fields,
                tags=tags,
                guid=genanki.guid_for(cand.item_id),
            )
            note_type = TBS_NOTETYPE

        deck_for(deck_name).add_note(note)
        manifest.append(
            {
                "item_id": cand.item_id,
                "note_type": note_type,
                "deck": deck_name,
                "tags": list(tags),
                "checker_status": status,
            }
        )

    apkg_path = cfg.out_dir / "cpa_bank.apkg"
    genanki.Package(list(decks.values())).write_to_file(str(apkg_path), timestamp=_EPOCH)

    write_jsonl(cfg.out_dir / "emitted_manifest.jsonl", manifest)
    write_json(cfg.out_dir / "confusable_patch.json", confusable_patch)

    print(
        f"[cardgen] emit: {len(manifest)} notes across {len(decks)} decks "
        f"-> {apkg_path.name}; {len(confusable_patch)} confusable set(s)"
    )

    reports.run(cfg)
