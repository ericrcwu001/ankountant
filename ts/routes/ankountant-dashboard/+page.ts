// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getConfigJson, getReadiness } from "@generated/backend";

import type { PageLoad } from "./$types";

const SECTION = "FAR";

export const load = (async () => {
    const readiness = await getReadiness({ section: SECTION });
    // The exam date is stored in `col` config under
    // ankountant.<section>.exam.date (set via the existing config-set RPC — no
    // new setter). It is surfaced so the Readiness band can be labelled the
    // exam-day projection (B5-D4 / A57).
    let examDate = "";
    try {
        const raw = await getConfigJson({ val: `ankountant.${SECTION}.exam.date` });
        const parsed = JSON.parse(new TextDecoder().decode(raw.json));
        examDate = typeof parsed === "string" ? parsed : "";
    } catch {
        examDate = "";
    }
    return { readiness, section: SECTION, examDate };
}) satisfies PageLoad;
