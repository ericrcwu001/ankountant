#!/usr/bin/env python3
"""Optional LLM usefulness triage for the online (AnkiWeb) card set.

The online cards are ungrounded (no verbatim ``source_passage``), so the pipeline's
grounded judge does not apply. Instead this stages an INDEPENDENT keep/drop pass by
Cursor subagents against a plain "is this a correct, useful CPA study card?" rubric —
the same fan-out pattern the template deck used.

Two phases:

    # 1) write batches for the subagents to grade
    python scripts/triage_online.py prepare --batch-size 75

    # 2) (agent) launch one subagent per queue/batch_XX.json; each writes
    #    verdicts/batch_XX.json = {"verdicts":[{"item_id","keep",bool,"reason"}]}

    # 3) fold verdicts back in -> kept_triaged.jsonl (keep==true)
    python scripts/triage_online.py collect

``collect`` fails OPEN: a card with no verdict is kept (never silently dropped),
so skipping triage entirely just leaves ``kept.jsonl`` as the online set.
"""

from __future__ import annotations

import argparse
import html as _html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ONLINE = ROOT / "out" / "online"
TRIAGE = ONLINE / "triage"
QUEUE = TRIAGE / "queue"
VERDICTS = TRIAGE / "verdicts"

_TAG = re.compile(r"<[^>]+>")
_CLOZE = re.compile(r"\{\{c\d+::(.*?)(?:::.*?)?\}\}", re.DOTALL)
_WS = re.compile(r"\s+")

RUBRIC = (
    "You are a US CPA exam tutor screening third-party flashcards. For EACH card decide "
    "keep=true only if it is a correct, coherent, self-contained study card that teaches "
    "something genuinely useful for the US CPA exam (FAR/AUD/REG/TCP/ISC/BAR) or sound "
    "accounting/audit/tax knowledge. Set keep=false if it is: factually wrong, incoherent "
    "or garbled, a fragment with no real answer, deck-specific mnemonic/administrative noise, "
    "duplicated boilerplate, purely non-US-jurisdiction rules presented as general truth, or "
    "too trivial/vague to teach. Judge only what is shown."
)


def _plain(s: str) -> str:
    s = _CLOZE.sub(r"\1", s or "")
    s = _TAG.sub(" ", s)
    s = _html.unescape(s)
    return _WS.sub(" ", s).strip()


def _read_jsonl(p: Path) -> list[dict]:
    if not p.exists():
        return []
    return [json.loads(line) for line in p.read_text(encoding="utf-8").splitlines() if line.strip()]


def prepare(in_path: Path, batch_size: int) -> None:
    rows = _read_jsonl(in_path)
    QUEUE.mkdir(parents=True, exist_ok=True)
    VERDICTS.mkdir(parents=True, exist_ok=True)
    for old in QUEUE.glob("batch_*.json"):
        old.unlink()
    n_batches = 0
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        cards = [
            {
                "item_id": r["item_id"],
                "section": r.get("section", ""),
                "is_cloze": r.get("is_cloze", False),
                "front": _plain(r.get("front", ""))[:600],
                "back": _plain(r.get("back", ""))[:600],
            }
            for r in batch
        ]
        idx = n_batches
        (QUEUE / f"batch_{idx:02d}.json").write_text(
            json.dumps({"batch": idx, "rubric": RUBRIC, "cards": cards}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        n_batches += 1
    (TRIAGE / "INSTRUCTIONS.md").write_text(
        "# Online triage — subagent instructions\n\n"
        f"{RUBRIC}\n\n"
        "For each `queue/batch_XX.json`, read its `cards`, and write "
        "`verdicts/batch_XX.json` with shape:\n\n"
        '```json\n{"verdicts": [{"item_id": "aw-...", "keep": true, "reason": "..."}]}\n```\n\n'
        "Include exactly one verdict per card. Keep `reason` short.\n",
        encoding="utf-8",
    )
    print(f"[triage] wrote {n_batches} batch(es) of <= {batch_size} to {QUEUE} ({len(rows)} cards)")


def collect(in_path: Path) -> None:
    rows = _read_jsonl(in_path)
    verdicts: dict[str, dict] = {}
    for vf in sorted(VERDICTS.glob("batch_*.json")):
        try:
            data = json.loads(vf.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            print(f"[triage] WARN: could not parse {vf.name}: {e}")
            continue
        items = data.get("verdicts", data) if isinstance(data, dict) else data
        for v in items or []:
            if isinstance(v, dict) and v.get("item_id"):
                verdicts[v["item_id"]] = v

    kept, dropped, missing = [], [], 0
    for r in rows:
        v = verdicts.get(r["item_id"])
        if v is None:
            missing += 1
            kept.append(r)  # fail open — never silently lose a card
            continue
        if v.get("keep", True):
            kept.append(r)
        else:
            dropped.append({"item_id": r["item_id"], "section": r.get("section"), "reason": v.get("reason", "")})

    (ONLINE / "kept_triaged.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in kept), encoding="utf-8"
    )
    (ONLINE / "triaged_dropped.jsonl").write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in dropped), encoding="utf-8"
    )
    print(
        f"[triage] collect: {len(rows)} in -> kept {len(kept)}, dropped {len(dropped)} "
        f"({missing} had no verdict, kept by fail-open). -> out/online/kept_triaged.jsonl"
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="Optional subagent usefulness triage for online cards.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--in", dest="in_path", default=str(ONLINE / "kept.jsonl"))
    p.add_argument("--batch-size", type=int, default=75)
    c = sub.add_parser("collect")
    c.add_argument("--in", dest="in_path", default=str(ONLINE / "kept.jsonl"))
    args = ap.parse_args()

    if args.cmd == "prepare":
        prepare(Path(args.in_path), args.batch_size)
    else:
        collect(Path(args.in_path))


if __name__ == "__main__":
    main()
