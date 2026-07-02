// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! B1 — a lightweight, UNGRADED scratch formula grid for the exam shell. It is
// ! a candidate's scratchpad only; nothing here is ever submitted or graded.
// ! Supports cell refs (A1), ranges (A1:B3), + - * / and parentheses, and the
// ! functions SUM / AVERAGE / ROUND. DOM-free + pure for `just test-ts`.

export type EvalResult = { ok: true; value: number } | { ok: false; error: string };

/** How many rows/cols the scratch grid renders (A..H x 1..12). */
export const GRID_COLS = 8;
export const GRID_ROWS = 12;

export function colLabel(col: number): string {
    return String.fromCharCode(65 + col); // 0 -> "A"
}

/** "A1" -> {col:0,row:0}; null when not a well-formed ref. */
export function parseRef(ref: string): { col: number; row: number } | null {
    const m = /^([A-Za-z])([0-9]{1,3})$/.exec(ref.trim());
    if (!m) {
        return null;
    }
    const col = m[1].toUpperCase().charCodeAt(0) - 65;
    const row = parseInt(m[2], 10) - 1;
    if (col < 0 || col >= GRID_COLS || row < 0 || row >= GRID_ROWS) {
        return null;
    }
    return { col, row };
}

export function cellKey(col: number, row: number): string {
    return `${colLabel(col)}${row + 1}`;
}

// --- tokenizer ---------------------------------------------------------------

type Tok =
    | { t: "num"; v: number }
    | { t: "ref"; v: string }
    | { t: "ident"; v: string }
    | { t: "op"; v: "+" | "-" | "*" | "/" }
    | { t: "lparen" }
    | { t: "rparen" }
    | { t: "comma" }
    | { t: "colon" };

function tokenize(input: string): Tok[] | null {
    const toks: Tok[] = [];
    let i = 0;
    while (i < input.length) {
        const c = input[i];
        if (c === " " || c === "\t") {
            i += 1;
            continue;
        }
        if (c === "+" || c === "-" || c === "*" || c === "/") {
            toks.push({ t: "op", v: c });
            i += 1;
        } else if (c === "(") {
            toks.push({ t: "lparen" });
            i += 1;
        } else if (c === ")") {
            toks.push({ t: "rparen" });
            i += 1;
        } else if (c === ",") {
            toks.push({ t: "comma" });
            i += 1;
        } else if (c === ":") {
            toks.push({ t: "colon" });
            i += 1;
        } else if (/[0-9.]/.test(c)) {
            let j = i + 1;
            while (j < input.length && /[0-9.]/.test(input[j])) {
                j += 1;
            }
            const v = Number(input.slice(i, j));
            if (!isFinite(v)) {
                return null;
            }
            toks.push({ t: "num", v });
            i = j;
        } else if (/[A-Za-z]/.test(c)) {
            let j = i + 1;
            while (j < input.length && /[A-Za-z0-9]/.test(input[j])) {
                j += 1;
            }
            const word = input.slice(i, j);
            if (parseRef(word)) {
                toks.push({ t: "ref", v: word.toUpperCase() });
            } else {
                toks.push({ t: "ident", v: word.toUpperCase() });
            }
            i = j;
        } else {
            return null;
        }
    }
    return toks;
}

// --- parser + evaluator ------------------------------------------------------

const MAX_DEPTH = 64;

class Parser {
    private pos = 0;
    constructor(
        private toks: Tok[],
        private resolveRaw: (ref: string) => string,
        private seen: Set<string>,
    ) {}

    parse(): number {
        const v = this.expr();
        if (this.pos !== this.toks.length) {
            throw new Error("#SYNTAX");
        }
        return v;
    }

    private peek(): Tok | undefined {
        return this.toks[this.pos];
    }

    private expr(): number {
        let v = this.term();
        for (;;) {
            const t = this.peek();
            if (t && t.t === "op" && (t.v === "+" || t.v === "-")) {
                this.pos += 1;
                const rhs = this.term();
                v = t.v === "+" ? v + rhs : v - rhs;
            } else {
                return v;
            }
        }
    }

    private term(): number {
        let v = this.factor();
        for (;;) {
            const t = this.peek();
            if (t && t.t === "op" && (t.v === "*" || t.v === "/")) {
                this.pos += 1;
                const rhs = this.factor();
                if (t.v === "/" && rhs === 0) {
                    throw new Error("#DIV/0");
                }
                v = t.v === "*" ? v * rhs : v / rhs;
            } else {
                return v;
            }
        }
    }

    private factor(): number {
        const t = this.peek();
        if (!t) {
            throw new Error("#SYNTAX");
        }
        if (t.t === "op" && (t.v === "-" || t.v === "+")) {
            this.pos += 1;
            const v = this.factor();
            return t.v === "-" ? -v : v;
        }
        if (t.t === "num") {
            this.pos += 1;
            return t.v;
        }
        if (t.t === "ref") {
            this.pos += 1;
            return this.resolveRef(t.v);
        }
        if (t.t === "lparen") {
            this.pos += 1;
            const v = this.expr();
            this.expect("rparen");
            return v;
        }
        if (t.t === "ident") {
            return this.func(t.v);
        }
        throw new Error("#SYNTAX");
    }

    private expect(kind: Tok["t"]): void {
        const t = this.peek();
        if (!t || t.t !== kind) {
            throw new Error("#SYNTAX");
        }
        this.pos += 1;
    }

    private func(name: string): number {
        this.pos += 1; // ident
        this.expect("lparen");
        const args: number[] = [];
        if (this.peek()?.t !== "rparen") {
            args.push(...this.arg());
            while (this.peek()?.t === "comma") {
                this.pos += 1;
                args.push(...this.arg());
            }
        }
        this.expect("rparen");
        switch (name) {
            case "SUM":
                return args.reduce((a, b) => a + b, 0);
            case "AVERAGE":
                if (args.length === 0) {
                    throw new Error("#DIV/0");
                }
                return args.reduce((a, b) => a + b, 0) / args.length;
            case "ROUND": {
                if (args.length < 1 || args.length > 2) {
                    throw new Error("#ARGS");
                }
                const digits = args.length === 2 ? Math.trunc(args[1]) : 0;
                const f = Math.pow(10, digits);
                return Math.round(args[0] * f) / f;
            }
            default:
                throw new Error("#NAME");
        }
    }

    /** An argument is either an A1:B2 range (expands to its cells) or an expr. */
    private arg(): number[] {
        const t = this.peek();
        const next = this.toks[this.pos + 1];
        if (t && t.t === "ref" && next && next.t === "colon") {
            this.pos += 2;
            const end = this.peek();
            if (!end || end.t !== "ref") {
                throw new Error("#SYNTAX");
            }
            this.pos += 1;
            return this.expandRange(t.v, end.v).map((r) => this.resolveRef(r));
        }
        return [this.expr()];
    }

    private expandRange(a: string, b: string): string[] {
        const pa = parseRef(a);
        const pb = parseRef(b);
        if (!pa || !pb) {
            throw new Error("#REF");
        }
        const out: string[] = [];
        const c0 = Math.min(pa.col, pb.col);
        const c1 = Math.max(pa.col, pb.col);
        const r0 = Math.min(pa.row, pb.row);
        const r1 = Math.max(pa.row, pb.row);
        for (let r = r0; r <= r1; r++) {
            for (let c = c0; c <= c1; c++) {
                out.push(cellKey(c, r));
            }
        }
        return out;
    }

    private resolveRef(ref: string): number {
        if (this.seen.has(ref)) {
            throw new Error("#CYCLE");
        }
        const raw = (this.resolveRaw(ref) ?? "").trim();
        if (raw === "") {
            return 0;
        }
        if (raw.startsWith("=")) {
            this.seen.add(ref);
            try {
                const r = evalCell(raw, this.resolveRaw, this.seen);
                if (!r.ok) {
                    throw new Error(r.error);
                }
                return r.value;
            } finally {
                this.seen.delete(ref);
            }
        }
        const n = Number(raw.replace(/[$,%\s]/g, ""));
        if (!isFinite(n)) {
            throw new Error("#VALUE");
        }
        return n;
    }
}

/**
 * Evaluate a cell's raw content. A leading `=` marks a formula; otherwise the
 * raw text is returned as a number when numeric, else an error (so a plain text
 * cell used in a formula surfaces `#VALUE`). `resolveRaw` returns another cell's
 * raw content for ref/range resolution.
 */
export function evalCell(
    raw: string,
    resolveRaw: (ref: string) => string,
    seen: Set<string> = new Set(),
): EvalResult {
    const trimmed = (raw ?? "").trim();
    if (!trimmed.startsWith("=")) {
        if (trimmed === "") {
            return { ok: true, value: 0 };
        }
        const n = Number(trimmed.replace(/[$,%\s]/g, ""));
        return isFinite(n) ? { ok: true, value: n } : { ok: false, error: "#VALUE" };
    }
    if (seen.size > MAX_DEPTH) {
        return { ok: false, error: "#DEPTH" };
    }
    const toks = tokenize(trimmed.slice(1));
    if (!toks || toks.length === 0) {
        return { ok: false, error: "#SYNTAX" };
    }
    try {
        return { ok: true, value: new Parser(toks, resolveRaw, seen).parse() };
    } catch (e) {
        return { ok: false, error: e instanceof Error ? e.message : "#ERR" };
    }
}

/** Format a cell for display: formulas show their computed value (or error),
 *  non-formula cells show their raw text unchanged. */
export function displayCell(raw: string, resolveRaw: (ref: string) => string): string {
    const trimmed = (raw ?? "").trim();
    if (!trimmed.startsWith("=")) {
        return raw ?? "";
    }
    const r = evalCell(trimmed, resolveRaw);
    if (!r.ok) {
        return r.error;
    }
    // Trim floating noise for display.
    return String(Math.round(r.value * 1e6) / 1e6);
}
