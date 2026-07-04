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
