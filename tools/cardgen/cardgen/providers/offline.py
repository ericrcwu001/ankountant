"""Deterministic, keyless backends for tests and CI.

Every output is a pure function of the input (hash-seeded), so tests can assert
exact behavior and the whole DAG runs end-to-end with no key or network.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct

from ..models import (
    BUCKET_BAD,
    BUCKET_OK,
    BUCKET_WRONG,
    MCQ,
    RECALL,
    TBS_DOC_REVIEW,
    TBS_JE,
    TBS_NUMERIC,
    TBS_RESEARCH,
    GenRequest,
    Verdict,
)


class OfflineEmbedder:
    def __init__(self, dim: int = 256) -> None:
        self.dim = dim

    def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._vec(t) for t in texts]

    def _vec(self, text: str) -> list[float]:
        out: list[float] = []
        h = hashlib.sha256(text.encode("utf-8")).digest()
        i = 0
        while len(out) < self.dim:
            h = hashlib.sha256(h + i.to_bytes(2, "big")).digest()
            for j in range(0, len(h), 4):
                if len(out) >= self.dim:
                    break
                out.append(struct.unpack(">I", h[j : j + 4])[0] / 2**32 - 0.5)
            i += 1
        norm = math.sqrt(sum(x * x for x in out)) or 1.0
        return [x / norm for x in out]


class OfflineGenerator:
    """Builds a schema-valid card deterministically from the top passage."""

    def generate(self, req: GenRequest) -> str:
        passage = req.passages[0].text.strip() if req.passages else "No passage available."
        source_passage = passage.split(". ")[0][:180] or passage[:180]
        citation = f"{req.section} {req.topic} ref"
        ct = req.card_type

        if ct == RECALL:
            payload = {
                "front": f"[{req.topic}] What does the source state?",
                "back": source_passage,
            }
        elif ct == MCQ:
            payload = {
                "prompt": f"[{req.topic}] Which treatment applies?",
                "answer_key": "OptionA",
                "ds_tag": f"ds::{req.topic}::a",
                "treatments": ["OptionA", "OptionB"],
            }
        elif ct == TBS_RESEARCH:
            payload = {
                "prompt": f"[{req.topic}] Cite the governing standard.",
                "exhibits": [{"title": "Scenario", "kind": "text", "body": source_passage}],
                "steps": [
                    {
                        "id": "citation",
                        "kind": "citation",
                        "answer_key": [citation],
                        "weight": 1.0,
                        "label": "Governing citation",
                        "corpus_refs": [],
                        "granularity": "paragraph",
                    }
                ],
            }
        elif ct == TBS_NUMERIC:
            payload = {
                "prompt": f"[{req.topic}] Compute the amount.",
                "exhibits": [{"title": "Data", "kind": "text", "body": source_passage}],
                "steps": [
                    {
                        "id": "c1",
                        "kind": "numeric",
                        "answer_key": 100.0,
                        "weight": 1.0,
                        "label": "Amount",
                        "tolerance": 0.01,
                    }
                ],
            }
        elif ct == TBS_JE:
            payload = {
                "prompt": f"[{req.topic}] Record the journal entry.",
                "exhibits": [{"title": "Data", "kind": "text", "body": source_passage}],
                "steps": [
                    {
                        "id": "l1",
                        "kind": "je",
                        "answer_key": {"account": "Cash", "side": "dr", "amount": 100.0},
                        "weight": 0.5,
                    },
                    {
                        "id": "l2",
                        "kind": "je",
                        "answer_key": {"account": "Revenue", "side": "cr", "amount": 100.0},
                        "weight": 0.5,
                    },
                ],
            }
        elif ct == TBS_DOC_REVIEW:
            payload = {
                "prompt": f"[{req.topic}] Review the document and correct each blank.",
                "exhibits": [
                    {
                        "id": "doc",
                        "title": "Document",
                        "kind": "document",
                        "role": "document",
                        "body": 'Intro. <blank step="s1">original text</blank> end.',
                    }
                ],
                "steps": [
                    {
                        "id": "s1",
                        "kind": "blank",
                        "answer_key": "o1",
                        "weight": 1.0,
                        "label": "Blank 1",
                        "original_text": "original text",
                        "confusion_set_id": f"cs_{req.topic}",
                        "options": [
                            {"id": "o1", "kind": "keep", "text": "Retain the original."},
                            {"id": "o2", "kind": "replace", "text": "Replace it."},
                        ],
                    }
                ],
            }
        else:
            payload = {"front": "?", "back": source_passage}

        return json.dumps(
            {"source_passage": source_passage, "citation": citation, "payload": payload},
            ensure_ascii=False,
        )


class OfflineJudge:
    """Deterministic 3-bucket verdicts driven by defect markers.

    Gold-set negatives are authored to embed `__wrong__` / `__bad__` markers so
    judge calibration is testable offline. Real (marker-free, grounded) cards
    pass; ungrounded cards fail.
    """

    def judge(self, cards: list[dict], rubric: str) -> list[Verdict]:
        out: list[Verdict] = []
        for c in cards:
            blob = json.dumps(c.get("payload", {}), ensure_ascii=False)
            if "__wrong__" in blob:
                out.append(Verdict(c["item_id"], BUCKET_WRONG, "wrong marker", 0.0))
            elif "__bad__" in blob:
                out.append(Verdict(c["item_id"], BUCKET_BAD, "bad-teaching marker", 0.5))
            elif not c.get("source_passage"):
                out.append(Verdict(c["item_id"], BUCKET_WRONG, "ungrounded", 0.0))
            else:
                out.append(Verdict(c["item_id"], BUCKET_OK, "grounded, no defect", 1.0))
        return out
