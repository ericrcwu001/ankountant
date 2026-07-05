// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { expect, test } from "vitest";

import type { SplitNode, TileNode } from "./workspace-layout";
import {
    addPane,
    canSplit,
    closeAt,
    countLeaves,
    defaultLayout,
    deserialize,
    ensureSurface,
    hasSurface,
    isSurfaceKind,
    launchLayout,
    MAX_PANES,
    MIN_RATIO,
    nodeAt,
    serialize,
    setRatioAt,
    setSurfaceAt,
    splitAt,
} from "./workspace-layout";

test("defaultLayout is a single leaf", () => {
    const tree = defaultLayout("dashboard");
    expect(tree.type).toBe("leaf");
    expect(countLeaves(tree)).toBe(1);
});

test("isSurfaceKind validates runtime surface names", () => {
    expect(isSurfaceKind("tbs")).toBe(true);
    expect(isSurfaceKind("sync")).toBe(false);
    expect(isSurfaceKind(undefined)).toBe(false);
});

test("splitAt wraps the target in a split and adds a pane", () => {
    const tree = splitAt(defaultLayout("dashboard"), [], "row", "tbs");
    expect(tree.type).toBe("split");
    expect(countLeaves(tree)).toBe(2);
    const split = tree as SplitNode;
    expect(split.dir).toBe("row");
    // side defaults to "after": the original stays in `a`, the new pane in `b`.
    expect(nodeAt(tree, ["a"])).toMatchObject({ type: "leaf", surface: "dashboard" });
    expect(nodeAt(tree, ["b"])).toMatchObject({ type: "leaf", surface: "tbs" });
});

test("splitAt side=before puts the new pane in a", () => {
    const tree = splitAt(defaultLayout("dashboard"), [], "col", "confusion", "before");
    expect(nodeAt(tree, ["a"])).toMatchObject({ surface: "confusion" });
    expect(nodeAt(tree, ["b"])).toMatchObject({ surface: "dashboard" });
});

test("nested split — left pane + right column split top/bottom", () => {
    // Reproduces the exact layout the user asked for.
    let tree: TileNode = defaultLayout("dashboard");
    tree = splitAt(tree, [], "row", "tbs"); // left | right
    tree = splitAt(tree, ["b"], "col", "confusion"); // right -> top/bottom
    expect(countLeaves(tree)).toBe(3);
    expect(nodeAt(tree, ["a"])).toMatchObject({ surface: "dashboard" });
    expect(nodeAt(tree, ["b", "a"])).toMatchObject({ surface: "tbs" });
    expect(nodeAt(tree, ["b", "b"])).toMatchObject({ surface: "confusion" });
});

test("MAX_PANES cap blocks further splits", () => {
    let tree: TileNode = defaultLayout("dashboard");
    for (let i = 0; i < 10; i++) {
        tree = addPane(tree, "tbs");
    }
    expect(countLeaves(tree)).toBe(MAX_PANES);
    expect(canSplit(tree)).toBe(false);
    // A split at the cap is a no-op (same reference back).
    expect(splitAt(tree, [], "row", "tbs")).toBe(tree);
});

test("closeAt collapses the parent split onto the sibling", () => {
    let tree: TileNode = splitAt(defaultLayout("dashboard"), [], "row", "tbs");
    tree = closeAt(tree, ["a"]); // close the dashboard, tbs survives
    expect(tree.type).toBe("leaf");
    expect(tree).toMatchObject({ surface: "tbs" });
});

test("closeAt never removes the last pane", () => {
    const tree = defaultLayout("dashboard");
    expect(closeAt(tree, [])).toBe(tree);
});

test("setSurfaceAt swaps a leaf's surface", () => {
    let tree: TileNode = splitAt(defaultLayout("dashboard"), [], "row", "tbs");
    tree = setSurfaceAt(tree, ["a"], "confusion");
    expect(nodeAt(tree, ["a"])).toMatchObject({ surface: "confusion" });
});

test("setRatioAt clamps to [MIN_RATIO, 1 - MIN_RATIO]", () => {
    const tree = splitAt(defaultLayout("dashboard"), [], "row", "tbs");
    expect((setRatioAt(tree, [], 0) as SplitNode).ratio).toBe(MIN_RATIO);
    expect((setRatioAt(tree, [], 5) as SplitNode).ratio).toBe(1 - MIN_RATIO);
    expect((setRatioAt(tree, [], 0.4) as SplitNode).ratio).toBeCloseTo(0.4);
});

test("hasSurface / ensureSurface", () => {
    const tree = defaultLayout("dashboard");
    expect(hasSurface(tree, "dashboard")).toBe(true);
    expect(hasSurface(tree, "tbs")).toBe(false);
    const withTbs = ensureSurface(tree, "tbs");
    expect(hasSurface(withTbs, "tbs")).toBe(true);
    // Already present -> unchanged reference.
    expect(ensureSurface(withTbs, "tbs")).toBe(withTbs);
});

test("launchLayout uses a single surface instead of restored panes", () => {
    const restored = splitAt(defaultLayout("confusion"), [], "row", "dashboard");
    const tree = launchLayout(restored, "browse", "browse");
    expect(tree.type).toBe("leaf");
    expect(tree).toMatchObject({ surface: "browse" });
});

test("serialize/deserialize round-trips a tree", () => {
    const tree = splitAt(defaultLayout("dashboard"), [], "col", "confusion");
    const back = deserialize(serialize(tree));
    expect(back).toEqual(tree);
});

test("deserialize returns null only for absent input", () => {
    expect(deserialize(null)).toBeNull();
    expect(deserialize(undefined)).toBeNull();
    expect(deserialize("")).toBeNull();
});

test("deserialize rejects malformed persisted layouts", () => {
    expect(() => deserialize("not json")).toThrow(/invalid JSON/);
    expect(() => deserialize("{\"type\":\"leaf\",\"id\":\"x\",\"surface\":\"bogus\"}")).toThrow(
        /Unknown workspace surface/,
    );
    expect(() =>
        deserialize(
            "{\"type\":\"split\",\"id\":\"s\",\"dir\":\"row\",\"ratio\":0.5,\"a\":{\"type\":\"leaf\",\"id\":\"l\",\"surface\":\"tbs\"},\"b\":null}",
        )
    ).toThrow(/node must be an object/);
    expect(() =>
        deserialize(
            "{\"type\":\"split\",\"id\":\"s\",\"dir\":\"row\",\"ratio\":0.01,\"a\":{\"type\":\"leaf\",\"id\":\"a\",\"surface\":\"tbs\"},\"b\":{\"type\":\"leaf\",\"id\":\"b\",\"surface\":\"dashboard\"}}",
        )
    ).toThrow(/outside the allowed range/);
    expect(() =>
        deserialize(JSON.stringify({
            type: "split",
            id: "s1",
            dir: "row",
            ratio: 0.5,
            a: {
                type: "split",
                id: "s2",
                dir: "col",
                ratio: 0.5,
                a: { type: "leaf", id: "a", surface: "dashboard" },
                b: { type: "leaf", id: "b", surface: "confusion" },
            },
            b: {
                type: "split",
                id: "s3",
                dir: "col",
                ratio: 0.5,
                a: {
                    type: "split",
                    id: "s4",
                    dir: "row",
                    ratio: 0.5,
                    a: { type: "leaf", id: "c", surface: "tbs" },
                    b: { type: "leaf", id: "d", surface: "research" },
                },
                b: { type: "leaf", id: "e", surface: "stats" },
            },
        }))
    ).toThrow(/pane limit/);
});
