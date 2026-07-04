// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! Workstream B — pure helpers for the section-agnostic TBS surfaces (exam
// ! shell, research, doc-review, JE/numeric). Grading stays authoritative on the
// ! Rust side via `SubmitPerformanceAttempt`; these helpers only parse the note
// ! structure for rendering and shape the submission JSON. Kept DOM-free for
// ! `just test-ts`.
// !
// ! RETRIEVAL INTEGRITY (C11): the *render* model NEVER carries an answer key —
// ! `parseSteps` drops `answer_key`, and `options[]` are the label-stripped
// ! candidates only (nothing marks which is correct). The correct value is
// ! surfaced ONLY post-submit via `buildRevealModel`, mirroring the existing
// ! client-side stripping discipline.

/** Field order of the "Ankountant TBS" note type (mirrors tbs_fields). */
export const TBS_FIELD = {
    tbsType: 0,
    prompt: 1,
    exhibitsJson: 2,
    stepsJson: 3,
    schemaTag: 4,
    sourcePassage: 5,
} as const;

export type TbsShape = "journal_entry" | "numeric" | "research" | "doc_review";

/** UI metadata for the four TBS shapes, in the order shown by the TBS-tab
 *  chooser. Lets the learner pick which kind of simulation to practise. */
export interface TbsShapeInfo {
    shape: TbsShape;
    label: string;
    /** Decorative glyph (no icon-font dependency), matching the workspace switcher. */
    glyph: string;
    /** One-line description of the task type shown under the chooser. */
    blurb: string;
}

export const TBS_SHAPES: readonly TbsShapeInfo[] = [
    {
        shape: "journal_entry",
        label: "Journal Entry",
        glyph: "▤",
        blurb: "Record the debits and credits for a transaction.",
    },
    {
        shape: "numeric",
        label: "Numeric",
        glyph: "▦",
        blurb: "Compute the value for each cell.",
    },
    {
        shape: "research",
        label: "Research",
        glyph: "⌕",
        blurb: "Find the governing authoritative citation.",
    },
    {
        shape: "doc_review",
        label: "Doc Review",
        glyph: "▥",
        blurb: "Choose the correct treatment for each blank in the document.",
    },
];

export function tbsShapeSearchOrder(selected: TbsShape): TbsShape[] {
    const shapes = TBS_SHAPES.map((shape) => shape.shape);
    return [selected, ...shapes.filter((shape) => shape !== selected)];
}

export type RenderableTbsShape = "journal_entry" | "numeric";

export function renderableTbsShape(shape: TbsShape): RenderableTbsShape {
    if (shape === "journal_entry" || shape === "numeric") {
        return shape;
    }
    throw new Error(`TbsSurface cannot render ${shape}; use the specialized ${shape} surface.`);
}

export function defaultStepLabel(id: string): string {
    const match = id.trim().match(/^([a-z])(\d+)$/i);
    if (!match) {
        return id;
    }
    const [, prefix, ordinal] = match;
    switch (prefix.toLowerCase()) {
        case "l":
            return `Line ${ordinal}`;
        case "c":
            return `Cell ${ordinal}`;
        case "b":
            return `Blank ${ordinal}`;
        default:
            return id;
    }
}

export function tbsSurfaceTitle(shape: RenderableTbsShape): string {
    switch (shape) {
        case "journal_entry":
            return "Journal entry simulation";
        case "numeric":
            return "Numeric simulation";
    }
}

/** Build the sealed-bank search that finds TBS notes of a given shape in a
 *  section (mirrors the research/doc-review page loaders). `shape` is the value
 *  stored in the `tbs_type` note field. */
export function tbsSearch(shape: TbsShape, section: string): string {
    return `"note:Ankountant TBS" "tbs_type:${shape}" deck:Ankountant::Sealed::${section}::*`;
}

/** The CPA sections the engine covers (ADR 0008). */
export const SECTIONS = ["AUD", "FAR", "REG", "BAR", "ISC", "TCP"] as const;
export type Section = (typeof SECTIONS)[number];
export const DEFAULT_SECTION: Section = "FAR";
export const SECTION_SEARCH_ORDER: readonly Section[] = [
    DEFAULT_SECTION,
    ...SECTIONS.filter((section) => section !== DEFAULT_SECTION),
];
export const ALL_SECTIONS = "ALL";
export type SectionChoice = Section | typeof ALL_SECTIONS;
export const TBS_SECTION_CHOICES: readonly SectionChoice[] = [
    ALL_SECTIONS,
    ...SECTION_SEARCH_ORDER,
];

export function sectionChoiceSearchOrder(choice: SectionChoice): readonly Section[] {
    return choice === ALL_SECTIONS ? SECTION_SEARCH_ORDER : [choice];
}

export function sectionChoiceFromModel(section: string | undefined): SectionChoice {
    const code = section?.trim().toUpperCase();
    if (!code) {
        return ALL_SECTIONS;
    }
    if ((SECTIONS as readonly string[]).includes(code)) {
        return code as Section;
    }
    throw new Error(`Unknown CPA section: ${code}`);
}

export function sectionChoiceLabel(choice: SectionChoice): string {
    return choice === ALL_SECTIONS ? "All sections" : choice;
}

export function sectionSearchOrder(section: string | null): readonly Section[] {
    const code = section?.trim().toUpperCase();
    if (!code) {
        return SECTION_SEARCH_ORDER;
    }
    if ((SECTIONS as readonly string[]).includes(code)) {
        return [code as Section];
    }
    throw new Error(`Unknown CPA section: ${code}`);
}

const SEC_TAG_PREFIX = "sec::";

/** Typed exhibit kinds (mirrors the Rust SeedExhibit `kind`). */
export type ExhibitKind =
    | "text"
    | "email"
    | "invoice"
    | "table"
    | "statement"
    | "memo"
    | "document"
    | "stamp";

/** A single typed exhibit shown alongside the task. `role:"document"` marks the
 *  doc-review primary document (its body carries `<blank step="id">` markers);
 *  `kind:"table"` carries `columns`/`rows`. */
export interface Exhibit {
    id?: string;
    title: string;
    kind: ExhibitKind;
    role?: string;
    body: string;
    columns?: string[];
    rows?: string[][];
}

/** A candidate option for a doc-review blank — label-stripped (nothing here
 *  marks which option is correct; that stays server-side). */
export interface RenderOption {
    id: string;
    text: string;
    kind: string;
}

/**
 * A gradable step, WITHOUT its answer key. For a journal-entry step the client
 * edits account/side/amount; for numeric a value cell; for a doc-review blank a
 * `<select>` of `options`; for research a citation input.
 */
export interface RenderStep {
    id: string;
    label: string;
    weight: number;
    /** Step kind (citation | blank | je | numeric); undefined for legacy steps. */
    kind?: string;
    /** doc-review blank candidates (label-stripped). */
    options?: RenderOption[];
    /** doc-review blank's original document text (safe to show). */
    originalText?: string;
    /** research hint: which bundled corpus passages back the answer. */
    corpusRefs?: string[];
}

export interface TbsModel {
    shape: TbsShape;
    section: string;
    prompt: string;
    exhibits: Exhibit[];
    steps: RenderStep[];
    /** doc-review only: the primary document body (with `<blank>` markers). */
    document?: string;
}

function errorMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}

function parseJsonArray(fieldName: string, raw: string | undefined): unknown[] {
    if (raw === undefined || raw.trim() === "") {
        throw new Error(`${fieldName} is missing.`);
    }
    try {
        const parsed = JSON.parse(raw);
        if (!Array.isArray(parsed)) {
            throw new Error(`${fieldName} must be an array.`);
        }
        return parsed;
    } catch (error) {
        if (error instanceof SyntaxError) {
            throw new Error(`Invalid ${fieldName}: ${errorMessage(error)}`);
        }
        throw error;
    }
}

function jsonObject(raw: unknown, fieldName: string): Record<string, unknown> {
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
        throw new Error(`${fieldName} must be an object.`);
    }
    return raw as Record<string, unknown>;
}

const EXHIBIT_KINDS: ExhibitKind[] = [
    "text",
    "email",
    "invoice",
    "table",
    "statement",
    "memo",
    "document",
    "stamp",
];

function parseExhibitKind(raw: unknown, fieldName: string): ExhibitKind {
    if (raw === undefined) {
        return "text";
    }
    if (typeof raw !== "string" || !EXHIBIT_KINDS.includes(raw as ExhibitKind)) {
        throw new Error(`${fieldName} has unknown exhibit kind: ${String(raw)}`);
    }
    return raw as ExhibitKind;
}

function asStringArray(v: unknown): string[] | undefined {
    if (!Array.isArray(v)) {
        return undefined;
    }
    return v.map((x) => String(x ?? ""));
}

/** Parse exhibits_json into typed exhibits. */
export function parseExhibits(raw: string | undefined): Exhibit[] {
    const parsed = parseJsonArray("exhibits_json", raw);
    return parsed.map((e, i) => {
        const obj = jsonObject(e, `exhibits_json[${i}]`);
        const kind = parseExhibitKind(obj.kind, `exhibits_json[${i}].kind`);
        const rows = Array.isArray(obj.rows)
            ? (obj.rows as unknown[]).map((r) => asStringArray(r) ?? [])
            : undefined;
        return {
            id: typeof obj.id === "string" ? obj.id : undefined,
            title: typeof obj.title === "string" ? obj.title : `Exhibit ${i + 1}`,
            kind,
            role: typeof obj.role === "string" ? obj.role : undefined,
            body: typeof obj.body === "string" ? obj.body : "",
            columns: asStringArray(obj.columns),
            rows,
        };
    });
}

interface RawOption {
    id?: unknown;
    text?: unknown;
    kind?: unknown;
}

interface RawStep {
    id?: unknown;
    label?: unknown;
    weight?: unknown;
    kind?: unknown;
    options?: unknown;
    original_text?: unknown;
    corpus_refs?: unknown;
    // NOTE: `answer_key` is deliberately NOT read here (retrieval integrity C11).
}

const OPTION_KINDS = ["keep", "delete", "replace"] as const;

function parseOptionKind(raw: unknown, fieldName: string): string {
    if (raw === undefined) {
        return "replace";
    }
    if (typeof raw !== "string" || !OPTION_KINDS.includes(raw as (typeof OPTION_KINDS)[number])) {
        throw new Error(`${fieldName} has unknown option kind: ${String(raw)}`);
    }
    return raw;
}

function parseOptions(raw: unknown, stepId: string): RenderOption[] | undefined {
    if (raw === undefined) {
        return undefined;
    }
    if (!Array.isArray(raw)) {
        throw new Error(`Options for ${stepId} must be an array.`);
    }
    if (raw.length === 0) {
        throw new Error(`Options for ${stepId} must contain at least one option.`);
    }
    return raw.map((o, i) => {
        const obj = jsonObject(o, `Option ${i + 1} for ${stepId}`) as RawOption;
        if (typeof obj.id !== "string" || obj.id.trim() === "") {
            throw new Error(`Option ${i + 1} for ${stepId} is missing an id.`);
        }
        if (typeof obj.text !== "string" || obj.text.trim() === "") {
            throw new Error(`Option ${obj.id} for ${stepId} is missing text.`);
        }
        return {
            id: obj.id,
            text: obj.text,
            kind: parseOptionKind(obj.kind, `Option ${obj.id} for ${stepId}`),
        };
    });
}

function parseStepWeight(raw: unknown, defaultWeight: number, fieldName: string): number {
    if (raw === undefined) {
        return defaultWeight;
    }
    if (typeof raw !== "number" || !Number.isFinite(raw) || raw < 0) {
        throw new Error(`${fieldName}.weight must be a nonnegative finite number.`);
    }
    return raw;
}

/**
 * Parse steps_json into render steps, stripping the answer_key. Weights default
 * to 1/N (matching the Rust default_weight) so the rendered total reconciles
 * with the A10 grading.
 */
export function parseSteps(raw: string | undefined): RenderStep[] {
    const parsed = parseJsonArray("steps_json", raw) as RawStep[];
    if (parsed.length === 0) {
        throw new Error("steps_json must contain at least one step.");
    }
    const defaultWeight = 1 / parsed.length;
    const seenIds = new Set<string>();
    const steps = parsed.map((s, i) => {
        const obj = jsonObject(s, `steps_json[${i}]`) as RawStep;
        if (typeof obj.id !== "string" || obj.id.trim() === "") {
            throw new Error(`steps_json[${i}].id is missing.`);
        }
        const id = obj.id;
        if (seenIds.has(id)) {
            throw new Error(`steps_json has duplicate step id: ${id}.`);
        }
        seenIds.add(id);
        const label = typeof obj.label === "string" && obj.label.trim() !== ""
            ? obj.label
            : defaultStepLabel(id);
        const weight = parseStepWeight(obj.weight, defaultWeight, `steps_json[${i}]`);
        const step: RenderStep = { id, label, weight };
        if (typeof obj.kind === "string") {
            step.kind = obj.kind;
        }
        const options = parseOptions(obj.options, id);
        if (step.kind === "blank" && !options) {
            throw new Error(`Options for ${id} must be an array.`);
        }
        if (options) {
            step.options = options;
        }
        if (typeof obj.original_text === "string") {
            step.originalText = obj.original_text;
        }
        const corpusRefs = asStringArray(obj.corpus_refs);
        if (corpusRefs) {
            step.corpusRefs = corpusRefs;
        }
        return step;
    });
    const totalWeight = steps.reduce((sum, step) => sum + step.weight, 0);
    if (Math.abs(totalWeight - 1) > 1e-6) {
        throw new Error("steps_json weights must sum to 1.0.");
    }
    return steps;
}

export function sectionFromTags(tags: string[] | undefined): Section {
    const t = (tags ?? []).find((x) => x.startsWith(SEC_TAG_PREFIX));
    if (!t) {
        return DEFAULT_SECTION;
    }
    const code = t.slice(SEC_TAG_PREFIX.length).trim().toUpperCase();
    if ((SECTIONS as readonly string[]).includes(code)) {
        return code as Section;
    }
    throw new Error(`Unknown CPA section tag: ${t}`);
}

/** Build the full TBS render model from a note's raw fields (+ tags for section). */
export function buildTbsModel(fields: string[], tags?: string[]): TbsModel {
    const shapeRaw = fields[TBS_FIELD.tbsType];
    if (
        !shapeRaw
        || !["journal_entry", "numeric", "research", "doc_review"].includes(shapeRaw)
    ) {
        throw new Error(`Unsupported tbs_type: ${shapeRaw ?? ""}`);
    }
    const shape = shapeRaw as TbsShape;
    const prompt = fields[TBS_FIELD.prompt];
    if (prompt === undefined || prompt.trim() === "") {
        throw new Error("prompt is missing.");
    }
    const exhibits = parseExhibits(fields[TBS_FIELD.exhibitsJson]);
    const doc = exhibits.find((e) => e.role === "document");
    const steps = parseSteps(fields[TBS_FIELD.stepsJson]);
    const document = doc?.body;
    if (shape === "doc_review") {
        validateDocReviewDocument(document, steps);
    }
    return {
        shape,
        section: sectionFromTags(tags),
        prompt,
        exhibits,
        steps,
        document,
    };
}

function validateDocReviewDocument(document: string | undefined, steps: RenderStep[]): void {
    if (document === undefined || document.trim() === "") {
        throw new Error("doc_review document exhibit is missing.");
    }
    const blankIds = segmentDocument(document)
        .filter((segment) => segment.type === "blank")
        .map((segment) => segment.blankId);
    if (blankIds.length === 0) {
        throw new Error("doc_review document has no blank markers.");
    }
    const stepIds = new Set(steps.map((step) => step.id));
    const missingStep = blankIds.find((blankId) => !stepIds.has(blankId));
    if (missingStep) {
        throw new Error(`doc_review blank ${missingStep} has no step.`);
    }
}

/** Exhibits shown in the exhibits pane (everything except the doc-review doc). */
export function paneExhibits(model: TbsModel): Exhibit[] {
    return model.exhibits.filter((e) => e.role !== "document");
}

// --- Document segmentation (doc-review) --------------------------------------

export type DocSegment =
    | { type: "text"; key: string; text: string }
    | { type: "blank"; key: string; blankId: string; original: string };

const BLANK_RE = /<blank\s+step="([^"]+)">([\s\S]*?)<\/blank>/g;

/** Split a doc-review document body into text + blank segments. Each `<blank
 *  step="id">original</blank>` marker becomes a blank segment referencing a
 *  step id; everything else is literal text. */
export function segmentDocument(body: string | undefined): DocSegment[] {
    if (!body) {
        return [];
    }
    const segments: DocSegment[] = [];
    let last = 0;
    let n = 0;
    BLANK_RE.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = BLANK_RE.exec(body)) !== null) {
        if (m.index > last) {
            segments.push({ type: "text", key: `t${n}`, text: body.slice(last, m.index) });
            n += 1;
        }
        segments.push({
            type: "blank",
            key: `b${n}`,
            blankId: m[1],
            original: m[2],
        });
        n += 1;
        last = m.index + m[0].length;
    }
    if (last < body.length) {
        segments.push({ type: "text", key: `t${n}`, text: body.slice(last) });
    }
    return segments;
}

// --- Submission builders -----------------------------------------------------

/** One journal-entry line as edited in the grid. */
export interface JeLineInput {
    id: string;
    label?: string;
    account: string;
    side: string;
    amount: string;
    /** When true the line is intentionally blank ("no entry required"). */
    noEntry?: boolean;
}

const DECIMAL_NUMBER_RE = /^[+-]?(?:\d+\.?\d*|\.\d+)$/;

function submissionNumber(raw: string, fieldName: string): number | "" {
    const trimmed = raw.trim();
    if (trimmed === "") {
        return "";
    }
    if (!DECIMAL_NUMBER_RE.test(trimmed)) {
        throw new Error(`${fieldName} must be a decimal number.`);
    }
    const value = Number(trimmed);
    if (!Number.isFinite(value)) {
        throw new Error(`${fieldName} must be a finite number.`);
    }
    return value;
}

/** Shape the submission_json for a journal-entry TBS. A "no entry" line submits
 *  empty values (graded incorrect if the line was required — the exam shows
 *  spare rows, so not every row must be used). */
export function buildJeSubmission(lines: JeLineInput[]): string {
    return JSON.stringify({
        steps: lines.map((l) => ({
            id: l.id,
            value: l.noEntry
                ? { account: "", side: "", amount: "" }
                : {
                    account: l.account,
                    side: l.side,
                    amount: submissionNumber(
                        l.amount,
                        `Amount for ${l.label ?? defaultStepLabel(l.id)}`,
                    ),
                },
        })),
    });
}

/** One numeric cell as edited. */
export interface NumericCellInput {
    id: string;
    label?: string;
    value: string;
}

/** Shape the submission_json for a numeric TBS. */
export function buildNumericSubmission(cells: NumericCellInput[]): string {
    return JSON.stringify({
        steps: cells.map((c) => ({
            id: c.id,
            value: submissionNumber(c.value, `Value for ${c.label ?? defaultStepLabel(c.id)}`),
        })),
    });
}

/** Shape the submission_json for a research TBS (one citation; the backend
 *  research arm reads `citation`). */
export function buildResearchSubmission(citation: string): string {
    return JSON.stringify({ citation: citation.trim() });
}

/** Shape the submission_json for a doc-review TBS (all blanks in one attempt;
 *  each value is the chosen option id, matched server-side against the blank's
 *  answer_key option id). */
export function docReviewAnswersComplete(blanks: { id: string; value: string }[]): boolean {
    return blanks.length > 0 && blanks.every((blank) => blank.value.trim() !== "");
}

export function buildDocReviewSubmission(blanks: { id: string; value: string }[]): string {
    if (!docReviewAnswersComplete(blanks)) {
        throw new Error("Doc-review submission requires a selected option for every blank.");
    }
    return JSON.stringify({ steps: blanks.map((b) => ({ id: b.id, value: b.value.trim() })) });
}

// --- Post-submit reveal (Results layer) --------------------------------------
// Built ONLY after submit. It resolves the answer key from the raw note fields
// (already in memory from getNote) into a human-readable correct value; it is
// never used to render anything before the learner submits.

export interface StepReveal {
    id: string;
    label: string;
    correctText: string;
}

export interface RevealModel {
    steps: StepReveal[];
    /** Item-level authoritative basis / provenance (source_passage field). */
    source: string;
    /** Blueprint-ish tag: section + the item's ds:: schema tag. */
    section: string;
    schemaTag: string;
}

export type RevealResultStatus = "correct" | "incorrect" | "ungraded";

export interface RevealResultPresentation {
    status: RevealResultStatus;
    mark: string;
    ariaLabel: string;
}

export function revealResultPresentation(
    stepId: string,
    results: readonly { id: string; correct: boolean }[],
): RevealResultPresentation {
    const result = results.find((r) => r.id === stepId);
    if (!result) {
        return { status: "ungraded", mark: "-", ariaLabel: "Not graded" };
    }
    return result.correct
        ? { status: "correct", mark: "✓", ariaLabel: "You were correct" }
        : { status: "incorrect", mark: "✗", ariaLabel: "You were incorrect" };
}

interface RawRevealStep {
    id?: unknown;
    label?: unknown;
    kind?: unknown;
    answer_key?: unknown;
    options?: unknown;
}

function optionText(options: unknown, id: string): string {
    if (!Array.isArray(options)) {
        return id;
    }
    for (const o of options) {
        const obj = (o ?? {}) as RawOption;
        if (obj.id === id) {
            return typeof obj.text === "string" ? obj.text : id;
        }
    }
    return id;
}

function revealCorrect(step: RawRevealStep): string {
    const key = step.answer_key;
    if (step.kind === "blank" && typeof key === "string") {
        return optionText(step.options, key);
    }
    if (Array.isArray(key)) {
        return key.map((k) => String(k)).join(" / ");
    }
    if (key && typeof key === "object") {
        const o = key as Record<string, unknown>;
        if ("account" in o) {
            return `${String(o.side ?? "").toUpperCase()} ${String(o.account ?? "")} ${String(o.amount ?? "")}`.trim();
        }
        return JSON.stringify(key);
    }
    return key === undefined || key === null ? "" : String(key);
}

/** Build the post-submit reveal model from the raw note fields. */
export function buildRevealModel(fields: string[], tags?: string[]): RevealModel {
    const rawSteps = parseJsonArray(
        "steps_json",
        fields[TBS_FIELD.stepsJson],
    ) as RawRevealStep[];
    const rendered = parseSteps(fields[TBS_FIELD.stepsJson]);
    const labelById = new Map(rendered.map((s) => [s.id, s.label]));
    const steps: StepReveal[] = rawSteps.map((s, i) => {
        const id = typeof s.id === "string" ? s.id : `s${i + 1}`;
        return {
            id,
            label: labelById.get(id) ?? id,
            correctText: revealCorrect(s),
        };
    });
    return {
        steps,
        source: fields[TBS_FIELD.sourcePassage] ?? "",
        section: sectionFromTags(tags),
        schemaTag: fields[TBS_FIELD.schemaTag] ?? "",
    };
}

// --- Controlled chart of accounts (JE upgrade) -------------------------------
// A curated account picker (not free text) covering the seeded JE items plus
// common FAR accounts. The real exam supplies a per-item list; this is a
// pragmatic superset until per-item account lists are authored.
export const JE_ACCOUNTS: string[] = [
    "Cash",
    "Accounts Receivable",
    "Allowance for Doubtful Accounts",
    "Inventory",
    "Prepaid Expenses",
    "Land",
    "Building",
    "Equipment",
    "ROU Asset",
    "Right-of-Use Asset",
    "Accumulated Depreciation",
    "Patent",
    "Accounts Payable",
    "Lease Liability",
    "Bonds Payable",
    "Discount on Bonds Payable",
    "Deferred Tax Liability",
    "Income Tax Payable",
    "Common Stock",
    "Common Stock Dividend Distributable",
    "Additional Paid-in Capital",
    "Retained Earnings",
    "Treasury Stock",
    "Unrealized Holding Gain - Income",
    "Unrealized Holding Gain - OCI",
    "Fair Value Adjustment - Trading",
    "Fair Value Adjustment (AFS)",
    "Interest Expense",
    "Income Tax Expense",
    "Repairs and Maintenance Expense",
    "Research and Development Expense",
    "Loss on Sale of A/R",
    "COGS",
];
