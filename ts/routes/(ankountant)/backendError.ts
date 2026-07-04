// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

function decodeHtmlEntities(text: string): string {
    return text
        .replace(/&#39;/g, "'")
        .replace(/&quot;/g, "\"")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">");
}

export function readableBackendError(error: unknown, fallback: string): string {
    const raw = error instanceof Error ? error.message : String(error);
    const trimmed = raw.trim();
    if (trimmed === "") {
        return fallback;
    }
    const hasHtml = /<[^>]+>/.test(trimmed);
    if (!hasHtml) {
        return trimmed;
    }
    const title = trimmed.match(/<title[^>]*>(.*?)<\/title>/is)?.[1]
        ?? trimmed.match(/<h1[^>]*>(.*?)<\/h1>/is)?.[1]
        ?? "";
    const decodedTitle = decodeHtmlEntities(title.replace(/<[^>]+>/g, " "))
        .replace(/\s+/g, " ")
        .trim();
    const status = trimmed.match(/\b([45]\d\d)\b/)?.[1] ?? "";
    const titleWithoutStatus = status === ""
        ? decodedTitle
        : decodedTitle.replace(new RegExp(`^${status}\\s*`), "").trim();
    const prefix = [status, titleWithoutStatus].filter(Boolean).join(" ");
    return prefix === "" ? fallback : `${prefix}. ${fallback}`;
}
