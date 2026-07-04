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

const SCHEMA_TAG_LABELS: Record<string, string> = {
    "ds::ar::allowance": "Allowance method",
    "ds::ar::writeoff": "Direct write-off",
    "ds::aud::insufficient": "Insufficient evidence",
    "ds::aud::retain": "Retain documentation",
    "ds::aud::revise": "Revise documentation",
    "ds::aud::sufficient": "Sufficient evidence",
    "ds::bar::not_reportable": "Not reportable",
    "ds::bar::reportable": "Reportable segment",
    "ds::concept::faithful": "Faithful representation",
    "ds::concept::relevance": "Relevance",
    "ds::cost::capitalize": "Capitalization",
    "ds::cost::expense": "Expense treatment",
    "ds::debt::extinguish": "Extinguishment",
    "ds::debt::modify": "Modification",
    "ds::govnfp::fund": "Fund statements",
    "ds::govnfp::govtwide": "Government-wide statements",
    "ds::intangible::finite": "Finite-lived intangibles",
    "ds::intangible::indefinite": "Indefinite-lived intangibles",
    "ds::inventory::lcm": "Lower of cost or market",
    "ds::inventory::lcnrv": "Lower of cost and NRV",
    "ds::isc::detective": "Detective control",
    "ds::isc::preventive": "Preventive control",
    "ds::lease::finance": "Finance leases",
    "ds::lease::operating": "Operating leases",
    "ds::pension::interest": "Interest cost",
    "ds::pension::service": "Service cost",
    "ds::reg::capitalize": "Capitalize",
    "ds::reg::deduct": "Deduct",
    "ds::revrec::step4": "Step 4 allocation",
    "ds::revrec::step5": "Step 5 recognition",
    "ds::securities::htm": "HTM securities",
    "ds::securities::trading": "Trading securities",
    "ds::stmt::financing": "Financing activities",
    "ds::stmt::operating": "Operating activities",
    "ds::tax::permanent": "Permanent items",
    "ds::tax::temporary": "Temporary differences",
    "ds::tcp::capitalize": "Capitalize",
    "ds::tcp::expense": "Expense",
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

export function schemaTagLabel(schemaTag: string): string {
    const known = SCHEMA_TAG_LABELS[schemaTag];
    if (known) {
        return known;
    }
    return fallbackSchemaTagLabel(schemaTag);
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

function fallbackSchemaTagLabel(schemaTag: string): string {
    const tail = schemaTag.trim().replace(/^ds::/, "").split(/::+/).filter(Boolean).at(-1);
    return tail ? fallbackTopicLabel(tail) : "";
}
