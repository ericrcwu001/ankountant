// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

const TOPIC_LABELS: Record<string, string> = {
    capitalize_vs_expense: "Capitalization vs expense",
    cash_receivables: "Cash & receivables",
    conceptual_framework: "Conceptual framework",
    debt_extinguishment: "Debt extinguishment",
    financial_statements: "Financial statements",
    government_nfp: "Government & NFP",
    intangibles_impairment: "Intangibles & impairment",
    inventory_valuation: "Inventory valuation",
    operating_vs_finance_lease: "Operating vs finance leases",
    pensions_equity: "Pensions & equity",
    revrec_step_selection: "Revenue recognition",
    tax_timing: "Tax timing",
    trading_afs_htm: "Trading, AFS & HTM securities",
};

const ACRONYMS = new Set(["afs", "aud", "far", "htm", "isc", "nfp", "ppe", "reg", "tcp"]);

export function topicLabel(setId: string): string {
    const known = TOPIC_LABELS[setId];
    if (known) {
        return known;
    }
    return fallbackTopicLabel(setId);
}

export function topicSentenceLabel(setId: string): string {
    const label = topicLabel(setId);
    if (/^[A-Z][a-z]/.test(label)) {
        return label[0].toLowerCase() + label.slice(1);
    }
    return label;
}

function fallbackTopicLabel(setId: string): string {
    const words = setId.trim().replace(/^(far|aud|reg|tcp|isc)_/, "").split(/_+/);
    return words
        .filter(Boolean)
        .map((word, index) => {
            const lower = word.toLowerCase();
            if (ACRONYMS.has(lower)) {
                return lower.toUpperCase();
            }
            return index === 0 ? lower[0].toUpperCase() + lower.slice(1) : lower;
        })
        .join(" ");
}
