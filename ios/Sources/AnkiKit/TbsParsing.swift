public import Foundation

// Pure helpers for the TBS / Confusion surfaces, ported from the desktop
// ts/routes/(ankountant)/ankountant-tbs/lib.ts and ankountant-confusion/lib.ts.
// The heavy lifting (partial-credit grading) is authoritative on the Rust side
// via SubmitPerformanceAttempt; these helpers only parse the note structure for
// rendering and shape the submission JSON.

/// The CPA sections the TBS engine covers (ADR 0008). Mirrors Rust `SECTIONS`.
public let TBS_SECTIONS = ["AUD", "FAR", "REG", "BAR", "ISC", "TCP"]

/// Fallback section for pre-section-dimension notes (mirrors Rust
/// `DEFAULT_SECTION`).
public let TBS_DEFAULT_SECTION = "FAR"

/// Field order of the "Ankountant TBS" note type (mirrors tbs_fields).
public enum TbsField {
    public static let tbsType = 0
    public static let prompt = 1
    public static let exhibitsJson = 2
    public static let stepsJson = 3
    public static let schemaTag = 4
    public static let sourcePassage = 5
}

/// Typed exhibit kinds (mirrors the Rust SeedExhibit `kind`).
private let exhibitKinds: Set<String> = [
    "text", "email", "invoice", "table", "statement", "memo", "document", "stamp",
]

private let optionKinds: Set<String> = ["keep", "delete", "replace"]

public enum TbsParseError: Error, Equatable, LocalizedError, Sendable {
    case missingJson(field: String)
    case invalidJson(field: String, message: String)
    case invalidValue(field: String, message: String)
    case nonArrayJson(field: String)
    case emptySteps
    case unsupportedTbsType(String)
    case unknownSectionTag(String)

    public var errorDescription: String? {
        switch self {
        case let .missingJson(field):
            "\(field) is missing."
        case let .invalidJson(field, message):
            "Invalid \(field): \(message)"
        case let .invalidValue(field, message):
            "Invalid \(field): \(message)"
        case let .nonArrayJson(field):
            "\(field) must be an array."
        case .emptySteps:
            "steps_json must contain at least one step."
        case let .unsupportedTbsType(shape):
            "Unsupported tbs_type: \(shape)"
        case let .unknownSectionTag(tag):
            "Unknown CPA section tag: \(tag)"
        }
    }
}

public enum TbsSubmissionError: Error, Equatable, LocalizedError, Sendable {
    case invalidDecimal(field: String)
    case nonFiniteNumber(field: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidDecimal(field):
            "\(field) must be a decimal number."
        case let .nonFiniteNumber(field):
            "\(field) must be a finite number."
        }
    }
}

/// Build the full TBS render model from a note's raw fields (+ tags for the
/// section, ADR 0008). Mirrors the desktop `buildTbsModel(fields, tags)`.
public func buildTbsModel(fields: [String], tags: [String] = []) throws -> TbsModel {
    let shapeRaw = field(fields, TbsField.tbsType)
    guard let shapeRaw, let shape = TbsShape(rawValue: shapeRaw) else {
        throw TbsParseError.unsupportedTbsType(shapeRaw ?? "")
    }
    guard let prompt = field(fields, TbsField.prompt),
          !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        throw TbsParseError.invalidValue(field: "prompt", message: "missing prompt")
    }
    let exhibits = try parseExhibits(field(fields, TbsField.exhibitsJson))
    let document = exhibits.first(where: { $0.role == "document" })?.body
    let steps = try parseSteps(field(fields, TbsField.stepsJson))
    if shape == .docReview {
        try validateDocReviewDocument(document, steps: steps)
    }
    return TbsModel(
        shape: shape,
        prompt: prompt,
        exhibits: exhibits,
        steps: steps,
        section: try sectionFromTags(tags),
        document: document
    )
}

public func sectionFromTags(_ tags: [String]) throws -> String {
    let prefix = "sec::"
    guard let tag = tags.first(where: { $0.hasPrefix(prefix) }) else {
        return TBS_DEFAULT_SECTION
    }
    let code = String(tag.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard TBS_SECTIONS.contains(code) else {
        throw TbsParseError.unknownSectionTag(tag)
    }
    return code
}

/// The exhibits shown in the exhibits pane: everything except the doc-review
/// primary document (which is rendered inline in the doc-review surface).
public func paneExhibits(_ model: TbsModel) -> [Exhibit] {
    model.exhibits.filter { $0.role != "document" }
}

/// Parse exhibits_json into typed exhibits ({id, title, kind, role, body,
/// columns, rows}). Mirrors the desktop `parseExhibits`.
public func parseExhibits(_ raw: String?) throws -> [Exhibit] {
    let array = try jsonArray("exhibits_json", raw)
    return try array.enumerated().map { index, element in
        let fieldName = "exhibits_json[\(index)]"
        let object = try jsonObject(element, fieldName: fieldName)
        let kind = try exhibitKind(object["kind"], fieldName: "\(fieldName).kind")
        return Exhibit(
            id: index,
            title: (object["title"] as? String) ?? "Exhibit \(index + 1)",
            body: (object["body"] as? String) ?? "",
            exhibitId: object["id"] as? String,
            kind: kind,
            role: object["role"] as? String,
            columns: try optionalStringArray(object["columns"], fieldName: "\(fieldName).columns"),
            rows: try optionalRowsArray(object["rows"], fieldName: "\(fieldName).rows")
        )
    }
}

private func exhibitKind(_ raw: Any?, fieldName: String) throws -> String {
    guard let raw else {
        return "text"
    }
    guard let kind = raw as? String, exhibitKinds.contains(kind) else {
        throw TbsParseError.invalidValue(
            field: fieldName,
            message: "unknown exhibit kind: \(String(describing: raw))"
        )
    }
    return kind
}

/// Parse steps_json into render steps, stripping the answer_key (retrieval
/// integrity: the render model NEVER carries the key or `correct_option`;
/// `options[]` are the label-stripped candidates only). Weights default to 1/N
/// (matching the Rust default_weight) so the rendered total reconciles with the
/// A10 grading. Mirrors the desktop `parseSteps`.
public func parseSteps(_ raw: String?) throws -> [RenderStep] {
    let array = try jsonArray("steps_json", raw)
    guard !array.isEmpty else { throw TbsParseError.emptySteps }
    let defaultWeight = 1.0 / Double(array.count)
    var seenIds = Set<String>()
    let steps = try array.enumerated().map { index, element in
        let fieldName = "steps_json[\(index)]"
        let object = try jsonObject(element, fieldName: fieldName)
        guard let id = object["id"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TbsParseError.invalidValue(field: "\(fieldName).id", message: "missing step id")
        }
        guard !seenIds.contains(id) else {
            throw TbsParseError.invalidValue(field: "steps_json", message: "duplicate step id: \(id)")
        }
        seenIds.insert(id)
        let kind = object["kind"] as? String
        let options = try parseOptions(object["options"], fieldName: "\(fieldName).options")
        if kind == "blank", options == nil {
            throw TbsParseError.invalidValue(field: "\(fieldName).options", message: "must be an array")
        }
        return RenderStep(
            id: id,
            label: (object["label"] as? String) ?? id,
            weight: try stepWeight(object["weight"], defaultWeight: defaultWeight, fieldName: fieldName),
            kind: kind,
            options: options ?? [],
            originalText: object["original_text"] as? String,
            corpusRefs: try optionalStringArray(object["corpus_refs"], fieldName: "\(fieldName).corpus_refs") ?? [],
            placeholder: (object["placeholder"] as? String) ?? (object["format"] as? String)
            // NOTE: answer_key / correct_option / accepted are deliberately
            // NOT read here (retrieval integrity C11).
        )
    }
    let totalWeight = steps.reduce(0) { $0 + $1.weight }
    if abs(totalWeight - 1.0) > 1e-6 {
        throw TbsParseError.invalidValue(field: "steps_json", message: "weights must sum to 1.0")
    }
    return steps
}

private func stepWeight(_ raw: Any?, defaultWeight: Double, fieldName: String) throws -> Double {
    guard let raw else { return defaultWeight }
    if raw is NSNull || raw is Bool {
        throw TbsParseError.invalidValue(
            field: "\(fieldName).weight",
            message: "must be a nonnegative finite number"
        )
    }
    let weight: Double?
    if let double = raw as? Double {
        weight = double
    } else if let number = raw as? NSNumber {
        weight = number.doubleValue
    } else {
        weight = nil
    }
    guard let weight, weight.isFinite, weight >= 0 else {
        throw TbsParseError.invalidValue(
            field: "\(fieldName).weight",
            message: "must be a nonnegative finite number"
        )
    }
    return weight
}

private func validateDocReviewDocument(_ document: String?, steps: [RenderStep]) throws {
    guard let document, !document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw TbsParseError.invalidValue(field: "doc_review.document", message: "missing document exhibit")
    }
    let blankIds = segmentDocument(document).compactMap { segment -> String? in
        if case let .blank(_, blankId, _) = segment {
            return blankId
        }
        return nil
    }
    guard !blankIds.isEmpty else {
        throw TbsParseError.invalidValue(field: "doc_review.document", message: "no blank markers")
    }
    let stepIds = Set(steps.map(\.id))
    if let missing = blankIds.first(where: { !stepIds.contains($0) }) {
        throw TbsParseError.invalidValue(field: "doc_review.document", message: "blank \(missing) has no step")
    }
}

/// Parse a step's `options` array into label-stripped render options. Mirrors
/// the desktop `parseOptions`.
private func parseOptions(_ raw: Any?, fieldName: String) throws -> [RenderOption]? {
    guard let raw, !(raw is NSNull) else { return nil }
    guard let array = raw as? [Any] else {
        throw TbsParseError.invalidValue(field: fieldName, message: "must be an array")
    }
    guard !array.isEmpty else {
        throw TbsParseError.invalidValue(field: fieldName, message: "must contain at least one option")
    }
    return try array.enumerated().map { index, element in
        let optionFieldName = "\(fieldName)[\(index)]"
        let object = try jsonObject(element, fieldName: optionFieldName)
        guard let id = object["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TbsParseError.invalidValue(field: "\(optionFieldName).id", message: "missing option id")
        }
        guard let text = object["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TbsParseError.invalidValue(field: "\(optionFieldName).text", message: "missing option text")
        }
        return RenderOption(
            id: id,
            text: text,
            kind: try optionKind(object["kind"], fieldName: "\(optionFieldName).kind")
        )
    }
}

private func optionKind(_ raw: Any?, fieldName: String) throws -> String {
    guard let raw else {
        return "replace"
    }
    guard let kind = raw as? String, optionKinds.contains(kind) else {
        throw TbsParseError.invalidValue(
            field: fieldName,
            message: "unknown option kind: \(String(describing: raw))"
        )
    }
    return kind
}

private func jsonObject(_ raw: Any, fieldName: String) throws -> [String: Any] {
    guard let object = raw as? [String: Any] else {
        throw TbsParseError.invalidValue(field: fieldName, message: "must be an object")
    }
    return object
}

/// Split a doc-review document body into text + blank segments. Each
/// `<blank step="id">original</blank>` marker becomes a blank segment
/// referencing a step id; everything else is literal text. Mirrors the desktop
/// `segmentDocument`.
public func segmentDocument(_ body: String?) -> [DocSegment] {
    guard let body, !body.isEmpty else { return [] }
    let pattern = #"<blank\s+step="([^"]+)">([\s\S]*?)</blank>"#
    let regex = regex(pattern)
    let ns = body as NSString
    var segments: [DocSegment] = []
    var last = 0
    var n = 0
    for match in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
        if match.range.location > last {
            let text = ns.substring(with: NSRange(location: last, length: match.range.location - last))
            segments.append(.text(key: "t\(n)", text: text))
            n += 1
        }
        let blankId = ns.substring(with: match.range(at: 1))
        let original = ns.substring(with: match.range(at: 2))
        segments.append(.blank(key: "b\(n)", blankId: blankId, original: original))
        n += 1
        last = match.range.location + match.range.length
    }
    if last < ns.length {
        segments.append(.text(key: "t\(n)", text: ns.substring(with: NSRange(location: last, length: ns.length - last))))
    }
    return segments
}

/// Shape the submission_json for a journal-entry TBS.
public func buildJeSubmission(_ lines: [JeLineInput]) throws -> String {
    let steps = try lines.map { line -> [String: Any] in
        [
            "id": line.id,
            "value": [
                "account": line.account,
                "side": line.side,
                "amount": try submissionNumber(line.amount, fieldName: "Amount for \(line.id)"),
            ] as [String: Any],
        ]
    }
    return jsonString(["steps": steps])
}

/// Shape the submission_json for a numeric TBS.
public func buildNumericSubmission(_ cells: [NumericCellInput]) throws -> String {
    let steps = try cells.map { cell -> [String: Any] in
        ["id": cell.id, "value": try submissionNumber(cell.value, fieldName: "Value for \(cell.id)")]
    }
    return jsonString(["steps": steps])
}

/// Shape submission_json for a which-treatment (discrimination) choice.
public func buildChoiceSubmission(_ choice: String) -> String {
    jsonString(["choice": choice])
}

/// Generic step submission `{"steps":[{"id":…,"value":…}]}` with STRING values.
/// Used by the doc-review surface (value = chosen option id) — mirrors the
/// desktop `buildDocReviewSubmission`. Research uses `buildResearchSubmission`.
public func buildStepsSubmission(_ pairs: [(id: String, value: String)]) -> String {
    let steps = pairs.map { ["id": $0.id, "value": $0.value] }
    return jsonString(["steps": steps])
}

/// Shape submission_json for a research TBS (one citation; the backend research
/// arm reads `citation`). Mirrors the desktop `buildResearchSubmission`.
public func buildResearchSubmission(_ citation: String) -> String {
    jsonString(["citation": citation.trimmingCharacters(in: .whitespacesAndNewlines)])
}

/// Confusion review is label-stripped: drop any trailing dev slug like
/// " (capitalize_vs_expense q0)" so the stem never leaks the category.
public func stripConfusionSlug(_ prompt: String) -> String {
    let pattern = #"\s*\([a-z0-9_]+\s+q\d+\)\s*$"#
    let regex = regex(pattern, options: [.caseInsensitive])
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

private func jsonArray(_ fieldName: String, _ raw: String?) throws -> [Any] {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw TbsParseError.missingJson(field: fieldName)
    }
    guard let data = raw.data(using: .utf8) else {
        throw TbsParseError.invalidJson(field: fieldName, message: "could not encode as UTF-8")
    }
    do {
        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let array = parsed as? [Any] else {
            throw TbsParseError.nonArrayJson(field: fieldName)
        }
        return array
    } catch let error as TbsParseError {
        throw error
    } catch {
        throw TbsParseError.invalidJson(field: fieldName, message: error.localizedDescription)
    }
}

/// Serialize a submission payload. Grading parses the JSON back, so key order is
/// irrelevant; sorted here only for deterministic output.
private func jsonString(_ object: [String: Any]) -> String {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            preconditionFailure("Could not encode submission JSON as UTF-8.")
        }
        return string
    } catch {
        preconditionFailure("Could not encode submission JSON: \(error.localizedDescription)")
    }
}

private let decimalNumberRegex = regex(#"^[+-]?(?:\d+\.?\d*|\.\d+)$"#)

private func submissionNumber(_ raw: String, fieldName: String) throws -> Any {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    guard decimalNumberRegex.firstMatch(in: trimmed, range: range) != nil else {
        throw TbsSubmissionError.invalidDecimal(field: fieldName)
    }
    guard let number = Double(trimmed) else {
        throw TbsSubmissionError.invalidDecimal(field: fieldName)
    }
    guard number.isFinite else {
        throw TbsSubmissionError.nonFiniteNumber(field: fieldName)
    }
    return number
}

/// Parse a JSON array of strings (coercing numbers/other scalars to strings),
/// mirroring lib.ts `asStringArray`. Returns nil only when the value is absent.
private func optionalStringArray(_ raw: Any?, fieldName: String) throws -> [String]? {
    guard let raw, !(raw is NSNull) else { return nil }
    return try requiredStringArray(raw, fieldName: fieldName)
}

private func requiredStringArray(_ raw: Any, fieldName: String) throws -> [String] {
    guard let array = raw as? [Any] else {
        throw TbsParseError.invalidValue(field: fieldName, message: "must be an array")
    }
    return array.map(stringify)
}

/// Parse a JSON array-of-arrays of strings (table rows), mirroring lib.ts.
private func optionalRowsArray(_ raw: Any?, fieldName: String) throws -> [[String]]? {
    guard let raw, !(raw is NSNull) else { return nil }
    guard let array = raw as? [Any] else {
        throw TbsParseError.invalidValue(field: fieldName, message: "must be an array")
    }
    return try array.enumerated().map { index, element in
        try requiredStringArray(element, fieldName: "\(fieldName)[\(index)]")
    }
}

/// Coerce a JSON scalar to a String, mirroring JS `String(x ?? "")`.
private func stringify(_ value: Any) -> String {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    case is NSNull:
        return ""
    default:
        return String(describing: value)
    }
}

private func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
        preconditionFailure("Invalid regular expression: \(error.localizedDescription)")
    }
}
