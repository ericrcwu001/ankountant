// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getConfigJson, getReadiness } from "@generated/backend";

import type { PageLoad } from "./$types";

const SECTION = "FAR";

export const load = (async () => {
    const readiness = await getReadiness({ section: SECTION });
    // The exam date lives in `col` config under ankountant.<section>.exam.date
    // (written via the generic config-set RPC — see Home.svelte). It is the
    // expected-absent state until the user picks a date, so suppress the
    // backend's NotFound alert and fall back to empty.
    let examDate = "";
    try {
        const raw = await getConfigJson(
            { val: `ankountant.${SECTION}.exam.date` },
            { alertOnError: false },
        );
        const parsed = JSON.parse(new TextDecoder().decode(raw.json));
        examDate = typeof parsed === "string" ? parsed : "";
    } catch {
        examDate = "";
    }
    return { readiness, section: SECTION, examDate };
}) satisfies PageLoad;
