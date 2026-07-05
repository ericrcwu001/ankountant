# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

from __future__ import annotations

import json
from typing import Any

import pytest

from aqt.ankountant_learning_feedback import (
    DEFAULT_LEARNING_FEEDBACK_MODEL,
    LearningFeedbackError,
    build_reviewer_learning_feedback_request,
    delete_learning_feedback_api_key,
    generate_learning_feedback,
    get_learning_feedback_settings,
    save_learning_feedback_api_key,
    set_learning_feedback_settings,
    validate_learning_feedback_request,
    validate_learning_feedback_response,
)


def test_learning_feedback_settings_default_and_profile_updates() -> None:
    profile: dict[str, Any] = {}

    assert get_learning_feedback_settings(profile) == {
        "enabled": False,
        "model": DEFAULT_LEARNING_FEEDBACK_MODEL,
        "apiKeySaved": False,
    }

    settings = set_learning_feedback_settings(
        profile, {"enabled": True, "model": " gpt-5.4-mini "}
    )
    assert settings == {
        "enabled": True,
        "model": "gpt-5.4-mini",
        "apiKeySaved": False,
    }

    settings = save_learning_feedback_api_key(profile, {"apiKey": " sk-test "})
    assert settings["apiKeySaved"] is True

    settings = delete_learning_feedback_api_key(profile)
    assert settings["apiKeySaved"] is False


def test_generate_learning_feedback_builds_strict_openai_request() -> None:
    profile = {
        "ankountant.learningFeedback.enabled": True,
        "ankountant.learningFeedback.model": "gpt-5.4-mini",
        "ankountant.learningFeedback.openAIAPIKey": "sk-test",
    }
    captured: dict[str, Any] = {}

    def transport(api_key: str, payload: dict[str, Any]) -> dict[str, Any]:
        captured["apiKey"] = api_key
        captured["payload"] = payload
        feedback = {
            "title": "Lease classification",
            "whyWrong": "The selected treatment conflicts with the revealed answer.",
            "correctApproach": "Use the supplied lease criteria from the card back.",
            "remember": "Anchor the answer in the revealed rule before choosing.",
            "sourceIds": ["review-back"],
        }
        return {
            "output": [
                {
                    "content": [
                        {
                            "type": "output_text",
                            "text": json.dumps(feedback),
                        }
                    ]
                }
            ]
        }

    feedback = generate_learning_feedback(profile, _request_payload(), transport)

    assert captured["apiKey"] == "sk-test"
    openai_payload = captured["payload"]
    assert openai_payload["model"] == "gpt-5.4-mini"
    assert openai_payload["store"] is False
    assert openai_payload["max_output_tokens"] == 1536
    assert openai_payload["text"]["format"]["type"] == "json_schema"
    assert openai_payload["text"]["format"]["strict"] is True
    assert openai_payload["text"]["format"]["schema"]["required"] == [
        "title",
        "whyWrong",
        "correctApproach",
        "remember",
        "sourceIds",
    ]
    assert "Depth extensive" in openai_payload["input"][0]["content"][0]["text"]
    assert feedback["sourceIds"] == ["review-back"]


def test_learning_feedback_request_requires_sources_with_ids_and_body() -> None:
    payload = _request_payload()
    payload["sources"] = [{"id": "", "title": "Card Back", "body": "Correct answer"}]

    with pytest.raises(LearningFeedbackError, match=r"sources\[0\]\.id"):
        validate_learning_feedback_request(payload)

    payload = _request_payload()
    payload["sources"] = [{"id": "review-back", "title": "Card Back", "body": "  "}]

    with pytest.raises(LearningFeedbackError, match=r"sources\[0\]\.body"):
        validate_learning_feedback_request(payload)


def test_learning_feedback_request_rejects_invalid_depth_or_outcome() -> None:
    payload = _request_payload()
    payload["feedbackDepth"] = "long"

    with pytest.raises(LearningFeedbackError, match="feedbackDepth"):
        validate_learning_feedback_request(payload)

    payload = _request_payload()
    payload["outcome"] = "partial"

    with pytest.raises(LearningFeedbackError, match="outcome"):
        validate_learning_feedback_request(payload)


def test_learning_feedback_response_rejects_unknown_or_empty_source_ids() -> None:
    request_payload = validate_learning_feedback_request(_request_payload())
    feedback = {
        "title": "Lease classification",
        "whyWrong": "The answer did not match the supplied material.",
        "correctApproach": "Use the provided card back.",
        "remember": "Use the cited source.",
        "sourceIds": ["unknown"],
    }

    with pytest.raises(LearningFeedbackError, match="unknown source ID"):
        validate_learning_feedback_response(json.dumps(feedback), request_payload)

    feedback["sourceIds"] = [""]
    with pytest.raises(LearningFeedbackError, match=r"sourceIds\[0\]"):
        validate_learning_feedback_response(json.dumps(feedback), request_payload)


def test_generate_learning_feedback_fails_when_disabled_or_missing_key() -> None:
    profile = {"ankountant.learningFeedback.enabled": False}

    with pytest.raises(LearningFeedbackError, match="disabled"):
        generate_learning_feedback(
            profile, _request_payload(), lambda _key, _payload: {}
        )

    profile = {"ankountant.learningFeedback.enabled": True}

    with pytest.raises(LearningFeedbackError, match="API key"):
        generate_learning_feedback(
            profile, _request_payload(), lambda _key, _payload: {}
        )


def test_reviewer_feedback_request_strips_html_and_uses_card_sources() -> None:
    payload = build_reviewer_learning_feedback_request(
        question_html="<div>Basis?</div><script>bad()</script>",
        answer_html="<p>Adjusted basis</p><br><p>Amount realized</p>",
        note_fields=[
            ("Topic", "<b>Basis vs amount realized</b>"),
            ("Empty", " "),
        ],
        ease=1,
        typed_answer="<span>Original cost</span>",
        confidence="low",
    )

    assert payload["question"] == "Basis?"
    assert payload["correctAnswer"] == "Adjusted basis Amount realized"
    assert payload["confidence"] == "low"
    assert payload["outcome"] == "incorrect"
    assert payload["feedbackDepth"] == "standard"
    assert (
        payload["userAnswer"]
        == "Rated Again\nTyped answer: Original cost\nConfidence: low"
    )
    assert payload["sources"] == [
        {"id": "card-front", "title": "Card front", "body": "Basis?"},
        {
            "id": "card-back",
            "title": "Card back",
            "body": "Adjusted basis Amount realized",
        },
        {
            "id": "field-1-topic",
            "title": "Topic",
            "body": "Basis vs amount realized",
        },
    ]


def _request_payload() -> dict[str, Any]:
    return {
        "title": "Review feedback",
        "confidence": "Guess",
        "outcome": "incorrect",
        "feedbackDepth": "extensive",
        "question": "Which treatment applies?",
        "userAnswer": "Operating lease",
        "correctAnswer": "Finance lease",
        "sources": [
            {
                "id": "review-front",
                "title": "Card Front",
                "body": "Which treatment applies?",
            },
            {
                "id": "review-back",
                "title": "Card Back",
                "body": "Finance lease",
            },
        ],
    }
