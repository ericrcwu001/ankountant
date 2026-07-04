// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { buildConfusionQueue } from "@generated/backend";

import { selectedSummitSection } from "../ankountant-home/summit";
import type { PageLoad } from "./$types";

export const load = (async ({ url }) => {
    const rawSection = url.searchParams.get("section");
    const section = rawSection === null ? "ALL" : selectedSummitSection(rawSection);
    // A3 returns an already label-stripped, interleaved queue (B3-D1). We never
    // fetch topic/deck labels for these items (B2-D1 / A44).
    const resp = await buildConfusionQueue({ section, maxItems: 60 });
    return { items: resp.items, section };
}) satisfies PageLoad;
