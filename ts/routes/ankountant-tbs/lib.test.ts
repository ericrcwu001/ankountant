// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { buildJeSubmission, buildNumericSubmission, buildTbsModel, parseExhibits, parseSteps } from "./lib";

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
