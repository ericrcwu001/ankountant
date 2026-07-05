# Copyright: Ankitects Pty Ltd and contributors
# License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from collections.abc import Callable, MutableMapping
from html.parser import HTMLParser
from typing import Any

DEFAULT_LEARNING_FEEDBACK_MODEL = "gpt-5.4-mini"
LEARNING_FEEDBACK_ENDPOINT = "https://api.openai.com/v1/responses"
MAXIMUM_LEARNING_FEEDBACK_OUTPUT_TOKENS = 1536

ENABLED_PROFILE_KEY = "ankountant.learningFeedback.enabled"
MODEL_PROFILE_KEY = "ankountant.learningFeedback.model"
OPENAI_API_KEY_PROFILE_KEY = "ankountant.learningFeedback.openAIAPIKey"

REQUIRED_FEEDBACK_FIELDS = (
    "title",
    "whyWrong",
    "correctApproach",
    "remember",
    "sourceIds",
)
LEARNING_FEEDBACK_DEPTHS = {"brief", "standard", "extensive"}
LEARNING_FEEDBACK_OUTCOMES = {"correct", "incorrect"}

OpenAITransport = Callable[[str, dict[str, Any]], dict[str, Any]]


class LearningFeedbackError(ValueError):
    pass


def get_learning_feedback_settings(profile: MutableMapping[str, Any]) -> dict[str, Any]:
    return {
        "enabled": _profile_enabled(profile),
        "model": _profile_model(profile),
        "apiKeySaved": _profile_api_key(profile) != "",
    }


def set_learning_feedback_settings(
    profile: MutableMapping[str, Any], payload: object
) -> dict[str, Any]:
    data = _require_object(payload, "learning feedback settings payload")
    model = _require_str(data, "model").strip()
    if not model:
        raise LearningFeedbackError("model must not be empty")

    profile[ENABLED_PROFILE_KEY] = _require_bool(data, "enabled")
    profile[MODEL_PROFILE_KEY] = model
    return get_learning_feedback_settings(profile)


def save_learning_feedback_api_key(
    profile: MutableMapping[str, Any], payload: object
) -> dict[str, Any]:
    data = _require_object(payload, "OpenAI API key payload")
    api_key = _require_str(data, "apiKey").strip()
    if not api_key:
        raise LearningFeedbackError("apiKey must not be empty")

    profile[OPENAI_API_KEY_PROFILE_KEY] = api_key
    return get_learning_feedback_settings(profile)


def delete_learning_feedback_api_key(
    profile: MutableMapping[str, Any],
) -> dict[str, Any]:
    profile.pop(OPENAI_API_KEY_PROFILE_KEY, None)
    return get_learning_feedback_settings(profile)


def generate_learning_feedback(
    profile: MutableMapping[str, Any],
    payload: object,
    transport: OpenAITransport | None = None,
) -> dict[str, Any]:
    if not _profile_enabled(profile):
        raise LearningFeedbackError("learning feedback is disabled")

    model = _profile_model(profile)
    if not model:
        raise LearningFeedbackError("OpenAI feedback model is empty")

    api_key = _profile_api_key(profile)
    if not api_key:
        raise LearningFeedbackError("OpenAI API key is not saved")

    request_payload = validate_learning_feedback_request(payload)
    openai_payload = build_openai_responses_payload(model, request_payload)
    openai_response = (transport or post_openai_responses)(api_key, openai_payload)
    output_text = extract_openai_output_text(openai_response)
    return validate_learning_feedback_response(output_text, request_payload)


def build_reviewer_learning_feedback_request(
    *,
    question_html: str,
    answer_html: str,
    note_fields: list[tuple[str, str]],
    ease: int,
    typed_answer: str | None,
    confidence: str | None,
) -> dict[str, Any]:
    question = text_from_html(question_html)
    correct_answer = text_from_html(answer_html)
    user_answer = reviewer_user_answer(ease, typed_answer, confidence)
    sources = [
        {"id": "card-front", "title": "Card front", "body": question},
        {"id": "card-back", "title": "Card back", "body": correct_answer},
    ]
    for index, (name, value) in enumerate(note_fields):
        body = text_from_html(value)
        if body:
            sources.append(
                {
                    "id": f"field-{index + 1}-{source_id_fragment(name)}",
                    "title": name,
                    "body": body,
                }
            )

    return validate_learning_feedback_request(
        {
            "title": "Review feedback",
            "confidence": confidence.strip() if confidence else "Unspecified",
            "outcome": reviewer_feedback_outcome(ease),
            "feedbackDepth": reviewer_feedback_depth(ease, confidence),
            "question": question,
            "userAnswer": user_answer,
            "correctAnswer": correct_answer,
            "sources": sources,
        }
    )


def reviewer_user_answer(
    ease: int, typed_answer: str | None, confidence: str | None
) -> str:
    pieces = [f"Rated {reviewer_rating_label(ease)}"]
    if typed_answer and typed_answer.strip():
        pieces.append(f"Typed answer: {text_from_html(typed_answer)}")
    if confidence and confidence.strip():
        pieces.append(f"Confidence: {confidence.strip()}")
    return "\n".join(pieces)


def reviewer_feedback_outcome(ease: int) -> str:
    reviewer_rating_label(ease)
    return "correct" if ease in (3, 4) else "incorrect"


def reviewer_feedback_depth(ease: int, confidence: str | None) -> str:
    normalized_confidence = confidence.strip().lower() if confidence else ""
    outcome = reviewer_feedback_outcome(ease)
    if normalized_confidence == "guess" or (
        normalized_confidence == "confident" and outcome == "incorrect"
    ):
        return "extensive"
    return "brief" if outcome == "correct" else "standard"


def reviewer_rating_label(ease: int) -> str:
    labels = {1: "Again", 2: "Hard", 3: "Good", 4: "Easy"}
    try:
        return labels[ease]
    except KeyError as exc:
        raise LearningFeedbackError(f"unknown reviewer ease: {ease}") from exc


def validate_learning_feedback_request(payload: object) -> dict[str, Any]:
    data = _require_object(payload, "learning feedback request payload")
    allowed_keys = {
        "title",
        "confidence",
        "outcome",
        "feedbackDepth",
        "question",
        "userAnswer",
        "correctAnswer",
        "sources",
    }
    unexpected_keys = set(data) - allowed_keys
    if unexpected_keys:
        raise LearningFeedbackError(
            "learning feedback request has unexpected fields: "
            + ", ".join(sorted(unexpected_keys))
        )

    sources = _require_list(data, "sources")
    if not sources:
        raise LearningFeedbackError("sources must not be empty")

    validated_sources = []
    source_ids = set()
    for index, source in enumerate(sources):
        source_data = _require_object(source, f"sources[{index}]")
        allowed_source_keys = {"id", "title", "body"}
        unexpected_source_keys = set(source_data) - allowed_source_keys
        if unexpected_source_keys:
            raise LearningFeedbackError(
                f"sources[{index}] has unexpected fields: "
                + ", ".join(sorted(unexpected_source_keys))
            )

        source_id = _require_str(source_data, "id").strip()
        title = _require_str(source_data, "title").strip()
        body = _require_str(source_data, "body").strip()
        if not source_id:
            raise LearningFeedbackError(f"sources[{index}].id must not be empty")
        if not body:
            raise LearningFeedbackError(f"sources[{index}].body must not be empty")
        if source_id in source_ids:
            raise LearningFeedbackError(f"duplicate source id: {source_id}")
        source_ids.add(source_id)
        validated_sources.append({"id": source_id, "title": title, "body": body})

    correct_answer = _require_str(data, "correctAnswer").strip()
    if not correct_answer:
        raise LearningFeedbackError("correctAnswer must not be empty")

    confidence = _require_str(data, "confidence").strip()
    if not confidence:
        raise LearningFeedbackError("confidence must not be empty")

    return {
        "title": _require_str(data, "title").strip(),
        "confidence": confidence,
        "outcome": _require_choice(data, "outcome", LEARNING_FEEDBACK_OUTCOMES),
        "feedbackDepth": _require_choice(
            data, "feedbackDepth", LEARNING_FEEDBACK_DEPTHS
        ),
        "question": _require_str(data, "question").strip(),
        "userAnswer": _require_str(data, "userAnswer").strip(),
        "correctAnswer": correct_answer,
        "sources": validated_sources,
    }


def build_openai_responses_payload(
    model: str, request_payload: dict[str, Any]
) -> dict[str, Any]:
    return {
        "model": model,
        "input": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": learning_feedback_input_text(request_payload),
                    }
                ],
            }
        ],
        "store": False,
        "max_output_tokens": MAXIMUM_LEARNING_FEEDBACK_OUTPUT_TOKENS,
        "reasoning": {"effort": "low"},
        "text": {"format": learning_feedback_text_format()},
    }


def learning_feedback_input_text(request_payload: dict[str, Any]) -> str:
    request_json = json.dumps(
        request_payload, ensure_ascii=False, separators=(",", ":")
    )
    return "\n".join(
        [
            "Generate learning feedback for this review request.",
            "Return JSON matching the schema exactly.",
            "Ground every substantive claim in the correctAnswer or sources.",
            "Do not introduce facts, rules, numbers, or citations that are not present in the request.",
            "If the request lacks enough evidence, keep the feedback narrow and say only what the revealed answer and sources support.",
            "Use the request confidence, outcome, and feedbackDepth when deciding how much explanation to provide.",
            "If outcome is correct, do not claim the answer was wrong; use whyWrong for the uncertainty or reasoning gap that still needs review.",
            learning_feedback_depth_instruction(request_payload["feedbackDepth"]),
            "Use sourceIds only from the request sources.",
            "",
            "Request:",
            request_json,
        ]
    )


def learning_feedback_depth_instruction(feedback_depth: str) -> str:
    if feedback_depth == "brief":
        return "Depth brief: keep each text field to one direct sentence."
    if feedback_depth == "standard":
        return "Depth standard: give concise teaching feedback with the main error, corrected reasoning, and memory cue."
    if feedback_depth == "extensive":
        return "Depth extensive: give richer teaching feedback with a diagnosis of the uncertainty or misconception, a step-by-step correction, and a durable memory cue."
    raise LearningFeedbackError(f"unknown feedbackDepth: {feedback_depth}")


def learning_feedback_text_format() -> dict[str, Any]:
    text_property = {"type": "string", "minLength": 1}
    return {
        "type": "json_schema",
        "name": "learning_feedback",
        "strict": True,
        "schema": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "title": text_property,
                "whyWrong": text_property,
                "correctApproach": text_property,
                "remember": text_property,
                "sourceIds": {
                    "type": "array",
                    "items": text_property,
                    "minItems": 1,
                },
            },
            "required": list(REQUIRED_FEEDBACK_FIELDS),
        },
    }


def post_openai_responses(
    api_key: str,
    payload: dict[str, Any],
    endpoint: str = LEARNING_FEEDBACK_ENDPOINT,
) -> dict[str, Any]:
    request_body = json.dumps(payload).encode("utf8")
    request = urllib.request.Request(
        endpoint,
        data=request_body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            response_body = response.read()
            status = response.status
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf8", errors="replace")
        raise LearningFeedbackError(
            f"OpenAI Responses request failed with status {exc.code}: {body}"
        ) from exc
    except urllib.error.URLError as exc:
        raise LearningFeedbackError(
            f"OpenAI Responses request failed: {exc.reason}"
        ) from exc

    if not 200 <= status < 300:
        raise LearningFeedbackError(
            f"OpenAI Responses request failed with status {status}"
        )

    try:
        decoded = json.loads(response_body.decode("utf8"))
    except json.JSONDecodeError as exc:
        raise LearningFeedbackError(f"OpenAI response JSON is invalid: {exc}") from exc
    if not isinstance(decoded, dict):
        raise LearningFeedbackError("OpenAI response JSON must be an object")
    return decoded


def extract_openai_output_text(response: dict[str, Any]) -> str:
    _validate_openai_response_status(response)
    output = _require_openai_output(response)
    for item in output:
        for content_item in _openai_content_items(item):
            output_text = _openai_output_text(content_item)
            if output_text is not None:
                return output_text

    raise LearningFeedbackError("OpenAI response did not include output text")


def _validate_openai_response_status(response: dict[str, Any]) -> None:
    if response.get("status") not in (None, "completed"):
        raise LearningFeedbackError(
            f"OpenAI response status was {response.get('status')}"
        )
    if response.get("error"):
        raise LearningFeedbackError(f"OpenAI response error: {response['error']}")


def _require_openai_output(response: dict[str, Any]) -> list[Any]:
    output = response.get("output")
    if not isinstance(output, list):
        raise LearningFeedbackError("OpenAI response output must be an array")
    return output


def _openai_content_items(item: object) -> list[object]:
    if not isinstance(item, dict):
        return []
    content = item.get("content")
    if not isinstance(content, list):
        return []
    return content


def _openai_output_text(content_item: object) -> str | None:
    if not isinstance(content_item, dict):
        return None
    if content_item.get("type") != "output_text":
        return None
    text = content_item.get("text")
    if not isinstance(text, str) or not text.strip():
        return None
    return text.strip()


def validate_learning_feedback_response(
    output_text: str, request_payload: dict[str, Any]
) -> dict[str, Any]:
    feedback = _decode_feedback_json(output_text)
    _validate_feedback_keys(feedback)
    _validate_feedback_text_fields(feedback)
    normalized_source_ids = _validate_feedback_source_ids(
        feedback["sourceIds"], request_payload
    )
    return {
        "title": feedback["title"].strip(),
        "whyWrong": feedback["whyWrong"].strip(),
        "correctApproach": feedback["correctApproach"].strip(),
        "remember": feedback["remember"].strip(),
        "sourceIds": normalized_source_ids,
    }


def _decode_feedback_json(output_text: str) -> dict[str, Any]:
    try:
        feedback = json.loads(output_text)
    except json.JSONDecodeError as exc:
        raise LearningFeedbackError(f"feedback JSON is invalid: {exc}") from exc

    if not isinstance(feedback, dict):
        raise LearningFeedbackError("feedback JSON must be an object")
    return feedback


def _validate_feedback_keys(feedback: dict[str, Any]) -> None:
    feedback_keys = set(feedback)
    required_keys = set(REQUIRED_FEEDBACK_FIELDS)
    missing_keys = required_keys - feedback_keys
    unexpected_keys = feedback_keys - required_keys
    if missing_keys:
        raise LearningFeedbackError(
            "feedback JSON is missing fields: " + ", ".join(sorted(missing_keys))
        )
    if unexpected_keys:
        raise LearningFeedbackError(
            "feedback JSON has unexpected fields: " + ", ".join(sorted(unexpected_keys))
        )


def _validate_feedback_text_fields(feedback: dict[str, Any]) -> None:
    for field in REQUIRED_FEEDBACK_FIELDS[:-1]:
        value = feedback[field]
        if not isinstance(value, str):
            raise LearningFeedbackError(f"{field} must be a string")
        if not value.strip():
            raise LearningFeedbackError(f"{field} must not be empty")


def _validate_feedback_source_ids(
    source_ids: object, request_payload: dict[str, Any]
) -> list[str]:
    if not isinstance(source_ids, list):
        raise LearningFeedbackError("sourceIds must be an array")
    if request_payload["sources"] and not source_ids:
        raise LearningFeedbackError("Feedback must include at least one source ID")

    valid_source_ids = {source["id"] for source in request_payload["sources"]}
    seen_source_ids = set()
    normalized_source_ids = []
    for index, source_id in enumerate(source_ids):
        if not isinstance(source_id, str):
            raise LearningFeedbackError(f"sourceIds[{index}] must be a string")
        normalized_source_id = source_id.strip()
        if not normalized_source_id:
            raise LearningFeedbackError(f"sourceIds[{index}] must not be empty")
        if normalized_source_id not in valid_source_ids:
            raise LearningFeedbackError(
                f"Feedback referenced unknown source ID: {normalized_source_id}"
            )
        if normalized_source_id in seen_source_ids:
            raise LearningFeedbackError(
                f"Feedback repeated source ID: {normalized_source_id}"
            )
        seen_source_ids.add(normalized_source_id)
        normalized_source_ids.append(normalized_source_id)

    return normalized_source_ids


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.skip_depth = 0

    def handle_starttag(self, tag: str, _attrs: list[tuple[str, str | None]]) -> None:
        if tag in ("script", "style"):
            self.skip_depth += 1
        elif tag in ("br", "div", "p", "li", "tr"):
            self.parts.append(" ")

    def handle_endtag(self, tag: str) -> None:
        if tag in ("script", "style") and self.skip_depth:
            self.skip_depth -= 1
        elif tag in ("div", "p", "li", "tr"):
            self.parts.append(" ")

    def handle_data(self, data: str) -> None:
        if not self.skip_depth:
            self.parts.append(data)

    def text(self) -> str:
        return with_collapsed_whitespace(" ".join(self.parts))


def text_from_html(value: str) -> str:
    extractor = TextExtractor()
    extractor.feed(value)
    extractor.close()
    return extractor.text()


def with_collapsed_whitespace(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def source_id_fragment(value: str) -> str:
    fragment = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return fragment or "field"


def _profile_enabled(profile: MutableMapping[str, Any]) -> bool:
    value = profile.get(ENABLED_PROFILE_KEY, False)
    if not isinstance(value, bool):
        raise LearningFeedbackError(
            "stored learning feedback enabled flag must be a boolean"
        )
    return value


def _profile_model(profile: MutableMapping[str, Any]) -> str:
    model = profile.get(MODEL_PROFILE_KEY, DEFAULT_LEARNING_FEEDBACK_MODEL)
    if not isinstance(model, str):
        raise LearningFeedbackError("stored learning feedback model must be a string")
    return model.strip()


def _profile_api_key(profile: MutableMapping[str, Any]) -> str:
    api_key = profile.get(OPENAI_API_KEY_PROFILE_KEY, "")
    if not isinstance(api_key, str):
        raise LearningFeedbackError("stored OpenAI API key must be a string")
    return api_key.strip()


def _require_object(value: object, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise LearningFeedbackError(f"{name} must be an object")
    return value


def _require_list(data: dict[str, Any], key: str) -> list[Any]:
    if key not in data:
        raise LearningFeedbackError(f"{key} is required")
    value = data[key]
    if not isinstance(value, list):
        raise LearningFeedbackError(f"{key} must be an array")
    return value


def _require_bool(data: dict[str, Any], key: str) -> bool:
    if key not in data:
        raise LearningFeedbackError(f"{key} is required")
    value = data[key]
    if not isinstance(value, bool):
        raise LearningFeedbackError(f"{key} must be a boolean")
    return value


def _require_str(data: dict[str, Any], key: str) -> str:
    if key not in data:
        raise LearningFeedbackError(f"{key} is required")
    value = data[key]
    if not isinstance(value, str):
        raise LearningFeedbackError(f"{key} must be a string")
    return value


def _require_choice(data: dict[str, Any], key: str, choices: set[str]) -> str:
    value = _require_str(data, key).strip()
    if value not in choices:
        raise LearningFeedbackError(
            f"{key} must be one of: {', '.join(sorted(choices))}"
        )
    return value
