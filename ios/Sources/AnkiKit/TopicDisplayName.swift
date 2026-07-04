// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

public func topicDisplayName(_ setId: String) -> String {
    if let label = topicDisplayNames[setId] {
        return label
    }
    return fallbackTopicDisplayName(setId)
}

public func topicSentenceName(_ setId: String) -> String {
    let label = topicDisplayName(setId)
    guard let first = label.first, first.isUppercase else {
        return label
    }
    let tail = label.dropFirst()
    guard tail.first?.isLowercase == true else {
        return label
    }
    return first.lowercased() + String(tail)
}

public func schemaTagDisplayName(_ schemaTag: String) -> String {
    if let label = schemaTagDisplayNames[schemaTag] {
        return label
    }
    return fallbackSchemaTagDisplayName(schemaTag)
}

private let topicDisplayNames: [String: String] = [
    "capitalize_vs_expense": "Capitalization vs expense",
    "cash_receivables": "Cash & receivables",
    "conceptual_framework": "Conceptual framework",
    "debt_extinguishment": "Debt extinguishment",
    "financial_statements": "Financial statements",
    "government_nfp": "Government & NFP",
    "intangibles_impairment": "Intangibles & impairment",
    "inventory_valuation": "Inventory valuation",
    "operating_vs_finance_lease": "Operating vs finance leases",
    "pensions_equity": "Pensions & equity",
    "revrec_step_selection": "Revenue recognition",
    "tax_timing": "Tax timing",
    "trading_afs_htm": "Trading, AFS & HTM securities",
]

private let schemaTagDisplayNames: [String: String] = [
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
]

private let topicAcronyms: Set<String> = ["afs", "aud", "far", "htm", "isc", "nfp", "ppe", "reg", "tcp"]

private func fallbackTopicDisplayName(_ setId: String) -> String {
    let stripped = setId
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacing(/^(far|aud|reg|tcp|isc)_/, with: "")
    return stripped
        .split(separator: "_")
        .enumerated()
        .map { index, word in
            let lower = word.lowercased()
            if topicAcronyms.contains(lower) {
                return lower.uppercased()
            }
            return index == 0 ? lower.prefix(1).uppercased() + String(lower.dropFirst()) : lower
        }
        .joined(separator: " ")
}

private func fallbackSchemaTagDisplayName(_ schemaTag: String) -> String {
    let parts = schemaTag
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacing(/^ds::/, with: "")
        .components(separatedBy: "::")
        .filter { !$0.isEmpty }
    guard let tail = parts.last else {
        return ""
    }
    return fallbackTopicDisplayName(tail)
}
