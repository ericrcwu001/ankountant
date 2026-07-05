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
    active_vs_passive_loss: "Active vs passive losses",
    authentication_vs_authorization: "Authentication vs authorization",
    aud_evidence_sufficiency: "Evidence sufficiency",
    aud_request_relevance: "Request relevance",
    backup_vs_disaster_recovery: "Backup vs disaster recovery",
    basis_vs_amount_realized: "Basis vs amount realized",
    c_corp_vs_s_corp_taxation: "C corp vs S corp taxation",
    operating_vs_finance_lease: "Operating vs finance leases",
    pensions_equity: "Pensions & equity",
    circular230_sanction_vs_tax_penalty: "Circular 230 vs tax penalties",
    deduction_for_vs_from_agi: "For AGI vs from AGI deductions",
    distribution_vs_liquidation: "Distributions vs liquidations",
    gift_vs_estate_tax: "Gift vs estate tax",
    incident_detection_vs_response: "Incident detection vs response",
    isc_control_type: "Control type",
    like_kind_vs_taxable_exchange: "Like-kind vs taxable exchange",
    materiality_vs_trivial_misstatement: "Materiality vs triviality",
    qualified_vs_adverse_opinion: "Qualified vs adverse opinions",
    redemption_vs_dividend: "Redemptions vs dividends",
    revrec_step_selection: "Revenue recognition",
    s1231_vs_capital_vs_ordinary: "Section 1231 vs capital vs ordinary",
    soc1_vs_soc2: "SOC 1 vs SOC 2",
    soc_report_type1_vs_type2: "SOC Type 1 vs Type 2",
    subsequent_events_vs_going_concern: "Subsequent events vs going concern",
    tax_timing: "Tax timing",
    tcp_cost_recovery: "Cost recovery",
    test_of_controls_vs_substantive: "Controls vs substantive procedures",
    trading_afs_htm: "Trading, AFS & HTM securities",
};

const SCHEMA_TAG_LABELS: Record<string, string> = {
    "ds::ar::allowance": "Allowance method",
    "ds::ar::writeoff": "Direct write-off",
    "ds::aud::insufficient": "Insufficient evidence",
    "ds::aud::adverse": "Adverse opinion",
    "ds::aud::controls": "Test of controls",
    "ds::aud::going_concern": "Going concern",
    "ds::aud::material": "Material misstatement",
    "ds::aud::qualified": "Qualified opinion",
    "ds::aud::retain": "Retain documentation",
    "ds::aud::revise": "Revise documentation",
    "ds::aud::subsequent": "Subsequent event",
    "ds::aud::substantive": "Substantive procedure",
    "ds::aud::sufficient": "Sufficient evidence",
    "ds::aud::trivial": "Clearly trivial",
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
    "ds::isc::authentication": "Authentication",
    "ds::isc::authorization": "Authorization",
    "ds::isc::backup": "Backup",
    "ds::isc::detect": "Incident detection",
    "ds::isc::preventive": "Preventive control",
    "ds::isc::recovery": "Disaster recovery",
    "ds::isc::respond": "Incident response",
    "ds::isc::soc1": "SOC 1",
    "ds::isc::soc2": "SOC 2",
    "ds::isc::type1": "Type 1",
    "ds::isc::type2": "Type 2",
    "ds::lease::finance": "Finance leases",
    "ds::lease::operating": "Operating leases",
    "ds::pension::interest": "Interest cost",
    "ds::pension::service": "Service cost",
    "ds::reg::capitalize": "Capitalize",
    "ds::reg::amount_realized": "Amount realized",
    "ds::reg::basis": "Adjusted basis",
    "ds::reg::c_corp": "C corporation",
    "ds::reg::capital": "Capital gain/loss",
    "ds::reg::circular230": "Circular 230 sanction",
    "ds::reg::deduct": "Deduct",
    "ds::reg::for_agi": "Deduction for AGI",
    "ds::reg::from_agi": "Deduction from AGI",
    "ds::reg::ordinary": "Ordinary income",
    "ds::reg::s1231": "Section 1231",
    "ds::reg::s_corp": "S corporation",
    "ds::reg::tax_penalty": "Tax penalty",
    "ds::revrec::step4": "Step 4 allocation",
    "ds::revrec::step5": "Step 5 recognition",
    "ds::securities::htm": "HTM securities",
    "ds::securities::trading": "Trading securities",
    "ds::stmt::financing": "Financing activities",
    "ds::stmt::operating": "Operating activities",
    "ds::tax::permanent": "Permanent items",
    "ds::tax::temporary": "Temporary differences",
    "ds::tcp::capitalize": "Capitalize",
    "ds::tcp::active": "Active business loss",
    "ds::tcp::distribution": "Nonliquidating distribution",
    "ds::tcp::dividend": "Dividend equivalent",
    "ds::tcp::expense": "Expense",
    "ds::tcp::estate": "Estate tax",
    "ds::tcp::gift": "Gift tax",
    "ds::tcp::liquidation": "Complete liquidation",
    "ds::tcp::nonrecognition": "Nonrecognition",
    "ds::tcp::passive": "Passive activity loss",
    "ds::tcp::redemption": "Redemption",
    "ds::tcp::taxable": "Taxable exchange",
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
