"""Offline tests for the Stage-2 chunk-quality filter (`_is_low_value`).

    cd tools/cardgen && UV_PROJECT_ENVIRONMENT=.venv CARDGEN_OFFLINE=1 \
        uv run pytest tests/test_chunk_filter.py -q
"""

from __future__ import annotations

from cardgen.chunk import MIN_PROSE_TOKENS, _is_low_value, count_tokens

# A genuine answer-bearing paragraph (well above the prose-token floor).
PROSE = (
    "Under ASC 606, revenue is recognized when a performance obligation is "
    "satisfied by transferring control of a promised good or service to a "
    "customer. The transaction price is allocated to each distinct performance "
    "obligation based on its relative standalone selling price, and revenue is "
    "recognized as each obligation is satisfied over time or at a point in time. "
    "Variable consideration is estimated and constrained so that a significant "
    "reversal is unlikely."
)


def test_keeps_real_prose() -> None:
    assert count_tokens(PROSE) >= MIN_PROSE_TOKENS
    low, reason = _is_low_value(PROSE)
    assert not low, reason


def test_drops_empty_and_short() -> None:
    assert _is_low_value("")[0]
    assert _is_low_value("   ")[0]
    drop, reason = _is_low_value("Goodwill Impairment")  # a bare heading
    assert drop and reason == "too_short"


def test_drops_numeric_table() -> None:
    # Lots of numbers, almost no prose -> low alpha ratio.
    table = " ".join(f"{y} {y * 111 % 1000} {y * 37 % 900}" for y in range(2000, 2040))
    assert count_tokens(table) >= MIN_PROSE_TOKENS
    drop, reason = _is_low_value(table)
    assert drop and reason == "low_prose_ratio"


def test_drops_table_of_contents() -> None:
    toc = "\n".join(
        f"Chapter {n} The Conceptual Framework of Accounting ..... {n * 12}"
        for n in range(1, 8)
    )
    assert count_tokens(toc) >= MIN_PROSE_TOKENS
    drop, reason = _is_low_value(toc)
    assert drop and reason in {"toc_or_index", "low_prose_ratio"}


def test_drops_bare_question_stem() -> None:
    stem = (
        "Which of the following statements about the recognition and measurement "
        "of a finance lease by the lessee under ASC 842 is most accurate given "
        "the facts described in the scenario above?\n"
        "A. The lessee records a right-of-use asset\n"
        "B. The lessee expenses all payments\n"
        "C. The lessee records nothing at commencement\n"
        "D. The lessee recognizes only interest\n"
    )
    assert count_tokens(stem) >= MIN_PROSE_TOKENS
    drop, reason = _is_low_value(stem)
    assert drop and reason == "question_stem"
