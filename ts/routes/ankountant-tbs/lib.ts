// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B4 (F014) — pure helpers for the TBS review surface. The heavy lifting
// ! (partial-credit grading) is authoritative on the Rust side via
// ! `SubmitPerformanceAttempt`; these helpers only parse the note structure for
// ! rendering and shape the submission JSON. Kept DOM-free for `just test-ts`.

/** Field order of the "Ankountant TBS" note type (mirrors tbs_fields). */
export const TBS_FIELD = {
    tbsType: 0,
    prompt: 1,
    exhibitsJson: 2,
    stepsJson: 3,
    schemaTag: 4,
} as const;

export type TbsShape = "journal_entry" | "numeric" | "research" | "doc_review";

/** A single exhibit shown alongside the task (basic pane, B4-D4). */
export interface Exhibit {
    title: string;
    body: string;
}

/**
 * A gradable step, WITHOUT its answer key — the key stays server-side and is
 * never rendered. For a journal-entry step the client edits account/side/amount
 * cells; for a numeric step, a single value cell.
 */
export interface RenderStep {
    id: string;
    label: string;
    weight: number;
}

export interface TbsModel {
    shape: TbsShape;
    prompt: string;
    exhibits: Exhibit[];
    steps: RenderStep[];
}

function safeParse<T>(raw: string | undefined, fallback: T): T {
    if (!raw) {
        return fallback;
    }
    try {
        return JSON.parse(raw) as T;
    } catch {
        return fallback;
    }
}

/** Parse exhibits_json into a list of {title, body} exhibits. */
export function parseExhibits(raw: string | undefined): Exhibit[] {
    const parsed = safeParse<unknown>(raw, []);
    if (!Array.isArray(parsed)) {
        return [];
    }
    return parsed.map((e, i) => {
        const obj = (e ?? {}) as Record<string, unknown>;
        return {
            title: typeof obj.title === "string" ? obj.title : `Exhibit ${i + 1}`,
            body: typeof obj.body === "string" ? obj.body : String(e ?? ""),
        };
    });
}

interface RawStep {
    id?: unknown;
    label?: unknown;
    weight?: unknown;
}

/**
 * Parse steps_json into render steps, stripping the answer_key. Weights default
 * to 1/N (matching the Rust default_weight) so the rendered total reconciles
 * with the A10 grading.
 */
export function parseSteps(raw: string | undefined): RenderStep[] {
    const parsed = safeParse<RawStep[]>(raw, []);
    if (!Array.isArray(parsed) || parsed.length === 0) {
        return [];
    }
    const defaultWeight = 1 / parsed.length;
    return parsed.map((s, i) => {
        const id = typeof s.id === "string" ? s.id : `s${i + 1}`;
        const label = typeof s.label === "string" ? s.label : id;
        const weight = typeof s.weight === "number" ? s.weight : defaultWeight;
        return { id, label, weight };
    });
}

/** Build the full TBS render model from a note's raw fields. */
export function buildTbsModel(fields: string[]): TbsModel {
    const shapeRaw = fields[TBS_FIELD.tbsType] ?? "journal_entry";
    const shape = (["journal_entry", "numeric", "research", "doc_review"].includes(shapeRaw)
        ? shapeRaw
        : "journal_entry") as TbsShape;
    return {
        shape,
        prompt: fields[TBS_FIELD.prompt] ?? "",
        exhibits: parseExhibits(fields[TBS_FIELD.exhibitsJson]),
        steps: parseSteps(fields[TBS_FIELD.stepsJson]),
    };
}

/** One journal-entry line as edited in the grid. */
export interface JeLineInput {
    id: string;
    account: string;
    side: string;
    amount: string;
}

/** Shape the submission_json for a journal-entry TBS. */
export function buildJeSubmission(lines: JeLineInput[]): string {
    return JSON.stringify({
        steps: lines.map((l) => ({
            id: l.id,
            value: {
                account: l.account,
                side: l.side,
                amount: l.amount === "" ? "" : Number(l.amount),
            },
        })),
    });
}

/** One numeric cell as edited. */
export interface NumericCellInput {
    id: string;
    value: string;
}

/** Shape the submission_json for a numeric TBS. */
export function buildNumericSubmission(cells: NumericCellInput[]): string {
    return JSON.stringify({
        steps: cells.map((c) => ({
            id: c.id,
            value: c.value === "" ? "" : Number(c.value),
        })),
    });
}
