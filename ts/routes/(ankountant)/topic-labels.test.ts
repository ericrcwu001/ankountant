// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { schemaTagLabel, topicLabel, topicSentenceLabel } from "./topic-labels";

test("topic labels use CPA terminology", () => {
    expect(topicLabel("government_nfp")).toBe("Government & NFP");
    expect(topicLabel("trading_afs_htm")).toBe("Trading, AFS & HTM securities");
    expect(topicLabel("aud_request_relevance")).toBe("Request relevance");
});

test("topic sentence labels preserve acronyms", () => {
    expect(topicSentenceLabel("tax_timing")).toBe("tax timing");
    expect(topicSentenceLabel("trading_afs_htm")).toBe("trading, AFS & HTM securities");
});

test("schema tag labels hide internal taxonomy tags", () => {
    expect(schemaTagLabel("ds::tax::permanent")).toBe("Permanent items");
    expect(schemaTagLabel("ds::securities::htm")).toBe("HTM securities");
    expect(schemaTagLabel("ds::custom::odd_case")).toBe("Odd case");
});
