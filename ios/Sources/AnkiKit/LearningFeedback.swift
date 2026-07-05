import Foundation

public let defaultLearningFeedbackModel = "gpt-5.4-mini"

public struct LearningFeedback: Sendable, Equatable, Identifiable, Decodable {
    public let title: String
    public let whyWrong: String
    public let correctApproach: String
    public let remember: String
    public let sourceIds: [String]

    public var id: String {
        stableLearningFeedbackId([title, whyWrong, correctApproach, remember] + sourceIds)
    }

    public var content: String {
        [title, whyWrong, correctApproach, remember]
            .map(learningFeedbackNormalizedText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public init(title: String, whyWrong: String, correctApproach: String, remember: String, sourceIds: [String]) {
        self.title = title
        self.whyWrong = whyWrong
        self.correctApproach = correctApproach
        self.remember = remember
        self.sourceIds = sourceIds
    }
}

public struct LearningFeedbackSource: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let body: String

    public init(id: String, title: String, body: String) {
        precondition(!id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Learning feedback source requires an id.")
        precondition(!body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Learning feedback source requires a body.")
        self.id = id
        self.title = title
        self.body = body
    }
}

public struct LearningFeedbackRequest: Sendable, Equatable, Codable {
    public let title: String
    public let question: String
    public let userAnswer: String
    public let correctAnswer: String
    public let sources: [LearningFeedbackSource]

    public init(
        title: String,
        question: String,
        userAnswer: String,
        correctAnswer: String,
        sources: [LearningFeedbackSource]
    ) {
        precondition(!sources.isEmpty, "Learning feedback request requires at least one source.")
        self.title = title
        self.question = question
        self.userAnswer = userAnswer
        self.correctAnswer = correctAnswer
        self.sources = sources
    }
}

public func buildReviewLearningFeedbackRequest(
    title: String,
    renderedCard: RenderedCard,
    note: NoteRecord,
    userAnswer: String
) -> LearningFeedbackRequest {
    buildReviewLearningFeedbackRequest(
        title: title,
        frontHTML: renderedCard.frontHTML,
        backHTML: renderedCard.backHTML,
        noteFields: note.flds.components(separatedBy: "\u{1f}"),
        userAnswer: userAnswer
    )
}

public func buildReviewLearningFeedbackRequest(
    title: String,
    frontHTML: String,
    backHTML: String,
    noteFields: [String],
    userAnswer: String
) -> LearningFeedbackRequest {
    let question = learningFeedbackReadableText(fromHTML: frontHTML)
    let correctAnswer = learningFeedbackReadableText(fromHTML: backHTML)
    var sources = [
        learningFeedbackSource(id: "review-front", title: "Card Front", html: frontHTML),
        learningFeedbackSource(id: "review-back", title: "Card Back", html: backHTML),
    ].compactMap(\.self)

    sources += noteFields.enumerated().compactMap { index, field in
        learningFeedbackSource(id: "note-field-\(index + 1)", title: "Note Field \(index + 1)", html: field)
    }

    return LearningFeedbackRequest(
        title: title,
        question: question,
        userAnswer: learningFeedbackNormalizedText(userAnswer),
        correctAnswer: correctAnswer,
        sources: sources
    )
}

public func buildTbsLearningFeedbackRequest(
    title: String,
    model: TbsModel,
    reveal: TbsRevealModel,
    stepResults: [PerformanceStepResult],
    userAnswerText: String
) -> LearningFeedbackRequest? {
    let incorrectResults = stepResults.filter { !$0.correct }
    guard !incorrectResults.isEmpty else { return nil }

    let modelStepsById = uniqueRenderStepsById(model.steps)
    let revealStepsById = uniqueStepRevealsById(reveal.steps)
    let correctAnswer = incorrectResults.map { result in
        guard let modelStep = modelStepsById[result.id] else {
            preconditionFailure("TBS feedback missing render step for result id \(result.id).")
        }
        guard let revealStep = revealStepsById[result.id] else {
            preconditionFailure("TBS feedback missing reveal step for result id \(result.id).")
        }
        let correctText = learningFeedbackNormalizedText(revealStep.correctText)
        precondition(!correctText.isEmpty, "TBS feedback requires correct text for result id \(result.id).")
        return "\(modelStep.label): \(correctText)"
    }.joined(separator: "\n")

    let sources = tbsLearningFeedbackSources(model: model, reveal: reveal)
    guard !sources.isEmpty else { return nil }

    return LearningFeedbackRequest(
        title: title,
        question: learningFeedbackReadableText(fromHTML: model.prompt),
        userAnswer: learningFeedbackNormalizedText(userAnswerText),
        correctAnswer: correctAnswer,
        sources: sources
    )
}

public func learningFeedbackReadableText(fromHTML html: String) -> String {
    learningFeedbackNormalizedText(decodeLearningFeedbackHTMLEntities(stripLearningFeedbackHTMLTags(html)))
}

private func tbsLearningFeedbackSources(model: TbsModel, reveal: TbsRevealModel) -> [LearningFeedbackSource] {
    var sources = [LearningFeedbackSource]()

    if let prompt = learningFeedbackSource(id: "tbs-prompt", title: "Prompt", html: model.prompt) {
        sources.append(prompt)
    }

    sources += model.exhibits.compactMap { exhibit in
        learningFeedbackSource(id: "tbs-exhibit-\(exhibit.id)", title: exhibit.title, plainText: exhibitLearningFeedbackText(exhibit))
    }

    if let source = learningFeedbackSource(id: "tbs-source", title: "Authoritative Source", html: reveal.source) {
        sources.append(source)
    }

    if let schema = learningFeedbackSource(id: "tbs-schema", title: "Schema", plainText: reveal.schemaTag) {
        sources.append(schema)
    }

    if let section = learningFeedbackSource(id: "tbs-section", title: "Section", plainText: reveal.section) {
        sources.append(section)
    }

    return sources
}

private func exhibitLearningFeedbackText(_ exhibit: Exhibit) -> String {
    var parts = [learningFeedbackReadableText(fromHTML: exhibit.body)]
    if let columns = exhibit.columns, !columns.isEmpty {
        parts.append(columns.joined(separator: " | "))
    }
    if let rows = exhibit.rows {
        parts += rows.map { $0.joined(separator: " | ") }
    }
    return learningFeedbackNormalizedText(parts.joined(separator: "\n"))
}

private func learningFeedbackSource(id: String, title: String, html: String) -> LearningFeedbackSource? {
    learningFeedbackSource(id: id, title: title, plainText: learningFeedbackReadableText(fromHTML: html))
}

private func learningFeedbackSource(id: String, title: String, plainText: String) -> LearningFeedbackSource? {
    let body = learningFeedbackNormalizedText(plainText)
    guard !body.isEmpty else { return nil }
    return LearningFeedbackSource(id: id, title: title, body: body)
}

private func uniqueRenderStepsById(_ steps: [RenderStep]) -> [String: RenderStep] {
    var byId = [String: RenderStep]()
    for step in steps {
        precondition(byId[step.id] == nil, "TBS feedback received duplicate render step id \(step.id).")
        byId[step.id] = step
    }
    return byId
}

private func uniqueStepRevealsById(_ steps: [StepReveal]) -> [String: StepReveal] {
    var byId = [String: StepReveal]()
    for step in steps {
        precondition(byId[step.id] == nil, "TBS feedback received duplicate reveal step id \(step.id).")
        byId[step.id] = step
    }
    return byId
}

private func stripLearningFeedbackHTMLTags(_ html: String) -> String {
    var output = ""
    var index = html.startIndex
    while index < html.endIndex {
        if html[index] == "<", let tagEnd = html[index...].firstIndex(of: ">") {
            let tagStart = html.index(after: index)
            let tag = html[tagStart..<tagEnd]
            output.append(learningFeedbackTagAddsLineBreak(tag) ? "\n" : " ")
            index = html.index(after: tagEnd)
        } else {
            output.append(html[index])
            index = html.index(after: index)
        }
    }
    return output
}

private func learningFeedbackTagAddsLineBreak(_ tag: Substring) -> Bool {
    let tagName = tag
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .drop { $0 == "/" }
        .split(whereSeparator: { $0.isWhitespace || $0 == "/" })
        .first?
        .lowercased()

    guard let tagName else { return false }
    return [
        "br", "p", "div", "li", "tr", "table", "section", "article",
        "h1", "h2", "h3", "h4", "h5", "h6",
    ].contains(tagName)
}

private func decodeLearningFeedbackHTMLEntities(_ text: String) -> String {
    var output = ""
    var index = text.startIndex
    while index < text.endIndex {
        if text[index] == "&", let semicolon = text[index...].firstIndex(of: ";") {
            let entityStart = text.index(after: index)
            let entity = String(text[entityStart..<semicolon])
            if let decoded = learningFeedbackHTMLEntity(entity) {
                output.append(decoded)
                index = text.index(after: semicolon)
                continue
            }
        }
        output.append(text[index])
        index = text.index(after: index)
    }
    return output
}

private func learningFeedbackHTMLEntity(_ entity: String) -> String? {
    if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
        return learningFeedbackUnicodeScalar(String(entity.dropFirst(2)), radix: 16)
    }
    if entity.hasPrefix("#") {
        return learningFeedbackUnicodeScalar(String(entity.dropFirst()), radix: 10)
    }
    return [
        "amp": "&",
        "apos": "'",
        "gt": ">",
        "lt": "<",
        "nbsp": " ",
        "quot": "\"",
    ][entity]
}

private func learningFeedbackUnicodeScalar(_ raw: String, radix: Int) -> String? {
    guard let value = UInt32(raw, radix: radix), let scalar = UnicodeScalar(value) else {
        return nil
    }
    return String(Character(scalar))
}

private func learningFeedbackNormalizedText(_ text: String) -> String {
    text
        .components(separatedBy: .newlines)
        .map(learningFeedbackCollapseInlineWhitespace)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}

private func learningFeedbackCollapseInlineWhitespace(_ text: String) -> String {
    var output = ""
    var previousWasWhitespace = false
    for scalar in text.unicodeScalars {
        if CharacterSet.whitespaces.contains(scalar) {
            if !previousWasWhitespace {
                output.append(" ")
                previousWasWhitespace = true
            }
        } else {
            output.unicodeScalars.append(scalar)
            previousWasWhitespace = false
        }
    }
    return output
}

private func stableLearningFeedbackId(_ components: [String]) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in components.joined(separator: "\u{1f}").utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return "learning-feedback-\(String(hash, radix: 16))"
}
