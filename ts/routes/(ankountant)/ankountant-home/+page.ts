// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import type { GetReadinessResponse } from "@generated/anki/scheduler_pb";
import { getExamDate, getReadiness } from "@generated/backend";

import { readableBackendError } from "../backendError";
import type { PageLoad } from "./$types";
import { selectedSummitSection, SUMMIT_SECTIONS } from "./summit";

export const load = (async ({ url }) => {
    const section = selectedSummitSection(url.searchParams.get("section"));
    try {
        const entries = await Promise.all(
            SUMMIT_SECTIONS.map(async (s) => [s.code, await getReadiness({ section: s.code })] as const),
        );
        const sections: Record<string, GetReadinessResponse | undefined> = {};
        for (const [code, response] of entries) {
            sections[code] = response;
        }
        const readiness = sections[section];

        const examDate = (await getExamDate({ section })).date;
        return { readiness, section, examDate, sections };
    } catch (error) {
        return {
            readiness: undefined,
            section,
            examDate: "",
            sections: {} as Record<string, GetReadinessResponse | undefined>,
            loadError: readableBackendError(error, "The study home could not be loaded."),
        };
    }
}) satisfies PageLoad;
