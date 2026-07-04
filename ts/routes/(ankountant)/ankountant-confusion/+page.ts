// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { buildConfusionQueue } from "@generated/backend";

import type { PageLoad } from "./$types";

const SECTION = "ALL";

export const load = (async () => {
    // A3 returns an already label-stripped, interleaved queue (B3-D1). We never
    // fetch topic/deck labels for these items (B2-D1 / A44).
    const resp = await buildConfusionQueue({ section: SECTION, maxItems: 60 });
    return { items: resp.items, section: SECTION };
}) satisfies PageLoad;
