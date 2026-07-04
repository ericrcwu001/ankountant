// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { readableBackendError } from "../../backendError";

export function errorMessage(error: unknown): string {
    return readableBackendError(error, "This workspace surface could not be loaded.");
}

export function isMissingConfigJson(error: unknown, key: string): boolean {
    return errorMessage(error).includes(`No such value: '${key}'`);
}

export function decodeConfigJson<T>(key: string, json: Uint8Array): T {
    try {
        return JSON.parse(new TextDecoder().decode(json)) as T;
    } catch (error) {
        throw new Error(
            `Saved preference "${key}" contains invalid JSON: ${errorMessage(error)}`,
        );
    }
}

export function encodeConfigJson(key: string, value: unknown): Uint8Array {
    try {
        const json = JSON.stringify(value);
        if (json === undefined) {
            throw new Error("value cannot be encoded as JSON");
        }
        return new TextEncoder().encode(json);
    } catch (error) {
        throw new Error(
            `Could not encode saved preference "${key}": ${errorMessage(error)}`,
        );
    }
}
