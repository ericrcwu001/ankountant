import Foundation

// Pure helpers for the TBS / Confusion surfaces, ported from the desktop
// ts/routes/(ankountant)/ankountant-tbs/lib.ts and ankountant-confusion/lib.ts.
// The heavy lifting (partial-credit grading) is authoritative on the Rust side
// via SubmitPerformanceAttempt; these helpers only parse the note structure for
// rendering and shape the submission JSON.

/// Field order of the "Ankountant TBS" note type (mirrors tbs_fields).
public enum TbsField {
    public static let tbsType = 0
    public static let prompt = 1
    public static let exhibitsJson = 2
    public static let stepsJson = 3
    public static let schemaTag = 4
}

/// Build the full TBS render model from a note's raw fields.
public func buildTbsModel(fields: [String]) -> TbsModel {
    let shapeRaw = field(fields, TbsField.tbsType) ?? "journal_entry"
    return TbsModel(
        shape: TbsShape(rawValue: shapeRaw) ?? .journalEntry,
        prompt: field(fields, TbsField.prompt) ?? "",
        exhibits: parseExhibits(field(fields, TbsField.exhibitsJson)),
        steps: parseSteps(field(fields, TbsField.stepsJson))
    )
}

/// Parse exhibits_json into a list of {title, body} exhibits.
public func parseExhibits(_ raw: String?) -> [Exhibit] {
    guard let array = jsonArray(raw) else { return [] }
    return array.enumerated().map { index, element in
        let object = element as? [String: Any]
        return Exhibit(
            id: index,
            title: (object?["title"] as? String) ?? "Exhibit \(index + 1)",
            body: (object?["body"] as? String) ?? jsString(element)
        )
    }
}

/// Parse steps_json into render steps, stripping the answer_key. Weights default
/// to 1/N (matching the Rust default_weight) so the rendered total reconciles
/// with the A10 grading.
public func parseSteps(_ raw: String?) -> [RenderStep] {
    guard let array = jsonArray(raw), !array.isEmpty else { return [] }
    let defaultWeight = 1.0 / Double(array.count)
    return array.enumerated().map { index, element in
        let object = element as? [String: Any]
        let id = (object?["id"] as? String) ?? "s\(index + 1)"
        return RenderStep(
            id: id,
            label: (object?["label"] as? String) ?? id,
            weight: (object?["weight"] as? Double) ?? defaultWeight
        )
    }
}

/// Shape the submission_json for a journal-entry TBS.
public func buildJeSubmission(_ lines: [JeLineInput]) -> String {
    let steps = lines.map { line -> [String: Any] in
        [
            "id": line.id,
            "value": [
                "account": line.account,
                "side": line.side,
                "amount": numberOrEmpty(line.amount),
            ] as [String: Any],
        ]
    }
    return jsonString(["steps": steps])
}

/// Shape the submission_json for a numeric TBS.
public func buildNumericSubmission(_ cells: [NumericCellInput]) -> String {
    let steps = cells.map { cell -> [String: Any] in
        ["id": cell.id, "value": numberOrEmpty(cell.value)]
    }
    return jsonString(["steps": steps])
}

/// Shape submission_json for a which-treatment (discrimination) choice.
public func buildChoiceSubmission(_ choice: String) -> String {
    jsonString(["choice": choice])
}

/// Confusion review is label-stripped: drop any trailing dev slug like
/// " (capitalize_vs_expense q0)" so the stem never leaks the category.
public func stripConfusionSlug(_ prompt: String) -> String {
    let pattern = #"\s*\([a-z0-9_]+\s+q\d+\)\s*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return prompt
    }
    let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
    var stripped = regex.stringByReplacingMatches(in: prompt, options: [], range: range, withTemplate: "")
    while let last = stripped.last, last.isWhitespace {
        stripped.removeLast()
    }
    return stripped
}

// MARK: - Private helpers

/// Positional field access that tolerates a short field list (out-of-range → nil,
/// mirroring JS `fields[i]` returning `undefined`).
private func field(_ fields: [String], _ index: Int) -> String? {
    fields.indices.contains(index) ? fields[index] : nil
}

/// Parse a top-level JSON array, mirroring lib.ts `safeParse` + `Array.isArray`:
/// nil input, invalid JSON, or a non-array top level all collapse to nil.
private func jsonArray(_ raw: String?) -> [Any]? {
    guard let raw, let data = raw.data(using: .utf8),
          let parsed = try? JSONSerialization.jsonObject(with: data) else {
        return nil
    }
    return parsed as? [Any]
}

/// Serialize a submission payload. Grading parses the JSON back, so key order is
/// irrelevant; sorted here only for deterministic output.
private func jsonString(_ object: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

/// A cell value for a submission: "" when empty, else the parsed number, else the
/// raw string when it does not parse (mirrors lib.ts `x === "" ? "" : Number(x)`).
private func numberOrEmpty(_ raw: String) -> Any {
    if raw.isEmpty { return "" }
    if let number = Double(raw) { return number }
    return raw
}

/// String coercion for an exhibit body fallback, mirroring JS `String(e ?? "")`.
private func jsString(_ element: Any?) -> String {
    switch element {
    case let string as String:
        return string
    case is [String: Any]:
        return "[object Object]"
    case let value? where !(value is NSNull):
        return String(describing: value)
    default:
        return ""
    }
}
