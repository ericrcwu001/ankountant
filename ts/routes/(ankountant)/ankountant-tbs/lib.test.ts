// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import {
    ALL_SECTIONS,
    buildDocReviewSubmission,
    buildJeSubmission,
    buildNumericSubmission,
    buildResearchSubmission,
    buildRevealModel,
    buildTbsModel,
    paneExhibits,
    parseExhibits,
    parseSteps,
    renderableTbsShape,
    SECTION_SEARCH_ORDER,
    sectionChoiceFromModel,
    sectionChoiceLabel,
    sectionChoiceSearchOrder,
    sectionFromTags,
    SECTIONS,
    sectionSearchOrder,
    segmentDocument,
    TBS_SECTION_CHOICES,
    tbsSearch,
    tbsShapeSearchOrder,
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

test("tbsSearch pins both task shape and section", () => {
    expect(tbsSearch("journal_entry", "FAR")).toBe(
        `"note:Ankountant TBS" "tbs_type:journal_entry" deck:Ankountant::Sealed::FAR::*`,
    );
    expect(tbsSearch("numeric", "REG")).toContain(`"tbs_type:numeric"`);
    expect(tbsSearch("numeric", "REG")).toContain("Ankountant::Sealed::REG::*");
});

test("tbsShapeSearchOrder starts with the requested shape", () => {
    expect(tbsShapeSearchOrder("research")).toEqual([
        "research",
        "journal_entry",
        "numeric",
        "doc_review",
    ]);
    expect(tbsShapeSearchOrder("journal_entry")).toEqual([
        "journal_entry",
        "numeric",
        "research",
        "doc_review",
    ]);
});

test("SECTION_SEARCH_ORDER prefers FAR while covering every section", () => {
    expect(SECTION_SEARCH_ORDER[0]).toBe("FAR");
    expect([...SECTION_SEARCH_ORDER].sort()).toEqual([...SECTIONS].sort());
});

test("sectionSearchOrder honors explicit sections and otherwise scans all", () => {
    expect(sectionSearchOrder("REG")).toEqual(["REG"]);
    expect(sectionSearchOrder(" bar ")).toEqual(["BAR"]);
    expect(sectionSearchOrder(null)).toEqual(SECTION_SEARCH_ORDER);
    expect(sectionSearchOrder("")).toEqual(SECTION_SEARCH_ORDER);
    expect(() => sectionSearchOrder("NOPE")).toThrow(/Unknown CPA section: NOPE/);
});

test("section choices expose all sections plus direct section scopes", () => {
    expect(TBS_SECTION_CHOICES).toEqual([ALL_SECTIONS, ...SECTION_SEARCH_ORDER]);
    expect(sectionChoiceSearchOrder(ALL_SECTIONS)).toEqual(SECTION_SEARCH_ORDER);
    expect(sectionChoiceSearchOrder("BAR")).toEqual(["BAR"]);
    expect(sectionChoiceFromModel(" bar ")).toBe("BAR");
    expect(sectionChoiceFromModel(undefined)).toBe(ALL_SECTIONS);
    expect(() => sectionChoiceFromModel("NOPE")).toThrow(/Unknown CPA section: NOPE/);
    expect(sectionChoiceLabel(ALL_SECTIONS)).toBe("All sections");
});

test("renderableTbsShape rejects specialized research and doc-review shapes", () => {
    expect(renderableTbsShape("journal_entry")).toBe("journal_entry");
    expect(renderableTbsShape("numeric")).toBe("numeric");
    expect(() => renderableTbsShape("research")).toThrow(/specialized research surface/);
    expect(() => renderableTbsShape("doc_review")).toThrow(/specialized doc_review surface/);
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

test("parseExhibits fails loudly on missing or malformed json", () => {
    expect(parseExhibits("[]")).toEqual([]);
    expect(() => parseExhibits(undefined)).toThrow(/exhibits_json is missing/);
    expect(() => parseExhibits("not json")).toThrow(/Invalid exhibits_json/);
    expect(() => parseExhibits("{}")).toThrow(/exhibits_json must be an array/);
    const ex = parseExhibits(JSON.stringify([{ title: "Ex 1", body: "text" }]));
    expect(ex[0].title).toBe("Ex 1");
});

test("parseSteps fails loudly on missing, malformed, or empty step json", () => {
    expect(() => parseSteps(undefined)).toThrow(/steps_json is missing/);
    expect(() => parseSteps("not json")).toThrow(/Invalid steps_json/);
    expect(() => parseSteps("{}")).toThrow(/steps_json must be an array/);
    expect(() => parseSteps("[]")).toThrow(/steps_json must contain at least one step/);
});

test("buildJeSubmission shapes account/side/amount per step", () => {
    const json = buildJeSubmission([
        { id: "l1", account: "Cash", side: "dr", amount: " 1000.50 " },
        { id: "l2", account: "Interest Expense", side: "dr", amount: "" },
        { id: "l3", account: "Cash", side: "cr", amount: "invalid", noEntry: true },
    ]);
    const parsed = JSON.parse(json);
    expect(parsed.steps[0]).toEqual({
        id: "l1",
        value: { account: "Cash", side: "dr", amount: 1000.5 },
    });
    expect(parsed.steps[1].value.amount).toBe("");
    expect(parsed.steps[2].value).toEqual({ account: "", side: "", amount: "" });
});

test("buildJeSubmission rejects malformed decimal amounts", () => {
    expect(() =>
        buildJeSubmission([
            { id: "l1", account: "Cash", side: "dr", amount: "1,000" },
        ])
    ).toThrow(/Amount for l1 must be a decimal number/);
});

test("buildNumericSubmission coerces numbers per cell", () => {
    const json = buildNumericSubmission([
        { id: "c1", value: "-250000.75" },
        { id: "c2", value: "   " },
        { id: "c3", value: ".25" },
    ]);
    const parsed = JSON.parse(json);
    expect(parsed.steps[0].value).toBe(-250000.75);
    expect(parsed.steps[1].value).toBe("");
    expect(parsed.steps[2].value).toBe(0.25);
});

test("buildNumericSubmission rejects non-finite or malformed cell values", () => {
    expect(() => buildNumericSubmission([{ id: "c1", value: "NaN" }])).toThrow(
        /Value for c1 must be a decimal number/,
    );
    expect(() => buildNumericSubmission([{ id: "c2", value: "9".repeat(400) }])).toThrow(
        /Value for c2 must be a finite number/,
    );
});

// --- Workstream B: section-agnostic surfaces ---------------------------------

test("sectionFromTags reads sec:: tag, falls back to FAR", () => {
    expect(sectionFromTags(["ds::reg::deduct", "sec::REG"])).toBe("REG");
    expect(sectionFromTags(["sec::reg"])).toBe("REG");
    expect(sectionFromTags(["ds::lease::finance"])).toBe("FAR");
    expect(sectionFromTags(undefined)).toBe("FAR");
    expect(() => sectionFromTags(["sec::NOPE"])).toThrow(/Unknown CPA section tag: sec::NOPE/);
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
            JSON.stringify([
                {
                    id: "b1",
                    kind: "blank",
                    label: "Blank 1",
                    answer_key: "o1",
                    options: [{ id: "o1", text: "Answer" }],
                },
            ]),
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

test("parseSteps rejects malformed doc-review blank options", () => {
    expect(() =>
        parseSteps(JSON.stringify([
            {
                id: "b1",
                kind: "blank",
                label: "Blank 1",
                options: [],
            },
        ]))
    ).toThrow(/Options for b1 must contain at least one option/);

    expect(() =>
        parseSteps(JSON.stringify([
            {
                id: "b1",
                kind: "blank",
                label: "Blank 1",
            },
        ]))
    ).toThrow(/Options for b1 must be an array/);

    expect(() =>
        parseSteps(JSON.stringify([
            {
                id: "b1",
                kind: "blank",
                label: "Blank 1",
                options: [{ id: "", text: "Choice" }],
            },
        ]))
    ).toThrow(/Option 1 for b1 is missing an id/);

    expect(() =>
        parseSteps(JSON.stringify([
            {
                id: "b1",
                kind: "blank",
                label: "Blank 1",
                options: [{ id: "o1", text: "" }],
            },
        ]))
    ).toThrow(/Option o1 for b1 is missing text/);
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
