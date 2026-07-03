"""Coverage report — targets vs generated vs shipped, plus a drop breakdown.

``run(cfg)`` (called by :mod:`cardgen.emit`, or standalone) writes
``cfg.out_dir/coverage_report.md`` from the DAG artifacts:

- **target**    per (section, topic) — from ``03-worklist/worklist.jsonl``
- **generated** per (section, topic) — from ``05-candidates/<item_id>.json``
- **shipped**   per (section, topic) — from ``09-dedup/kept.jsonl``
- **drops**     per (stage, reason)  — aggregated from every stage's
  ``dropped.jsonl`` (``06-checked``, ``08-leak``, ``09-dedup``)

Every input is read defensively: a missing artifact contributes zero, so the
report is useful at any point in the pipeline (e.g. after a bare emit).
"""

from __future__ import annotations

import json
from collections import defaultdict

from .config import RunConfig
from .models import read_jsonl
from .util import slugify

# (stage subdir, human label) for the stages that drop candidates.
_DROP_STAGES = [
    ("06-checked", "selfcheck"),
    ("08-leak", "leakage"),
    ("09-dedup", "dedup"),
]

SectionTopic = tuple[str, str]


def _topic_of_row(row: dict) -> str:
    """Topic for a row: explicit field, else a ``topic::`` tag, else ``core``."""
    topic = row.get("topic")
    if topic:
        return topic
    for t in row.get("tags") or []:
        if t.startswith("topic::"):
            return t[len("topic::") :]
    payload = row.get("payload") or {}
    return payload.get("topic") or "core"


def _key(row: dict) -> SectionTopic:
    # Slugify so a work-list row (human topic) and a candidate/shipped row
    # (topic::<slug> tag) join on the same key.
    return (row.get("section", "?"), slugify(_topic_of_row(row)))


def _topic_labels(cfg: RunConfig) -> dict[SectionTopic, str]:
    """Map (section, topic-slug) -> the human topic label from the work-list."""
    labels: dict[SectionTopic, str] = {}
    for row in read_jsonl(cfg.out_dir / "03-worklist" / "worklist.jsonl"):
        human = _topic_of_row(row)
        labels[(row.get("section", "?"), slugify(human))] = human
    return labels


def _count_worklist(cfg: RunConfig) -> dict[SectionTopic, int]:
    counts: dict[SectionTopic, int] = defaultdict(int)
    for row in read_jsonl(cfg.out_dir / "03-worklist" / "worklist.jsonl"):
        counts[_key(row)] += 1
    return counts


def _count_candidates(cfg: RunConfig) -> dict[SectionTopic, int]:
    counts: dict[SectionTopic, int] = defaultdict(int)
    cand_dir = cfg.out_dir / "05-candidates"
    if cand_dir.exists():
        for fp in sorted(cand_dir.glob("*.json")):
            try:
                row = json.loads(fp.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            counts[_key(row)] += 1
    return counts


def _count_shipped(cfg: RunConfig) -> dict[SectionTopic, int]:
    counts: dict[SectionTopic, int] = defaultdict(int)
    for row in read_jsonl(cfg.out_dir / "09-dedup" / "kept.jsonl"):
        counts[_key(row)] += 1
    return counts


def _count_drops(cfg: RunConfig) -> dict[tuple[str, str], int]:
    counts: dict[tuple[str, str], int] = defaultdict(int)
    for sub, label in _DROP_STAGES:
        for row in read_jsonl(cfg.out_dir / sub / "dropped.jsonl"):
            reason = row.get("reason") or row.get("bucket") or "unspecified"
            counts[(label, reason)] += 1
    return counts


def _pct(num: int, den: int) -> str:
    return f"{100.0 * num / den:.0f}%" if den else "-"


def build_markdown(cfg: RunConfig) -> str:
    target = _count_worklist(cfg)
    generated = _count_candidates(cfg)
    shipped = _count_shipped(cfg)
    drops = _count_drops(cfg)

    keys = sorted(set(target) | set(generated) | set(shipped))
    labels = _topic_labels(cfg)

    lines: list[str] = [f"# Coverage report — run `{cfg.run_id}`", ""]

    # --- Per-topic coverage ------------------------------------------------
    lines += [
        "## Per-topic coverage",
        "",
        "| Section | Topic | Target | Generated | Shipped |",
        "| --- | --- | --: | --: | --: |",
    ]
    tot_t = tot_g = tot_s = 0
    for section, topic in keys:
        t = target.get((section, topic), 0)
        g = generated.get((section, topic), 0)
        s = shipped.get((section, topic), 0)
        tot_t, tot_g, tot_s = tot_t + t, tot_g + g, tot_s + s
        lines.append(f"| {section} | {labels.get((section, topic), topic)} | {t} | {g} | {s} |")
    lines.append(f"| **Total** | | {tot_t} | {tot_g} | {tot_s} |")
    lines.append("")

    # --- Per-section summary ----------------------------------------------
    lines += [
        "## Per-section summary",
        "",
        "| Section | Target | Generated | Shipped | Shipped/Target |",
        "| --- | --: | --: | --: | --: |",
    ]
    sections = sorted({section for section, _ in keys})
    for section in sections:
        t = sum(v for (sec, _), v in target.items() if sec == section)
        g = sum(v for (sec, _), v in generated.items() if sec == section)
        s = sum(v for (sec, _), v in shipped.items() if sec == section)
        lines.append(f"| {section} | {t} | {g} | {s} | {_pct(s, t)} |")
    lines.append(
        f"| **Total** | {tot_t} | {tot_g} | {tot_s} | {_pct(tot_s, tot_t)} |"
    )
    lines.append("")

    # --- Drop breakdown ----------------------------------------------------
    lines += [
        "## Drops (by stage & reason)",
        "",
        "| Stage | Reason | Count |",
        "| --- | --- | --: |",
    ]
    tot_d = 0
    for (label, reason), count in sorted(drops.items()):
        tot_d += count
        lines.append(f"| {label} | {reason} | {count} |")
    if not drops:
        lines.append("| _(none)_ | | 0 |")
    lines.append(f"| **Total dropped** | | {tot_d} |")
    lines.append("")

    return "\n".join(lines)


def run(cfg: RunConfig) -> None:
    cfg.out_dir.mkdir(parents=True, exist_ok=True)
    out = cfg.out_dir / "coverage_report.md"
    out.write_text(build_markdown(cfg), encoding="utf-8")
    print(f"[cardgen] reports: wrote {out.name}")
