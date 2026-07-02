// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Normalizes the deck/tag RPC trees into one shape the recursive sidebar can
// ! render, and filters them for the sidebar search box. Both RPC trees return a
// ! synthetic empty root whose children are the top level, and each node's
// ! `name` is the LEAF only — so we accumulate the parent prefix to reconstruct
// ! full `deck:`/`tag:` paths (matches qt/aqt/browser/sidebar/tree.py). Pure.

import type { DeckTreeNode } from "@generated/anki/decks_pb";
import type { TagTreeNode } from "@generated/anki/tags_pb";

export interface TreeItem {
    id: string;
    /** Leaf component shown in the row. */
    label: string;
    /** Full "A::B::C" path used to build the search. */
    fullName: string;
    kind: "deck" | "tag";
    deckId?: bigint;
    collapsed: boolean;
    level: number;
    children: TreeItem[];
}

export function deckTreeToItems(root: DeckTreeNode, prefix = ""): TreeItem[] {
    return root.children
        .filter((child) => child.deckId !== 1n || child.name !== "Default" || hasChildren(child))
        .map((child) => {
            const fullName = prefix + child.name;
            return {
                id: `deck:${child.deckId}`,
                label: child.name,
                fullName,
                kind: "deck" as const,
                deckId: child.deckId,
                collapsed: child.collapsed,
                level: child.level,
                children: deckTreeToItems(child, `${fullName}::`),
            };
        });
}

function hasChildren(node: DeckTreeNode): boolean {
    return node.children.length > 0;
}

export function tagTreeToItems(root: TagTreeNode, prefix = ""): TreeItem[] {
    return root.children.map((child) => {
        const fullName = prefix + child.name;
        return {
            id: `tag:${fullName}`,
            label: child.name,
            fullName,
            kind: "tag" as const,
            collapsed: child.collapsed,
            level: child.level,
            children: tagTreeToItems(child, `${fullName}::`),
        };
    });
}

/**
 * Prune a tree to branches whose full path contains `query` (case-insensitive),
 * keeping ancestors of any match. An empty query returns the tree unchanged.
 */
export function filterItems(items: TreeItem[], query: string): TreeItem[] {
    const q = query.trim().toLowerCase();
    if (!q) {
        return items;
    }
    const out: TreeItem[] = [];
    for (const item of items) {
        const children = filterItems(item.children, q);
        if (item.fullName.toLowerCase().includes(q) || children.length > 0) {
            out.push({ ...item, children });
        }
    }
    return out;
}
