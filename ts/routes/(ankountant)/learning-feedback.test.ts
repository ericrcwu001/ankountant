// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { afterEach, expect, test, vi } from "vitest";

import {
    learningFeedbackDepthForOutcome,
    type LearningFeedbackRequest,
    maybeGenerateLearningFeedback,
    shouldGenerateLearningFeedback,
} from "./learning-feedback";

afterEach(() => {
    vi.unstubAllGlobals();
});

test("learning feedback disabled state is visible to wrong-answer panels", async () => {
    const fetch = stubFetch([
        {
            enabled: false,
            model: "gpt-5.4-mini",
            apiKeySaved: false,
        },
    ]);

    await expect(maybeGenerateLearningFeedback(request())).rejects.toThrow(
        "AI feedback is disabled.",
    );
    expect(fetch).toHaveBeenCalledTimes(1);
});

test("learning feedback missing key state is visible to wrong-answer panels", async () => {
    const fetch = stubFetch([
        {
            enabled: true,
            model: "gpt-5.4-mini",
            apiKeySaved: false,
        },
    ]);

    await expect(maybeGenerateLearningFeedback(request())).rejects.toThrow(
        "OpenAI API key is not saved.",
    );
    expect(fetch).toHaveBeenCalledTimes(1);
});

test("learning feedback posts generation request when settings are ready", async () => {
    const fetch = stubFetch([
        {
            enabled: true,
            model: "gpt-5.4-mini",
            apiKeySaved: true,
        },
        {
            title: "Evidence sufficiency",
            whyWrong: "The selected treatment conflicts with the source.",
            correctApproach: "Use the stated correct treatment.",
            remember: "Anchor the choice in the source passage.",
            sourceIds: ["source-passage"],
        },
    ]);

    const feedback = await maybeGenerateLearningFeedback(request());

    expect(feedback.title).toBe("Evidence sufficiency");
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(fetch.mock.calls[1][0]).toBe("/_anki/generateAnkountantLearningFeedback");
    expect(decodeFetchBody(fetch.mock.calls[1][1]?.body).feedbackDepth).toBe(
        "extensive",
    );
});

test("learning feedback depth is extensive for guesses and confident misses", () => {
    expect(shouldGenerateLearningFeedback("Guess", "correct")).toBe(true);
    expect(learningFeedbackDepthForOutcome("Guess", "correct")).toBe("extensive");
    expect(learningFeedbackDepthForOutcome("Guess", "incorrect")).toBe(
        "extensive",
    );
    expect(learningFeedbackDepthForOutcome("Confident", "incorrect")).toBe(
        "extensive",
    );
    expect(learningFeedbackDepthForOutcome("Unsure", "incorrect")).toBe("standard");
    expect(shouldGenerateLearningFeedback("Confident", "correct")).toBe(false);
    expect(learningFeedbackDepthForOutcome("Confident", "correct")).toBe("brief");
});

function stubFetch(responses: unknown[]): ReturnType<typeof vi.fn> {
    const fetch = vi.fn(async () => {
        const response = responses.shift();
        if (response === undefined) {
            throw new Error("Unexpected fetch call");
        }
        return {
            ok: true,
            status: 200,
            text: async () => JSON.stringify(response),
        };
    });
    vi.stubGlobal("fetch", fetch);
    return fetch;
}

function decodeFetchBody(body: unknown): LearningFeedbackRequest {
    if (!(body instanceof Uint8Array)) {
        throw new Error("expected Uint8Array fetch body");
    }
    return JSON.parse(new TextDecoder().decode(body)) as LearningFeedbackRequest;
}

function request(): LearningFeedbackRequest {
    return {
        title: "Evidence sufficiency",
        confidence: "Guess",
        outcome: "correct",
        feedbackDepth: "extensive",
        question: "Select the correct treatment.",
        userAnswer: "Insufficient evidence",
        correctAnswer: "Insufficient evidence",
        sources: [
            {
                id: "source-passage",
                title: "Source passage",
                body: "Insufficient evidence is the correct treatment.",
            },
        ],
    };
}
