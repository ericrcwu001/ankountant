// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getConfigJson, getReadiness } from "@generated/backend";

import type { PageLoad } from "./$types";

// The dashboard is the per-section drill-in: the summit range on Home links here
// with ?section=<CODE>. Defaults to FAR (the Readiness tab + direct visits).
export const load = (async ({ url }) => {
    const section = url.searchParams.get("section") ?? "FAR";
    const readiness = await getReadiness({ section });
    // The exam date is stored in `col` config under
    // ankountant.<section>.exam.date (set via the existing config-set RPC — no
    // new setter). It is surfaced so the Readiness band can be labelled the
    // exam-day projection (B5-D4 / A57). A missing date is the normal, expected
    // state, so suppress the backend's NotFound alert and fall back to empty.
    let examDate = "";
    try {
        const raw = await getConfigJson(
            { val: `ankountant.${section}.exam.date` },
            { alertOnError: false },
        );
        const parsed = JSON.parse(new TextDecoder().decode(raw.json));
        examDate = typeof parsed === "string" ? parsed : "";
    } catch {
        examDate = "";
    }
    return { readiness, section, examDate };
}) satisfies PageLoad;
