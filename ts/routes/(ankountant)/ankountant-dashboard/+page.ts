// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import { getExamDate, getReadiness } from "@generated/backend";

import { selectedSummitSection } from "../ankountant-home/summit";
import { readableBackendError } from "../backendError";
import type { PageLoad } from "./$types";

// The dashboard is the per-section drill-in: the summit range on Home links here
// with ?section=<CODE>. Defaults to FAR (the Readiness tab + direct visits).
export const load = (async ({ url }) => {
    const section = selectedSummitSection(url.searchParams.get("section"));
    try {
        const readiness = await getReadiness({ section });
        const examDate = (await getExamDate({ section })).date;
        return { readiness, section, examDate };
    } catch (error) {
        return {
            readiness: undefined,
            section,
            examDate: "",
            loadError: readableBackendError(
                error,
                "Readiness evidence could not be loaded.",
            ),
        };
    }
}) satisfies PageLoad;
