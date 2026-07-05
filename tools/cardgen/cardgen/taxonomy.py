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
    if data.get("section", section) != section:
        raise ValueError(f"section mismatch in {_catalog_path(cfg, section)}")
    sets = data.get("sets", [])
    if not isinstance(sets, list):
        raise ValueError(f"'sets' must be a list in {_catalog_path(cfg, section)}")
    if not sets:
        raise ValueError(f"empty confusion catalog for {section}")
    out: list[dict] = []
    seen: set[str] = set()
    for raw in sets:
        if not isinstance(raw, dict):
            raise ValueError(f"confusion set entries must be mappings in {_catalog_path(cfg, section)}")
        s = dict(raw)
        set_id = str(s.get("set_id", "")).strip()
        if not set_id:
            raise ValueError(f"confusion set missing set_id in {_catalog_path(cfg, section)}")
        if set_id in seen:
            raise ValueError(f"duplicate confusion set {set_id} in {_catalog_path(cfg, section)}")
        seen.add(set_id)
        tags = s.get("tags")
        treatments = s.get("treatments")
        if not isinstance(tags, list) or not tags or not all(str(t).startswith("ds::") for t in tags):
            raise ValueError(f"confusion set {set_id} must define ds:: tags")
        if not isinstance(treatments, list) or not treatments or not all(str(t).strip() for t in treatments):
            raise ValueError(f"confusion set {set_id} must define treatments")
        s["set_id"] = set_id
        s["tags"] = [str(t) for t in tags]
        s["treatments"] = [str(t) for t in treatments]
        out.append(s)
    return out


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
