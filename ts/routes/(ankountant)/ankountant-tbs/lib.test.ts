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
    defaultStepLabel,
    docReviewAnswersComplete,
    paneExhibits,
    parseExhibits,
    parseSteps,
    renderableTbsShape,
    researchCitationComplete,
    revealResultPresentation,
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
    tbsSurfaceTitle,
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

test("buildTbsModel fails loudly on missing prompt", () => {
    const stepsJson = JSON.stringify([{ id: "l1", answer_key: 1 }]);
    expect(() => buildTbsModel(["journal_entry", "", "[]", stepsJson, "ds::lease"])).toThrow(
        /prompt is missing/,
    );
    expect(() => buildTbsModel(["journal_entry", " ", "[]", stepsJson, "ds::lease"])).toThrow(
        /prompt is missing/,
    );
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

test("defaultStepLabel makes seeded ids learner-readable", () => {
    expect(defaultStepLabel("l1")).toBe("Line 1");
    expect(defaultStepLabel("c2")).toBe("Cell 2");
    expect(defaultStepLabel("b3")).toBe("Blank 3");
    expect(defaultStepLabel("citation")).toBe("citation");
});

test("tbsSurfaceTitle names standalone gradable TBS shapes", () => {
    expect(tbsSurfaceTitle("journal_entry")).toBe("Journal entry simulation");
    expect(tbsSurfaceTitle("numeric")).toBe("Numeric simulation");
});

test("parseSteps falls back to friendly labels for unlabeled seeded ids", () => {
    const steps = parseSteps(JSON.stringify([
        { id: "l1", answer_key: 1 },
        { id: "c2", answer_key: 2 },
        { id: "named", label: "Explicit", answer_key: 3 },
    ]));
    expect(steps.map((step) => step.label)).toEqual(["Line 1", "Cell 2", "Explicit"]);
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
    expect(() => parseExhibits("[1]")).toThrow(/exhibits_json\[0\] must be an object/);
    expect(() => parseExhibits(JSON.stringify([{ kind: "chart" }]))).toThrow(
        /exhibits_json\[0\]\.kind has unknown exhibit kind: chart/,
    );
    const ex = parseExhibits(JSON.stringify([{ title: "Ex 1", body: "text" }]));
    expect(ex[0].title).toBe("Ex 1");
    expect(ex[0].kind).toBe("text");
});

test("parseSteps fails loudly on missing, malformed, or empty step json", () => {
    expect(() => parseSteps(undefined)).toThrow(/steps_json is missing/);
    expect(() => parseSteps("not json")).toThrow(/Invalid steps_json/);
    expect(() => parseSteps("{}")).toThrow(/steps_json must be an array/);
    expect(() => parseSteps("[]")).toThrow(/steps_json must contain at least one step/);
    expect(() => parseSteps("[1]")).toThrow(/steps_json\[0\] must be an object/);
    expect(() => parseSteps(JSON.stringify([{ answer_key: 1 }]))).toThrow(
        /steps_json\[0\]\.id is missing/,
    );
    expect(() => parseSteps(JSON.stringify([{ id: " ", answer_key: 1 }]))).toThrow(
        /steps_json\[0\]\.id is missing/,
    );
    expect(() => parseSteps(JSON.stringify([{ id: "a" }, { id: "a" }]))).toThrow(
        /steps_json has duplicate step id: a/,
    );
    expect(() => parseSteps(JSON.stringify([{ id: "a", weight: -0.1 }, { id: "b", weight: 1.1 }]))).toThrow(
        /steps_json\[0\]\.weight must be a nonnegative finite number/,
    );
    expect(() => parseSteps(JSON.stringify([{ id: "a", weight: null }, { id: "b" }]))).toThrow(
        /steps_json\[0\]\.weight must be a nonnegative finite number/,
    );
    expect(() => parseSteps(JSON.stringify([{ id: "a", weight: 0.8 }, { id: "b", weight: 0.8 }]))).toThrow(
        /steps_json weights must sum to 1\.0/,
    );
    expect(() => parseSteps(JSON.stringify([{ id: "s1", options: [{ id: "o1", text: "x", kind: "maybe" }] }]))).toThrow(
        /Option o1 for s1 has unknown option kind: maybe/,
    );
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
            { id: "l1", label: "Line 1", account: "Cash", side: "dr", amount: "1,000" },
        ])
    ).toThrow(/Amount for Line 1 must be a decimal number/);
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
    expect(() => buildNumericSubmission([{ id: "c1", label: "Cell 1", value: "NaN" }])).toThrow(
        /Value for Cell 1 must be a decimal number/,
    );
    expect(() => buildNumericSubmission([{ id: "c2", label: "Cell 2", value: "9".repeat(400) }])).toThrow(
        /Value for Cell 2 must be a finite number/,
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

test("buildTbsModel rejects malformed doc-review documents", () => {
    const stepsJson = JSON.stringify([
        {
            id: "b1",
            kind: "blank",
            label: "Blank 1",
            answer_key: "o1",
            options: [{ id: "o1", text: "Answer" }],
        },
    ]);
    const noDocument = JSON.stringify([{ title: "Exhibit", body: "facts" }]);
    const noMarkers = JSON.stringify([
        { title: "Doc", kind: "document", role: "document", body: "plain text" },
    ]);
    const missingStep = JSON.stringify([
        { title: "Doc", kind: "document", role: "document", body: "x <blank step=\"b2\">y</blank>" },
    ]);

    expect(() => buildTbsModel(["doc_review", "Review it.", noDocument, stepsJson])).toThrow(
        /doc_review document exhibit is missing/,
    );
    expect(() => buildTbsModel(["doc_review", "Review it.", noMarkers, stepsJson])).toThrow(
        /doc_review document has no blank markers/,
    );
    expect(() => buildTbsModel(["doc_review", "Review it.", missingStep, stepsJson])).toThrow(
        /doc_review blank b2 has no step/,
    );
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
                options: [1],
            },
        ]))
    ).toThrow(/Option 1 for b1 must be an object/);

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

test("research submission requires a governing citation", () => {
    expect(researchCitationComplete("ASC 842-20-25-1")).toBe(true);
    expect(researchCitationComplete("   ")).toBe(false);
    expect(() => buildResearchSubmission("   ")).toThrow(/governing citation/);
});

test("buildDocReviewSubmission submits each blank's chosen option id", () => {
    const json = buildDocReviewSubmission([
        { id: "b1", value: " o1 " },
        { id: "b2", value: "o2" },
    ]);
    expect(JSON.parse(json)).toEqual({
        steps: [
            { id: "b1", value: "o1" },
            { id: "b2", value: "o2" },
        ],
    });
});

test("doc-review submission requires every blank to be selected", () => {
    expect(docReviewAnswersComplete([{ id: "b1", value: "o1" }])).toBe(true);
    expect(docReviewAnswersComplete([{ id: "b1", value: "" }])).toBe(false);
    expect(docReviewAnswersComplete([])).toBe(false);
    expect(() => buildDocReviewSubmission([{ id: "b1", value: "" }])).toThrow(
        /selected option for every blank/,
    );
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

test("revealResultPresentation keeps missing grader rows neutral", () => {
    expect(revealResultPresentation("line-1", [{ id: "line-1", correct: true }])).toEqual({
        status: "correct",
        mark: "✓",
        ariaLabel: "You were correct",
    });
    expect(revealResultPresentation("line-1", [{ id: "line-1", correct: false }])).toEqual({
        status: "incorrect",
        mark: "✗",
        ariaLabel: "You were incorrect",
    });
    expect(revealResultPresentation("line-2", [{ id: "line-1", correct: false }])).toEqual({
        status: "ungraded",
        mark: "-",
        ariaLabel: "Not graded",
    });
});
