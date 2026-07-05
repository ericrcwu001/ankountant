// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { error } from "@sveltejs/kit";

import { isSettingsSectionId } from "../settings-model";
import type { PageLoad } from "./$types";

export const load = (({ params }) => {
    if (!isSettingsSectionId(params.section)) {
        throw error(404, `Unknown settings section: ${params.section}`);
    }
    return { section: params.section };
}) satisfies PageLoad;
