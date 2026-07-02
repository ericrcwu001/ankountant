// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import { buildCountdown, buildPhaseCta, choosePhase, CONSOLIDATION_WINDOW_DAYS, daysUntil } from "./lib";

const today = new Date(2026, 0, 1); // 2026-01-01 (local)

test("daysUntil counts whole local days, signed", () => {
    expect(daysUntil("2026-01-31", today)).toBe(30);
    expect(daysUntil("2026-01-01", today)).toBe(0);
    expect(daysUntil("2025-12-27", today)).toBe(-5);
});

test("daysUntil rejects empty / malformed / impossible dates", () => {
    expect(daysUntil("", today)).toBe(null);
    expect(daysUntil("nope", today)).toBe(null);
    expect(daysUntil("2026-13-01", today)).toBe(null);
    expect(daysUntil("2026-02-30", today)).toBe(null);
});

test("buildCountdown labels the future, exam day, and the past", () => {
    expect(buildCountdown("2026-01-31", today)).toMatchObject({
        hasDate: true,
        days: 30,
        numeral: "30",
        caption: "days until exam",
    });
    expect(buildCountdown("2026-01-02", today).caption).toBe("day until exam");
    expect(buildCountdown("2026-01-01", today)).toMatchObject({
        numeral: "0",
        caption: "Exam day — good luck",
    });
    expect(buildCountdown("2025-12-27", today)).toMatchObject({
        numeral: "5",
        caption: "days since exam",
    });
});

test("buildCountdown with no date invites the user to set one", () => {
    expect(buildCountdown("", today)).toMatchObject({
        hasDate: false,
        days: null,
        numeral: "—",
        caption: "Set your exam date",
    });
});

test("choosePhase: no memory base is always foundation (beginner override)", () => {
    // Regardless of days-to-exam — even none set — a student with no base builds
    // it first (SPOV 3 boundary / worked-example effect).
    expect(choosePhase({ days: 90, memoryReady: false })).toBe("foundation");
    expect(choosePhase({ days: 5, memoryReady: false })).toBe("foundation");
    expect(choosePhase({ days: null, memoryReady: false })).toBe("foundation");
});

test("choosePhase: final stretch consolidates once a base exists", () => {
    expect(choosePhase({ days: 0, memoryReady: true })).toBe("consolidation");
    expect(choosePhase({ days: CONSOLIDATION_WINDOW_DAYS, memoryReady: true })).toBe(
        "consolidation",
    );
});

test("choosePhase: otherwise discrimination is the core primitive", () => {
    // Just past the window, far out, no date, and after the exam all default to
    // the confusion set for a student with a base.
    expect(choosePhase({ days: CONSOLIDATION_WINDOW_DAYS + 1, memoryReady: true })).toBe(
        "discrimination",
    );
    expect(choosePhase({ days: 90, memoryReady: true })).toBe("discrimination");
    expect(choosePhase({ days: null, memoryReady: true })).toBe("discrimination");
    expect(choosePhase({ days: -3, memoryReady: true })).toBe("discrimination");
});

test("buildPhaseCta maps each phase to a label + routing target", () => {
    expect(buildPhaseCta("foundation")).toMatchObject({
        phase: "foundation",
        label: "Build foundation",
        target: "recall",
    });
    expect(buildPhaseCta("discrimination")).toMatchObject({
        phase: "discrimination",
        label: "Discrimination drill",
        target: "confusion",
    });
    expect(buildPhaseCta("consolidation")).toMatchObject({
        phase: "consolidation",
        label: "Consolidate",
        target: "recall",
    });
    // Every phase surfaces a non-empty subtitle for the two-line CTA.
    for (const phase of ["foundation", "discrimination", "consolidation"] as const) {
        expect(buildPhaseCta(phase).subtitle.length).toBeGreaterThan(0);
    }
});
