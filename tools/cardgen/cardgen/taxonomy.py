"""Stage-4 inputs: AICPA blueprint taxonomy + confusion-set catalog loaders.

The YAML lives under ``cfg.taxonomy_dir`` (``tools/cardgen/taxonomy/``):

- ``taxonomy.<SECTION>.yaml``          — blueprint tree (areas/groups/topics)
- ``confusion_catalog.<SECTION>.yaml`` — curated confusion sets (ds:: tags)

These are static, version-controlled inputs, so every loader is a pure function
of ``(cfg, section)`` and the on-disk files — nothing here touches the network
or a key (offline-first per doc 07).
"""

from __future__ import annotations

from pathlib import Path

import yaml

from .config import RunConfig


def _taxonomy_path(cfg: RunConfig, section: str) -> Path:
    return cfg.taxonomy_dir / f"taxonomy.{section}.yaml"


def _catalog_path(cfg: RunConfig, section: str) -> Path:
    return cfg.taxonomy_dir / f"confusion_catalog.{section}.yaml"


def _load_yaml(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"taxonomy file missing: {path}")
    with path.open(encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict):
        raise ValueError(f"expected a mapping at top level of {path}, got {type(data).__name__}")
    return data


def load_taxonomy(cfg: RunConfig, section: str) -> dict:
    """Parsed ``taxonomy.<section>.yaml`` (``{section, areas:[...]}``)."""
    data = _load_yaml(_taxonomy_path(cfg, section))
    data.setdefault("section", section)
    data.setdefault("areas", [])
    return data


def load_confusion_catalog(cfg: RunConfig, section: str) -> list[dict]:
    """The section's confusion sets: ``[{set_id, topic, tags, treatments}, ...]``."""
    data = _load_yaml(_catalog_path(cfg, section))
    sets = data.get("sets", [])
    if not isinstance(sets, list):
        raise ValueError(f"'sets' must be a list in {_catalog_path(cfg, section)}")
    return [dict(s) for s in sets]


def all_topics(cfg: RunConfig, section: str) -> list[dict]:
    """Flatten the blueprint tree to one row per representative task.

    Each row: ``{section, area, area_weight, group, topic, task_id, skill_level}``
    in document order (area -> group -> topic), which keeps downstream
    allocation deterministic.
    """
    tax = load_taxonomy(cfg, section)
    sec = tax.get("section", section)
    out: list[dict] = []
    for area in tax.get("areas", []):
        area_title = area["title"]
        area_weight = float(area["weight"])
        for group in area.get("groups", []):
            group_title = group["title"]
            for topic in group.get("topics", []):
                out.append(
                    {
                        "section": sec,
                        "area": area_title,
                        "area_weight": area_weight,
                        "group": group_title,
                        "topic": topic["topic"],
                        "task_id": topic["task_id"],
                        "skill_level": topic["skill_level"],
                    }
                )
    return out
