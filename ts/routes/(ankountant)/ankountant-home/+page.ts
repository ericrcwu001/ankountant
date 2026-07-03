// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import type { GetReadinessResponse } from "@generated/anki/scheduler_pb";
import { getConfigJson, getReadiness } from "@generated/backend";

import type { PageLoad } from "./$types";
import { SUMMIT_SECTIONS } from "./summit";

const SECTION = "FAR";

export const load = (async () => {
    // Readiness for every summit section (one RPC each — there is no bulk
    // endpoint). FAR drives the headline band + phase CTA; the whole set feeds
    // the topographic range + the section list.
    // One RPC per section, but resilient: a single section failing must not
    // blank the whole Home. Each call is caught independently → an undefined
    // entry renders as an "unproven" ghost (same as a backend abstain).
    const entries = await Promise.all(
        SUMMIT_SECTIONS.map(async (s) => {
            try {
                return [s.code, await getReadiness({ section: s.code })] as const;
            } catch (error) {
                console.log("ankountant: readiness failed for", s.code, error);
                return [s.code, undefined] as const;
            }
        }),
    );
    const sections: Record<string, GetReadinessResponse | undefined> = {};
    for (const [code, response] of entries) {
        sections[code] = response;
    }
    const readiness = sections[SECTION];

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
    return { readiness, section: SECTION, examDate, sections };
}) satisfies PageLoad;
