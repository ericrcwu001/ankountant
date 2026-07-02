// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

// ! The client-bundled, per-section authoritative-literature corpus (OQ-3:
// ! search is client-side over this bundled data). This MIRRORS the backend
// ! source of truth `rslib/src/ankountant/seed_literature.json` — keep the two
// ! in sync (a build-time copy/generation is a future hardening).
// !
// ! Per ADR 0006 / ADR 0008 / D10 the corpus is per-body:
// !  - FASB ASC (FAR/BAR): `verbatim:false` — OUR paraphrase + a deep link;
// !    verbatim ASC prose is NEVER shipped (Tier-B firewall).
// !  - IRC/PCAOB/NIST (REG/TCP/AUD/ISC): `verbatim:true` — real public-domain text.

export interface CorpusEntry {
    id: string;
    citation: string;
    title: string;
    /** Paraphrase (cite-only) OR real verbatim public-domain text. */
    body: string;
    deepLink?: string;
    verbatim: boolean;
    tags?: string[];
}

export const CORPUS: Record<string, CorpusEntry[]> = {
    FAR: [
        {
            id: "asc-842-20-25-1",
            citation: "ASC 842-20-25-1",
            title: "Leases — Lessee initial recognition at the commencement date",
            body:
                "Our paraphrase (Tier-B cite-only; see the Codification for the authoritative text): at the lease commencement date the lessee recognizes a right-of-use asset and a lease liability. The liability is the present value of the lease payments not yet paid; the right-of-use asset is that liability plus payments made at/before commencement and initial direct costs, less incentives.",
            deepLink: "https://asc.fasb.org/842-20-25-1",
            verbatim: false,
            tags: ["lease", "recognition", "commencement", "ROU"],
        },
        {
            id: "asc-606-10-32-31",
            citation: "ASC 606-10-32-31",
            title: "Revenue — Allocating the transaction price (Step 4)",
            body:
                "Our paraphrase (Tier-B cite-only): the transaction price is allocated to each distinct performance obligation in proportion to relative standalone selling prices, so each obligation gets the consideration the entity expects for satisfying it.",
            deepLink: "https://asc.fasb.org/606-10-32-31",
            verbatim: false,
            tags: ["revenue", "allocation", "SSP", "step4"],
        },
        {
            id: "asc-606-10-25-27",
            citation: "ASC 606-10-25-27",
            title: "Revenue — Performance obligations satisfied over time (Step 5)",
            body:
                "Our paraphrase (Tier-B cite-only): recognize revenue over time when one of three criteria is met (customer simultaneously receives/consumes the benefit; performance creates/enhances a customer-controlled asset; or no alternative use plus an enforceable right to payment for work to date). Otherwise recognize at the point control transfers.",
            deepLink: "https://asc.fasb.org/606-10-25-27",
            verbatim: false,
            tags: ["revenue", "over-time", "point-in-time", "step5"],
        },
        {
            id: "asc-360-10-30-1",
            citation: "ASC 360-10-30-1",
            title: "Property, plant, and equipment — Initial measurement",
            body:
                "Our paraphrase (Tier-B cite-only): PP&E is initially measured at historical cost — the costs necessary to bring the asset to the condition and location for its intended use (purchase price, freight-in, installation, testing). Costs that do not ready the asset (operator training, first-year insurance) are period costs.",
            deepLink: "https://asc.fasb.org/360-10-30-1",
            verbatim: false,
            tags: ["PP&E", "capitalize", "historical-cost"],
        },
    ],
    BAR: [
        {
            id: "asc-280-10-50-12",
            citation: "ASC 280-10-50-12",
            title: "Segment reporting — Quantitative thresholds",
            body:
                "Our paraphrase (Tier-B cite-only): an operating segment is separately reportable if it meets any 10% threshold — reported revenue (external + intersegment) ≥ 10% of combined revenue; |profit or loss| ≥ 10% of the greater (absolute) of combined profit of profitable segments or combined loss of loss segments; or assets ≥ 10% of combined assets.",
            deepLink: "https://asc.fasb.org/280-10-50-12",
            verbatim: false,
            tags: ["segment", "reportable", "thresholds"],
        },
    ],
    REG: [
        {
            id: "irc-162",
            citation: "IRC §162(a)",
            title: "Trade or business expenses — ordinary and necessary",
            body:
                "26 U.S.C. §162(a) (public domain): \"There shall be allowed as a deduction all the ordinary and necessary expenses paid or incurred during the taxable year in carrying on any trade or business, including— (1) a reasonable allowance for salaries or other compensation for personal services actually rendered; (2) traveling expenses (including amounts expended for meals and lodging other than amounts which are lavish or extravagant under the circumstances) while away from home in the pursuit of a trade or business; and (3) rentals or other payments required to be made as a condition to the continued use or possession, for purposes of the trade or business, of property to which the taxpayer has not taken or is not taking title or in which he has no equity.\"",
            deepLink: "https://www.law.cornell.edu/uscode/text/26/162",
            verbatim: true,
            tags: ["deduction", "trade-or-business", "ordinary-and-necessary"],
        },
        {
            id: "irc-263",
            citation: "IRC §263(a)",
            title: "Capital expenditures — no current deduction",
            body:
                "26 U.S.C. §263(a) (public domain): \"No deduction shall be allowed for— (1) Any amount paid out for new buildings or for permanent improvements or betterments made to increase the value of any property or estate.\" (Statutory exceptions (A)–(L) omitted.)",
            deepLink: "https://www.law.cornell.edu/uscode/text/26/263",
            verbatim: true,
            tags: ["capitalize", "capital-expenditure", "improvements"],
        },
    ],
    TCP: [
        {
            id: "irc-179",
            citation: "IRC §179(a)",
            title: "Election to expense certain depreciable business assets",
            body:
                "26 U.S.C. §179(a) (public domain): \"A taxpayer may elect to treat the cost of any section 179 property as an expense which is not chargeable to capital account. Any cost so treated shall be allowed as a deduction for the taxable year in which the section 179 property is placed in service.\"",
            deepLink: "https://www.law.cornell.edu/uscode/text/26/179",
            verbatim: true,
            tags: ["cost-recovery", "expensing", "election"],
        },
    ],
    AUD: [
        {
            id: "pcaob-as-1105",
            citation: "AS 1105",
            title: "Audit Evidence (sufficiency and appropriateness)",
            body:
                "PCAOB AS 1105.04 (public domain): \"Audit evidence is all the information, whether obtained from audit procedures or other sources, that is used by the auditor in arriving at the conclusions on which the auditor's opinion is based. Audit evidence consists of both information that supports and corroborates management's assertions regarding the financial statements or internal control over financial reporting and information that contradicts such assertions.\" AS 1105.06: to be appropriate, audit evidence must be both relevant and reliable; sufficiency measures the quantity of audit evidence.",
            deepLink: "https://pcaobus.org/oversight/standards/auditing-standards/details/AS1105",
            verbatim: true,
            tags: ["audit-evidence", "sufficient", "appropriate"],
        },
    ],
    ISC: [
        {
            id: "nist-csf-2-0",
            citation: "NIST CSF 2.0",
            title: "NIST Cybersecurity Framework 2.0 — Core Functions",
            body:
                "NIST Cybersecurity Framework (CSF) 2.0 (public domain): the CSF Core is organized into six Functions — Govern, Identify, Protect, Detect, Respond, and Recover. Govern (new in 2.0) establishes and monitors the organization's cybersecurity risk-management strategy, expectations, and policy; the other five organize outcomes for understanding, safeguarding against, detecting, responding to, and recovering from cybersecurity risks.",
            deepLink: "https://www.nist.gov/cyberframework",
            verbatim: true,
            tags: ["NIST", "CSF", "controls", "governance"],
        },
    ],
};
