// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import {
    buildDocReviewSubmission,
    buildJeSubmission,
    buildNumericSubmission,
    buildResearchSubmission,
    buildRevealModel,
    buildTbsModel,
    paneExhibits,
    parseExhibits,
    parseSteps,
    sectionFromTags,
    segmentDocument,
} from "./lib";

test("buildTbsModel parses a JE note without leaking answer keys", () => {
    const stepsJson = JSON.stringify([
        { id: "l1", label: "Line 1", answer_key: { account: "Cash", side: "dr", amount: 1000 } },
        { id: "l2", label: "Line 2", answer_key: { account: "Lease Liability", side: "cr", amount: 1000 } },
    ]);
    const fields = ["journal_entry", "Record the lease.", "[]", stepsJson, "ds::lease"];
    const model = buildTbsModel(fields);
    expect(model.shape).toBe("journal_entry");
    expect(model.prompt).toBe("Record the lease.");
    expect(model.steps).toHaveLength(2);
    // answer_key must not survive into the render model
    expect(JSON.stringify(model.steps)).not.toContain("answer_key");
    expect(JSON.stringify(model.steps)).not.toContain("Cash");
});

test("parseSteps defaults weights to 1/N so totals reconcile with A10", () => {
    const steps = parseSteps(JSON.stringify([
        { id: "a", answer_key: 1 },
        { id: "b", answer_key: 2 },
        { id: "c", answer_key: 3 },
        { id: "d", answer_key: 4 },
    ]));
    expect(steps).toHaveLength(4);
    for (const s of steps) {
        expect(s.weight).toBeCloseTo(0.25, 9);
    }
});

test("parseExhibits tolerates missing / malformed json", () => {
    expect(parseExhibits(undefined)).toEqual([]);
    expect(parseExhibits("not json")).toEqual([]);
    const ex = parseExhibits(JSON.stringify([{ title: "Ex 1", body: "text" }]));
    expect(ex[0].title).toBe("Ex 1");
});

test("buildJeSubmission shapes account/side/amount per step", () => {
    const json = buildJeSubmission([
        { id: "l1", account: "Cash", side: "dr", amount: "1000" },
    ]);
    const parsed = JSON.parse(json);
    expect(parsed.steps[0]).toEqual({
        id: "l1",
        value: { account: "Cash", side: "dr", amount: 1000 },
    });
});

test("buildNumericSubmission coerces numbers per cell", () => {
    const json = buildNumericSubmission([
        { id: "c1", value: "250000" },
        { id: "c2", value: "" },
    ]);
    const parsed = JSON.parse(json);
    expect(parsed.steps[0].value).toBe(250000);
    expect(parsed.steps[1].value).toBe("");
});

// --- Workstream B: section-agnostic surfaces ---------------------------------

test("sectionFromTags reads sec:: tag, falls back to FAR", () => {
    expect(sectionFromTags(["ds::reg::deduct", "sec::REG"])).toBe("REG");
    expect(sectionFromTags(["ds::lease::finance"])).toBe("FAR");
    expect(sectionFromTags(undefined)).toBe("FAR");
    expect(sectionFromTags(["sec::NOPE"])).toBe("FAR");
});

test("parseExhibits reads typed exhibits (kind, table columns/rows, role)", () => {
    const raw = JSON.stringify([
        { title: "Doc", kind: "document", role: "document", body: "x <blank step=\"b1\">y</blank>" },
        { title: "Sched", kind: "table", columns: ["Item", "Amount"], rows: [["Rev", "100"]] },
        { title: "Note" },
    ]);
    const ex = parseExhibits(raw);
    expect(ex[0].kind).toBe("document");
    expect(ex[0].role).toBe("document");
    expect(ex[1].kind).toBe("table");
    expect(ex[1].columns).toEqual(["Item", "Amount"]);
    expect(ex[1].rows).toEqual([["Rev", "100"]]);
    // Unknown/missing kind defaults to text.
    expect(ex[2].kind).toBe("text");
});

test("paneExhibits excludes the doc-review primary document", () => {
    const model = buildTbsModel(
        [
            "doc_review",
            "Review it.",
            JSON.stringify([
                { title: "Exhibit 1", body: "facts" },
                { title: "Doc", kind: "document", role: "document", body: "the <blank step=\"b1\">x</blank>" },
            ]),
            "[]",
            "ds::reg::deduct",
        ],
        ["sec::REG"],
    );
    expect(model.section).toBe("REG");
    expect(model.document).toContain("<blank step=\"b1\">");
    const pane = paneExhibits(model);
    expect(pane).toHaveLength(1);
    expect(pane[0].title).toBe("Exhibit 1");
});

test("parseSteps surfaces doc-review options but NEVER the answer key", () => {
    const stepsJson = JSON.stringify([
        {
            id: "b1",
            kind: "blank",
            label: "Blank 1",
            answer_key: "o2",
            options: [
                { id: "o1", text: "Currently deductible", kind: "replace" },
                { id: "o2", text: "Capitalize and recover", kind: "replace" },
            ],
            confusion_set_id: "reg_capitalize_vs_deduct",
        },
    ]);
    const steps = parseSteps(stepsJson);
    expect(steps[0].options).toHaveLength(2);
    expect(steps[0].options?.[1].text).toBe("Capitalize and recover");
    // The correct-option key must not survive into the render model. (Option ids
    // like "o2" DO appear — they are the label-stripped choices, not the key —
    // so the integrity check is specifically the absence of answer_key.)
    expect(JSON.stringify(steps)).not.toContain("answer_key");
    expect(steps[0]).not.toHaveProperty("answer_key");
});

test("segmentDocument splits text and <blank> markers in order", () => {
    const body = "Freight is [pre]<blank step=\"b1\">capitalized</blank>[mid]<blank step=\"b2\">expensed</blank>[end]";
    const segs = segmentDocument(body);
    // text, blank, text, blank, text
    expect(segs.map((s) => s.type)).toEqual(["text", "blank", "text", "blank", "text"]);
    const b1 = segs[1];
    expect(b1.type === "blank" && b1.blankId).toBe("b1");
    expect(b1.type === "blank" && b1.original).toBe("capitalized");
    expect(segmentDocument(undefined)).toEqual([]);
});

test("buildResearchSubmission emits a single trimmed citation (backend research arm)", () => {
    expect(JSON.parse(buildResearchSubmission("  ASC 842-20-25-1 "))).toEqual({
        citation: "ASC 842-20-25-1",
    });
});

test("buildDocReviewSubmission submits each blank's chosen option id", () => {
    const json = buildDocReviewSubmission([
        { id: "b1", value: "o1" },
        { id: "b2", value: "o2" },
    ]);
    expect(JSON.parse(json)).toEqual({
        steps: [
            { id: "b1", value: "o1" },
            { id: "b2", value: "o2" },
        ],
    });
});

test("buildRevealModel resolves the correct value only from raw fields (post-submit)", () => {
    const fields = [
        "doc_review",
        "Review it.",
        "[]",
        JSON.stringify([
            {
                id: "b1",
                kind: "blank",
                label: "Freight",
                answer_key: "o1",
                options: [
                    { id: "o1", text: "Capitalize", kind: "replace" },
                    { id: "o2", text: "Expense", kind: "replace" },
                ],
            },
        ]),
        "ds::cost::capitalize",
        "ASC 360-10-30-1 (capitalizable cost).",
    ];
    const reveal = buildRevealModel(fields, ["sec::FAR"]);
    expect(reveal.section).toBe("FAR");
    expect(reveal.schemaTag).toBe("ds::cost::capitalize");
    expect(reveal.source).toContain("ASC 360-10-30-1");
    expect(reveal.steps[0].label).toBe("Freight");
    // The option id resolves to its human text for the reveal.
    expect(reveal.steps[0].correctText).toBe("Capitalize");
});

test("buildRevealModel joins a research accepted-citation array", () => {
    const fields = [
        "research",
        "Cite it.",
        "[]",
        JSON.stringify([
            {
                id: "citation",
                kind: "citation",
                label: "Governing citation",
                answer_key: ["ASC 842-20-25-1", "842-20-25-1"],
            },
        ]),
        "ds::lease::operating",
        "ASC 842.",
    ];
    const reveal = buildRevealModel(fields, ["sec::FAR"]);
    expect(reveal.steps[0].correctText).toBe("ASC 842-20-25-1 / 842-20-25-1");
});
