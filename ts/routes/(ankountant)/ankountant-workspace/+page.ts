// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import type { PageLoad } from "./$types";
import { isSurfaceKind } from "./workspace-layout";

// The tiling workspace loads no data itself — each pane self-loads. `?initial`
// lets the Ankountant menu seed a fresh layout with a chosen surface.
export const load = (({ url }) => {
    const raw = url.searchParams.get("initial") ?? "";
    const initial = isSurfaceKind(raw) ? raw : undefined;
    return { initial };
}) satisfies PageLoad;
