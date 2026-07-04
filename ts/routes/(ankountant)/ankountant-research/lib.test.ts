// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { corpusForSection, searchCorpus } from "./lib";

test("corpusForSection returns per-section passages (both licensing kinds)", () => {
    const far = corpusForSection("FAR");
    expect(far.length).toBeGreaterThan(0);
    expect(corpusForSection(" far ")).toEqual(far);
    // FASB ASC (FAR) is cite-only: paraphrase + deep link, never verbatim.
    expect(far.every((e) => e.verbatim === false)).toBe(true);
    expect(far.every((e) => (e.deepLink ?? "").includes("asc.fasb.org"))).toBe(true);

    // REG bundles real verbatim IRC text.
    const reg = corpusForSection("REG");
    expect(reg.some((e) => e.verbatim && e.citation.includes("162"))).toBe(true);

    expect(() => corpusForSection("NOPE")).toThrow(/Unknown CPA section: NOPE/);
});

test("searchCorpus does a client-side substring/keyword match over the section", () => {
    const far = corpusForSection("FAR");
    // empty query browses everything
    expect(searchCorpus(far, "")).toHaveLength(far.length);
    // citation match
    expect(searchCorpus(far, "842-20-25-1").some((e) => e.citation.includes("842-20-25-1"))).toBe(
        true,
    );
    // keyword over body/title (all terms must match)
    const lease = searchCorpus(far, "lease commencement");
    expect(lease.some((e) => e.citation === "ASC 842-20-25-1")).toBe(true);
    // no match
    expect(searchCorpus(far, "zzz-not-a-cite")).toHaveLength(0);
});
