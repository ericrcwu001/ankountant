// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! BSP tiling model for the Ankountant study workspace. A layout is a binary
// ! tree: every node is either a `leaf` (one mounted study surface) or a
// ! `split` (two children, laid out side-by-side `row` or stacked `col`,
// ! divided at `ratio`). Splitting a leaf wraps it in a split; closing a leaf
// ! collapses its parent split onto the sibling. Kept pure + DOM-free so the
// ! operations are unit-tested under `just test-ts` and reused by the Svelte
// ! renderer without duplication.

/** The study surfaces that can be mounted in a pane. */
export type SurfaceKind = "dashboard" | "confusion" | "tbs" | "stats" | "add" | "browse";

/** Split orientation. `row` = children left/right; `col` = children top/bottom. */
export type SplitDir = "row" | "col";

/** Which side of an existing node a newly-split pane lands on. */
export type Side = "before" | "after";

/** A branch selector into a split node. */
export type Branch = "a" | "b";

/** A path from the tree root to a node, one branch per level. */
export type Path = Branch[];

export interface LeafNode {
    type: "leaf";
    id: string;
    surface: SurfaceKind;
}

export interface SplitNode {
    type: "split";
    id: string;
    dir: SplitDir;
    /** Size fraction of child `a`, clamped to [MIN_RATIO, 1 - MIN_RATIO]. */
    ratio: number;
    a: TileNode;
    b: TileNode;
}

export type TileNode = LeafNode | SplitNode;

/** Hard cap on simultaneously-open panes (product decision: four). */
export const MAX_PANES = 4;

/** Smallest fraction a pane may be shrunk to when resizing a split. */
export const MIN_RATIO = 0.15;

/** All mountable surfaces, in the order shown by the pane switcher. */
export const SURFACE_KINDS: readonly SurfaceKind[] = [
    "dashboard",
    "confusion",
    "tbs",
    "stats",
    "add",
    "browse",
];

const KNOWN_SURFACES = new Set<string>(SURFACE_KINDS);

let _idSeq = 0;

/** A process-unique node id. Prefers crypto.randomUUID; falls back to a counter
 *  (jsdom/older runtimes) so the model stays usable under vitest. */
export function nextId(): string {
    const c = typeof globalThis !== "undefined" ? globalThis.crypto : undefined;
    if (c && typeof c.randomUUID === "function") {
        return c.randomUUID();
    }
    _idSeq += 1;
    return `n${_idSeq}`;
}

export function makeLeaf(surface: SurfaceKind): LeafNode {
    return { type: "leaf", id: nextId(), surface };
}

/** A fresh single-pane layout. */
export function defaultLayout(surface: SurfaceKind = "dashboard"): TileNode {
    return makeLeaf(surface);
}

export function countLeaves(node: TileNode): number {
    return node.type === "leaf" ? 1 : countLeaves(node.a) + countLeaves(node.b);
}

/** True while another pane may still be opened (under the MAX_PANES cap). */
export function canSplit(tree: TileNode): boolean {
    return countLeaves(tree) < MAX_PANES;
}

export function nodeAt(tree: TileNode, path: Path): TileNode | null {
    let node: TileNode = tree;
    for (const branch of path) {
        if (node.type !== "split") {
            return null;
        }
        node = node[branch];
    }
    return node;
}

/** Return a new tree with `fn` applied to the node at `path` (structural
 *  sharing everywhere else). A path that runs off a leaf is a no-op. */
function updateAt(tree: TileNode, path: Path, fn: (n: TileNode) => TileNode): TileNode {
    if (path.length === 0) {
        return fn(tree);
    }
    if (tree.type !== "split") {
        return tree;
    }
    const [head, ...rest] = path;
    const child = updateAt(tree[head], rest, fn);
    return head === "a" ? { ...tree, a: child } : { ...tree, b: child };
}

/** Split the node at `path`, wrapping it in a new split alongside a fresh pane
 *  showing `surface`. No-op past the pane cap. */
export function splitAt(
    tree: TileNode,
    path: Path,
    dir: SplitDir,
    surface: SurfaceKind,
    side: Side = "after",
): TileNode {
    if (!canSplit(tree)) {
        return tree;
    }
    return updateAt(tree, path, (node) => {
        const leaf = makeLeaf(surface);
        return {
            type: "split",
            id: nextId(),
            dir,
            ratio: 0.5,
            a: side === "before" ? leaf : node,
            b: side === "before" ? node : leaf,
        };
    });
}

/** Remove the leaf at `path`; its parent split collapses onto the sibling.
 *  Closing the last remaining pane is disallowed (returns the tree unchanged). */
export function closeAt(tree: TileNode, path: Path): TileNode {
    if (path.length === 0) {
        return tree;
    }
    const parentPath = path.slice(0, -1);
    const branch = path[path.length - 1];
    return updateAt(tree, parentPath, (parent) => {
        if (parent.type !== "split") {
            return parent;
        }
        return branch === "a" ? parent.b : parent.a;
    });
}

export function setSurfaceAt(tree: TileNode, path: Path, surface: SurfaceKind): TileNode {
    return updateAt(tree, path, (node) => node.type === "leaf" ? { ...node, surface } : node);
}

export function setRatioAt(tree: TileNode, path: Path, ratio: number): TileNode {
    const clamped = Math.min(1 - MIN_RATIO, Math.max(MIN_RATIO, ratio));
    return updateAt(tree, path, (node) => node.type === "split" ? { ...node, ratio: clamped } : node);
}

function firstLeafPath(node: TileNode, path: Path = []): Path {
    return node.type === "leaf" ? path : firstLeafPath(node.a, [...path, "a"]);
}

/** Open one more pane showing `surface` by splitting the first leaf. No-op past
 *  the cap. */
export function addPane(tree: TileNode, surface: SurfaceKind, dir: SplitDir = "row"): TileNode {
    if (!canSplit(tree)) {
        return tree;
    }
    return splitAt(tree, firstLeafPath(tree), dir, surface, "after");
}

export function hasSurface(tree: TileNode, surface: SurfaceKind): boolean {
    return tree.type === "leaf"
        ? tree.surface === surface
        : hasSurface(tree.a, surface) || hasSurface(tree.b, surface);
}

/** Ensure a pane showing `surface` exists, adding one if the cap allows. */
export function ensureSurface(tree: TileNode, surface: SurfaceKind): TileNode {
    return hasSurface(tree, surface) ? tree : addPane(tree, surface);
}

export function serialize(tree: TileNode): string {
    return JSON.stringify(tree);
}

/** Parse + validate a persisted layout. Returns null on anything malformed so
 *  the caller can fall back to a default; repairs partial damage (unknown
 *  surface, out-of-range ratio, missing id, one dead child) in place. */
export function deserialize(raw: string | null | undefined): TileNode | null {
    if (!raw) {
        return null;
    }
    try {
        return sanitize(JSON.parse(raw));
    } catch {
        return null;
    }
}

function sanitize(node: unknown): TileNode | null {
    if (!node || typeof node !== "object") {
        return null;
    }
    const n = node as Record<string, unknown>;
    if (n.type === "leaf") {
        const surface = KNOWN_SURFACES.has(n.surface as string)
            ? (n.surface as SurfaceKind)
            : "dashboard";
        return { type: "leaf", id: typeof n.id === "string" ? n.id : nextId(), surface };
    }
    if (n.type === "split") {
        const a = sanitize(n.a);
        const b = sanitize(n.b);
        // A split with a dead child degrades to its surviving child.
        if (!a || !b) {
            return a ?? b ?? null;
        }
        const dir: SplitDir = n.dir === "col" ? "col" : "row";
        const ratio = typeof n.ratio === "number" && isFinite(n.ratio)
            ? Math.min(1 - MIN_RATIO, Math.max(MIN_RATIO, n.ratio))
            : 0.5;
        return {
            type: "split",
            id: typeof n.id === "string" ? n.id : nextId(),
            dir,
            ratio,
            a,
            b,
        };
    }
    return null;
}
