// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

export const DEFAULT_LEARNING_FEEDBACK_MODEL = "gpt-5.4-mini";

export interface LearningFeedbackSettings {
    enabled: boolean;
    model: string;
    apiKeySaved: boolean;
}

export interface LearningFeedback {
    title: string;
    whyWrong: string;
    correctApproach: string;
    remember: string;
    sourceIds: string[];
}

export type LearningFeedbackConfidence = "Guess" | "Unsure" | "Confident";
export type LearningFeedbackOutcome = "correct" | "incorrect";
export type LearningFeedbackDepth = "brief" | "standard" | "extensive";

export type LearningFeedbackPanelState =
    | { phase: "loading" }
    | { phase: "ready"; feedback: LearningFeedback }
    | { phase: "error"; message: string };

export interface LearningFeedbackRequest {
    title: string;
    confidence: LearningFeedbackConfidence;
    outcome: LearningFeedbackOutcome;
    feedbackDepth: LearningFeedbackDepth;
    question: string;
    userAnswer: string;
    correctAnswer: string;
    sources: LearningFeedbackSource[];
}

export interface LearningFeedbackSource {
    id: string;
    title: string;
    body: string;
}

export async function loadLearningFeedbackSettings(): Promise<LearningFeedbackSettings> {
    const response = await fetchJson(
        "getAnkountantLearningFeedbackSettings",
        new Uint8Array(),
    );
    return decodeLearningFeedbackSettings(response);
}

export async function saveLearningFeedbackSettings(
    settings: Pick<LearningFeedbackSettings, "enabled" | "model">,
): Promise<LearningFeedbackSettings> {
    const response = await fetchJson(
        "setAnkountantLearningFeedbackSettings",
        encodeJson(settings),
    );
    return decodeLearningFeedbackSettings(response);
}

export async function saveLearningFeedbackApiKey(apiKey: string): Promise<void> {
    await postBackend("saveAnkountantLearningFeedbackApiKey", encodeJson({ apiKey }));
}

export async function deleteLearningFeedbackApiKey(): Promise<void> {
    await postBackend("deleteAnkountantLearningFeedbackApiKey", new Uint8Array());
}

export async function maybeGenerateLearningFeedback(
    request: LearningFeedbackRequest,
): Promise<LearningFeedback> {
    const settings = await loadLearningFeedbackSettings();
    if (!settings.enabled) {
        throw new Error(
            "AI feedback is disabled. Turn it on in Settings -> Review Session -> AI feedback.",
        );
    }
    if (!settings.apiKeySaved) {
        throw new Error(
            "OpenAI API key is not saved. Add it in Settings -> Review Session -> AI feedback.",
        );
    }
    const response = await fetchJson("generateAnkountantLearningFeedback", requestBody(request));
    return decodeLearningFeedback(response);
}

export function shouldGenerateLearningFeedback(
    confidence: LearningFeedbackConfidence,
    outcome: LearningFeedbackOutcome,
): boolean {
    return confidence === "Guess" || outcome === "incorrect";
}

export function learningFeedbackDepthForOutcome(
    confidence: LearningFeedbackConfidence,
    outcome: LearningFeedbackOutcome,
): LearningFeedbackDepth {
    if (confidence === "Guess" || (confidence === "Confident" && outcome === "incorrect")) {
        return "extensive";
    }
    return outcome === "correct" ? "brief" : "standard";
}

export function learningFeedbackErrorMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}

function requestBody(request: LearningFeedbackRequest): Uint8Array {
    return encodeJson(request);
}

async function fetchJson(method: string, body: Uint8Array): Promise<unknown> {
    const text = await postBackend(method, body);
    if (text.length === 0) {
        throw new Error(`${method} did not return JSON.`);
    }
    return JSON.parse(text) as unknown;
}

async function postBackend(method: string, body: Uint8Array): Promise<string> {
    const result = await fetch(`/_anki/${method}`, {
        method: "POST",
        headers: { "Content-Type": "application/binary" },
        body,
    });
    if (!result.ok) {
        throw new Error(`${result.status}: ${await result.text()}`);
    }
    return await result.text();
}

function encodeJson(value: unknown): Uint8Array {
    return new TextEncoder().encode(JSON.stringify(value));
}

function decodeLearningFeedbackSettings(value: unknown): LearningFeedbackSettings {
    if (!isRecord(value)) {
        throw new Error("Learning feedback settings response must be an object.");
    }
    return {
        enabled: requireBoolean(value, "enabled"),
        model: requireString(value, "model"),
        apiKeySaved: requireBoolean(value, "apiKeySaved"),
    };
}

function decodeLearningFeedback(value: unknown): LearningFeedback {
    if (!isRecord(value)) {
        throw new Error("Learning feedback response must be an object.");
    }
    return {
        title: requireString(value, "title"),
        whyWrong: requireString(value, "whyWrong"),
        correctApproach: requireString(value, "correctApproach"),
        remember: requireString(value, "remember"),
        sourceIds: requireStringArray(value, "sourceIds"),
    };
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireBoolean(value: Record<string, unknown>, key: string): boolean {
    const field = value[key];
    if (typeof field !== "boolean") {
        throw new Error(`${key} must be a boolean.`);
    }
    return field;
}

function requireString(value: Record<string, unknown>, key: string): string {
    const field = value[key];
    if (typeof field !== "string") {
        throw new Error(`${key} must be a string.`);
    }
    return field;
}

function requireStringArray(value: Record<string, unknown>, key: string): string[] {
    const field = value[key];
    if (!Array.isArray(field) || field.some((item) => typeof item !== "string")) {
        throw new Error(`${key} must be a string array.`);
    }
    return field;
}
