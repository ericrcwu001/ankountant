// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Registry mapping each study surface to the self-loading pane component that
// ! mounts it, plus its switcher label/glyph. `typeof SvelteComponent<any>`
// ! mirrors the existing dynamic-slotting contract so `<svelte:component>` type
// ! checks.

/* eslint
@typescript-eslint/no-explicit-any: "off",
 */

import type { SvelteComponent } from "svelte";

import AddPane from "./panes/AddPane.svelte";
import BrowsePane from "./panes/BrowsePane.svelte";
import ConfusionPane from "./panes/ConfusionPane.svelte";
import DashboardPane from "./panes/DashboardPane.svelte";
import DocReviewPane from "./panes/DocReviewPane.svelte";
import LiteraturePane from "./panes/LiteraturePane.svelte";
import ResearchPane from "./panes/ResearchPane.svelte";
import StatsPane from "./panes/StatsPane.svelte";
import TbsPane from "./panes/TbsPane.svelte";
import type { SurfaceKind } from "./workspace-layout";

export interface SurfaceDef {
    kind: SurfaceKind;
    label: string;
    /** Decorative header glyph — no icon-font dependency. */
    glyph: string;
    component: typeof SvelteComponent<any>;
}

export const SURFACES: Record<SurfaceKind, SurfaceDef> = {
    dashboard: {
        kind: "dashboard",
        label: "Readiness",
        glyph: "◑",
        component: DashboardPane,
    },
    confusion: {
        kind: "confusion",
        label: "Confusion",
        glyph: "⇄",
        component: ConfusionPane,
    },
    tbs: {
        kind: "tbs",
        label: "TBS",
        glyph: "▤",
        component: TbsPane,
    },
    research: {
        kind: "research",
        label: "Research",
        glyph: "⌕",
        component: ResearchPane,
    },
    doc_review: {
        kind: "doc_review",
        label: "Doc Review",
        glyph: "▥",
        component: DocReviewPane,
    },
    literature: {
        kind: "literature",
        label: "Literature",
        glyph: "▧",
        component: LiteraturePane,
    },
    stats: {
        kind: "stats",
        label: "Stats",
        glyph: "▦",
        component: StatsPane,
    },
    add: {
        kind: "add",
        label: "Add",
        glyph: "＋",
        component: AddPane,
    },
    browse: {
        kind: "browse",
        label: "Browse",
        glyph: "☰",
        component: BrowsePane,
    },
};
