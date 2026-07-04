// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { cellKey, colLabel, displayCell, evalCell, parseRef } from "./spreadsheet";

function grid(cells: Record<string, string>): (ref: string) => string {
    return (ref) => cells[ref] ?? "";
}

test("parseRef / cellKey / colLabel round-trip within bounds", () => {
    expect(colLabel(0)).toBe("A");
    expect(cellKey(0, 0)).toBe("A1");
    expect(parseRef("A1")).toEqual({ col: 0, row: 0 });
    expect(parseRef("B3")).toEqual({ col: 1, row: 2 });
    expect(parseRef("Z9")).toBeNull(); // out of the 8-col grid
    expect(parseRef("nope")).toBeNull();
});

test("plain numeric cells and arithmetic evaluate", () => {
    const g = grid({ A1: "10", A2: "5" });
    expect(evalCell("42", g)).toEqual({ ok: true, value: 42 });
    expect(evalCell("$1,200", g)).toEqual({ ok: true, value: 1200 });
    expect(evalCell("=A1+A2", g)).toEqual({ ok: true, value: 15 });
    expect(evalCell("=A1*2-A2", g)).toEqual({ ok: true, value: 15 });
    expect(evalCell("=(A1+A2)/5", g)).toEqual({ ok: true, value: 3 });
    expect(evalCell("=-A1", g)).toEqual({ ok: true, value: -10 });
});

test("percentage cells and formula literals evaluate as fractions", () => {
    const g = grid({ A1: "5%", A2: "2.5 %", B1: "$1,200" });
    expect(evalCell("5%", g)).toEqual({ ok: true, value: 0.05 });
    expect(evalCell("=A1*B1", g)).toEqual({ ok: true, value: 60 });
    expect(evalCell("=A1+A2", g)).toEqual({ ok: true, value: 0.075 });
    expect(evalCell("=5%*200", g)).toEqual({ ok: true, value: 10 });
    expect(evalCell("5%%", g)).toEqual({ ok: false, error: "#VALUE" });
    expect(evalCell("5%2", g)).toEqual({ ok: false, error: "#VALUE" });
    expect(evalCell("=5%%", g)).toEqual({ ok: false, error: "#SYNTAX" });
});

test("SUM / AVERAGE over ranges, and ROUND", () => {
    const g = grid({ A1: "1", A2: "2", A3: "3", B1: "10" });
    expect(evalCell("=SUM(A1:A3)", g)).toEqual({ ok: true, value: 6 });
    expect(evalCell("=SUM(A1:A3, B1)", g)).toEqual({ ok: true, value: 16 });
    expect(evalCell("=AVERAGE(A1:A3)", g)).toEqual({ ok: true, value: 2 });
    expect(evalCell("=ROUND(A1/A3, 2)", g)).toEqual({ ok: true, value: 0.33 });
});

test("nested formula references resolve", () => {
    const g = grid({ A1: "2", A2: "=A1*3", A3: "=A2+A1" });
    expect(evalCell("=A3", g)).toEqual({ ok: true, value: 8 });
});

test("errors: div by zero, cycles, bad names, non-numeric refs", () => {
    expect(evalCell("=1/0", grid({}))).toEqual({ ok: false, error: "#DIV/0" });
    expect(evalCell("=NOPE(A1)", grid({ A1: "1" }))).toEqual({ ok: false, error: "#NAME" });
    expect(evalCell("=A1", grid({ A1: "abc" }))).toEqual({ ok: false, error: "#VALUE" });
    expect(evalCell("$", grid({}))).toEqual({ ok: false, error: "#VALUE" });
    expect(evalCell("=A1", grid({ A1: "%" }))).toEqual({ ok: false, error: "#VALUE" });

    const cyclic = grid({ A1: "=A2", A2: "=A1" });
    const r = evalCell("=A1", cyclic);
    expect(r.ok).toBe(false);
});

test("displayCell shows raw text for non-formulas and computed value for formulas", () => {
    const g = grid({ A1: "10", A2: "20" });
    expect(displayCell("hello", g)).toBe("hello");
    expect(displayCell("=A1+A2", g)).toBe("30");
    expect(displayCell("=1/0", g)).toBe("#DIV/0");
});
