// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import {
    buildTopoRange,
    heightForTopicScore,
    TOPIC_MAX_SCORE,
    TOPIC_PASS_SCORE,
    type TopoTopic,
    yForTopicScore,
} from "./topo";

test("heightForTopicScore maps topic score percentages onto 0..1", () => {
    expect(heightForTopicScore(0)).toBe(0);
    expect(heightForTopicScore(75)).toBeGreaterThan(0.65);
    expect(heightForTopicScore(75)).toBeLessThan(0.75);
    expect(heightForTopicScore(TOPIC_MAX_SCORE)).toBe(1);
    expect(heightForTopicScore(-4)).toBe(0);
    expect(heightForTopicScore(130)).toBe(1);
    expect(heightForTopicScore(90) - heightForTopicScore(80)).toBeGreaterThan(0.1);
});

test("foreground topic heights compress around the pass line", () => {
    const passHeight = heightForTopicScore(TOPIC_PASS_SCORE);

    expect(heightForTopicScore(0, "front")).toBe(0);
    expect(heightForTopicScore(TOPIC_PASS_SCORE, "front")).toBeCloseTo(passHeight);
    expect(heightForTopicScore(82, "front")).toBeGreaterThan(passHeight);
    expect(heightForTopicScore(85, "back") - heightForTopicScore(82, "front"))
        .toBeGreaterThan(0.1);
});

test("topo flags and pass line share the same topic score y-axis", () => {
    const topics: TopoTopic[] = [
        {
            key: "back-above",
            label: "Back Above",
            score: 90,
            below: false,
            cx: 0.2,
            height: 0.9,
            tier: "back",
        },
        {
            key: "back-pass",
            label: "Back Pass",
            score: TOPIC_PASS_SCORE,
            below: false,
            cx: 0.5,
            height: 0.75,
            tier: "back",
        },
        {
            key: "front-pass",
            label: "Front Pass",
            score: TOPIC_PASS_SCORE,
            below: false,
            cx: 0.6,
            height: 0.75,
            tier: "front",
        },
        {
            key: "front-below",
            label: "Front Below",
            score: 60,
            below: true,
            cx: 0.8,
            height: 0.6,
            tier: "front",
        },
    ];
    const range = buildTopoRange(topics, { width: 1000, height: 680 });
    const plotH = range.height * 0.86;

    expect(yForTopicScore(0, range.baseY, plotH)).toBe(range.height);
    expect(range.passY).toBeCloseTo(
        yForTopicScore(TOPIC_PASS_SCORE, range.baseY, plotH),
    );
    expect(range.flags.find((f) => f.key === "back-pass")?.y).toBeCloseTo(
        range.passY,
    );
    expect(range.flags.find((f) => f.key === "front-pass")?.y).toBeCloseTo(
        range.passY,
    );
    expect(range.flags.find((f) => f.key === "front-below")?.y).toBeGreaterThan(
        yForTopicScore(60, range.baseY, plotH),
    );
    expect(range.flags.find((f) => f.key === "back-above")?.y).toBeLessThan(
        range.passY,
    );
    expect(range.flags.find((f) => f.key === "front-below")?.y).toBeGreaterThan(
        range.passY,
    );
});
