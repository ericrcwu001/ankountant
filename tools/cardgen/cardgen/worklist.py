"""Stage 4 — worklist.

Expands the blueprint taxonomy x confusion-set catalog into a flat list of
``WorkItem``s and writes ``03-worklist/worklist.jsonl``. This is the pipeline's
spine: everything downstream (retrieve -> generate -> ...) iterates over it.

Allocation (doc 02 "Allocating 50,000"), two levels + skill split:

1. **Across sections** — split ``cfg.target_total`` by the doc-2 section
   weights (FAR 11k / REG 9k / AUD 8k / TCP 8k / BAR 8k / ISC 6k), normalized
   over whatever sections were requested.
2. **Within a section** — split that section's budget across the three skill
   *families* by summed ``area_weight x topic_share`` (topic_share = equal share
   within an area), then within a family across topics.
3. **Skill level -> card_type**:
   - ``R&U``                 -> ``recall``
   - ``Application``         -> ``mcq`` (from the confusion catalog) + some
     applied ``recall`` (from the taxonomy topics)
   - ``Analysis``/``Evaluation`` -> the four TBS shapes, rotated so every
     section gets several of EACH shape (research + numeric emphasized), with
     >=1 of each shape guaranteed whenever the section budget allows.

Everything is a pure function of ``cfg`` (sections, target_total, seed) and the
static YAML, so re-running yields a byte-identical worklist.
"""

from __future__ import annotations

import math
from collections import Counter
from pathlib import Path

from .config import RunConfig
from .models import (
    MCQ,
    RECALL,
    TBS_DOC_REVIEW,
    TBS_JE,
    TBS_NUMERIC,
    TBS_RESEARCH,
    WorkItem,
    write_jsonl,
)
from .taxonomy import all_topics, load_confusion_catalog
from .util import content_hash, slugify

# doc 02 across-section targets (of a 50k build); used as relative weights and
# normalized to the requested sections + target_total.
SECTION_WEIGHTS: dict[str, int] = {
    "FAR": 11000,
    "REG": 9000,
    "AUD": 8000,
    "TCP": 8000,
    "BAR": 8000,
    "ISC": 6000,
}

_RU_LEVELS = {"R&U"}
_APP_LEVELS = {"Application"}
_AE_LEVELS = {"Analysis", "Evaluation"}

# Rotation for TBS shapes. The four are guaranteed first (coverage), then the
# tail emphasizes research + numeric per the plan (they are the highest-value,
# most-gradeable shapes).
_TBS_ORDER = [TBS_RESEARCH, TBS_NUMERIC, TBS_JE, TBS_DOC_REVIEW]
_TBS_EMPHASIS = [TBS_RESEARCH, TBS_NUMERIC, TBS_JE, TBS_DOC_REVIEW, TBS_RESEARCH, TBS_NUMERIC]

# Fraction of the Application budget spent on confusion (MCQ) items; the rest
# becomes applied recall. Confusion is emphasized (doc 02).
_MCQ_SHARE = 0.6


def largest_remainder(weights: list[float], total: int) -> list[int]:
    """Apportion ``total`` integer units across ``weights`` (Hamilton method).

    Deterministic: leftover units go to the largest fractional remainders, ties
    broken by lowest index. Sum of the result is exactly ``total`` (for
    ``total >= 0``).
    """
    n = len(weights)
    if n == 0 or total <= 0:
        return [0] * n
    s = float(sum(weights))
    if s <= 0.0:  # degenerate: even split
        base, extra = divmod(total, n)
        return [base + (1 if i < extra else 0) for i in range(n)]
    raw = [w / s * total for w in weights]
    floors = [int(math.floor(x)) for x in raw]
    rem = total - sum(floors)
    order = sorted(range(n), key=lambda i: (raw[i] - floors[i], -i), reverse=True)
    for k in range(rem):
        floors[order[k % n]] += 1
    return floors


def _enforce_minimums(budgets: list[int], mins: list[int], total: int) -> list[int]:
    """Bump any family below its minimum, borrowing from the most-surplus family.

    Keeps ``sum(budgets) == total``. If the minimums cannot fit (``sum(mins) >
    total``) the budgets are returned unchanged (the "when target allows"
    caveat).
    """
    if sum(mins) > total:
        return list(budgets)
    b = list(budgets)
    for i in range(len(b)):
        deficit = mins[i] - b[i]
        if deficit <= 0:
            continue
        b[i] = mins[i]
        while deficit > 0:
            donors = [j for j in range(len(b)) if j != i and b[j] > mins[j]]
            if not donors:
                break
            cand = max(donors, key=lambda j: (b[j] - mins[j], -j))
            b[cand] -= 1
            deficit -= 1
    return b


def _tbs_shape_sequence(n: int) -> list[str]:
    """``n`` TBS shapes: one of each first (if ``n >= 4``), then research/numeric-heavy."""
    if n <= 0:
        return []
    seq = list(_TBS_ORDER[: min(n, 4)])
    j = 0
    while len(seq) < n:
        seq.append(_TBS_EMPHASIS[j % len(_TBS_EMPHASIS)])
        j += 1
    return seq


def section_targets(cfg: RunConfig) -> dict[str, int]:
    """Per-section card budgets, normalized from the doc-2 weights."""
    weights = [float(SECTION_WEIGHTS.get(s, 8000)) for s in cfg.sections]
    counts = largest_remainder(weights, cfg.target_total)
    return dict(zip(cfg.sections, counts))


def _make_item(
    cfg: RunConfig,
    *,
    section: str,
    area: str,
    topic: str,
    task_id: str,
    skill_level: str,
    card_type: str,
    i: int,
    category: dict,
) -> WorkItem:
    set_id = str(category.get("set_id", "")).strip()
    tags = [str(t) for t in (category.get("tags") or [])]
    treatments = [str(t) for t in (category.get("treatments") or [])]
    if not set_id or not tags or not treatments:
        raise ValueError(f"{section} work item missing category metadata for {topic}")
    item_id = content_hash(section, task_id, i)
    # Per-item seed: deterministic in cfg.seed but distinct per item, so
    # downstream generation can vary fact patterns without colliding.
    seed = (int(item_id[:8], 16) ^ (cfg.seed & 0xFFFFFFFF)) & 0x7FFFFFFF
    return WorkItem(
        item_id=item_id,
        section=section,
        area=area,
        topic=topic,
        task_id=task_id,
        skill_level=skill_level,
        card_type=card_type,
        seed=seed,
        category=set_id,
        category_tags=tags,
        treatments=treatments,
    )


def _category_for_topic(sets: list[dict], topic: str, index: int) -> dict:
    """Deterministic category metadata for a non-MCQ topic item."""
    if not sets:
        raise ValueError(f"missing confusion catalog while categorizing {topic}")
    normalized = topic.strip().lower()
    for st in sets:
        catalog_topic = str(st.get("topic", "")).strip().lower()
        if catalog_topic == normalized:
            return st
    return sets[index % len(sets)]


def allocate_section(cfg: RunConfig, section: str, target: int) -> list[WorkItem]:
    """Build the WorkItems for one section (see module docstring for the model)."""
    topics = all_topics(cfg, section)
    sets = load_confusion_catalog(cfg, section)
    if not topics or target <= 0:
        return []

    area_topic_count = Counter(t["area"] for t in topics)

    def topic_weight(t: dict) -> float:
        return t["area_weight"] / area_topic_count[t["area"]]

    ru = [t for t in topics if t["skill_level"] in _RU_LEVELS]
    app = [t for t in topics if t["skill_level"] in _APP_LEVELS]
    ae = [t for t in topics if t["skill_level"] in _AE_LEVELS]

    fam_weights = [
        sum(topic_weight(t) for t in ru),
        sum(topic_weight(t) for t in app),
        sum(topic_weight(t) for t in ae),
    ]
    budgets = largest_remainder(fam_weights, target)
    # Minimums so a section that can afford it shows every card type: >=1 recall,
    # >=1 mcq, and >=4 TBS (one per shape).
    mins = [
        1 if ru else 0,
        1 if (app and sets) else 0,
        4 if ae else 0,
    ]
    budgets = _enforce_minimums(budgets, mins, target)
    b_ru, b_app, b_ae = budgets

    if sets and b_app > 0:
        mcq_budget = min(b_app, max(1, round(b_app * _MCQ_SHARE)))
    else:
        mcq_budget = 0
    applied_budget = b_app - mcq_budget
    # If there are no Application topics to carry applied recall, fold it into MCQ.
    if not app and applied_budget > 0 and sets:
        mcq_budget += applied_budget
        applied_budget = 0

    topic_area = {t["topic"]: t["area"] for t in topics}
    topic_category = {
        id(t): _category_for_topic(sets, t["topic"], i)
        for i, t in enumerate(topics)
    }
    items: list[WorkItem] = []

    # (a) R&U topics -> recall
    for t, c in zip(ru, largest_remainder([topic_weight(x) for x in ru], b_ru)):
        for i in range(c):
            items.append(
                _make_item(
                    cfg,
                    section=section,
                    area=t["area"],
                    topic=t["topic"],
                    task_id=t["task_id"],
                    skill_level=t["skill_level"],
                    card_type=RECALL,
                    i=i,
                    category=topic_category[id(t)],
                )
            )

    # (b) Application topics -> applied recall
    if app and applied_budget > 0:
        for t, c in zip(app, largest_remainder([topic_weight(x) for x in app], applied_budget)):
            for i in range(c):
                items.append(
                    _make_item(
                        cfg,
                        section=section,
                        area=t["area"],
                        topic=t["topic"],
                        task_id=t["task_id"],
                        skill_level=t["skill_level"],
                        card_type=RECALL,
                        i=i,
                        category=topic_category[id(t)],
                    )
                )

    # (c) confusion catalog -> mcq (this is the taxonomy x catalog expansion)
    if sets and mcq_budget > 0:
        for st, c in zip(sets, largest_remainder([1.0] * len(sets), mcq_budget)):
            set_id = st["set_id"]
            topic = st.get("topic", set_id)
            area = topic_area.get(topic, "Confusion sets")
            task_id = f"{section}.confusion.{slugify(set_id)}"
            for i in range(c):
                items.append(
                    _make_item(
                        cfg,
                        section=section,
                        area=area,
                        topic=topic,
                        task_id=task_id,
                        skill_level="Application",
                        card_type=MCQ,
                        i=i,
                        category=st,
                    )
                )

    # (d) Analysis/Evaluation topics -> TBS shapes (rotated for coverage)
    if ae and b_ae > 0:
        ae_counts = largest_remainder([topic_weight(x) for x in ae], b_ae)
        shapes = _tbs_shape_sequence(sum(ae_counts))
        shape_i = 0
        for t, c in zip(ae, ae_counts):
            for i in range(c):
                card_type = shapes[shape_i]
                shape_i += 1
                items.append(
                    _make_item(
                        cfg,
                        section=section,
                        area=t["area"],
                        topic=t["topic"],
                        task_id=t["task_id"],
                        skill_level=t["skill_level"],
                        card_type=card_type,
                        i=i,
                        category=topic_category[id(t)],
                    )
                )

    return items


def build_worklist(cfg: RunConfig) -> list[WorkItem]:
    """The full ordered worklist across all requested sections."""
    targets = section_targets(cfg)
    items: list[WorkItem] = []
    for section in cfg.sections:
        items.extend(allocate_section(cfg, section, targets.get(section, 0)))
    return items


def run(cfg: RunConfig) -> Path:
    items = build_worklist(cfg)
    out_path = cfg.stage_dir("03-worklist") / "worklist.jsonl"
    write_jsonl(out_path, items)

    by_type = Counter(it.card_type for it in items)
    by_section = Counter(it.section for it in items)
    print(
        f"[cardgen] worklist: {len(items)} items "
        f"(target {cfg.target_total}) across {len(cfg.sections)} sections -> {out_path}"
    )
    print(f"[cardgen]   by section: {dict(by_section)}")
    print(f"[cardgen]   by type:    {dict(by_type)}")
    return out_path
