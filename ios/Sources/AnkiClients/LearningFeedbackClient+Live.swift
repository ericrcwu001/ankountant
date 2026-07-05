import AnkiKit
import AnkiSync
public import Dependencies
public import Foundation

private let learningFeedbackEndpoint = "https://api.openai.com/v1/responses"
private let maximumLearningFeedbackOutputTokens = 1_024

extension LearningFeedbackClient: DependencyKey {
    public static let liveValue = Self(
        generate: { request, model in
            let apiKey = try KeychainHelper.requireOpenAIAPIKey()
            let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                throw LearningFeedbackClientError.missingModel
            }

            guard let url = URL(string: learningFeedbackEndpoint) else {
                throw LearningFeedbackClientError.invalidEndpoint
            }

            let payload = try OpenAIResponsesRequest(
                model: model,
                inputText: learningFeedbackInputText(for: request)
            )
            let payloadData = try JSONEncoder().encode(payload)
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = payloadData

            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LearningFeedbackClientError.invalidHTTPResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw LearningFeedbackClientError.httpError(
                    statusCode: httpResponse.statusCode,
                    body: String(data: data, encoding: .utf8)
                )
            }

            let openAIResponse: OpenAIResponsesResponse
            do {
                openAIResponse = try JSONDecoder().decode(OpenAIResponsesResponse.self, from: data)
            } catch {
                throw LearningFeedbackClientError.invalidResponseJSON(error.localizedDescription)
            }

            guard let outputText = openAIResponse.firstOutputText()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !outputText.isEmpty else {
                throw LearningFeedbackClientError.noOutputText
            }

            let feedback: LearningFeedback
            do {
                feedback = try JSONDecoder().decode(LearningFeedback.self, from: Data(outputText.utf8))
            } catch {
                throw LearningFeedbackClientError.invalidFeedbackJSON(error.localizedDescription)
            }

            try validate(feedback: feedback, request: request)
            return feedback
        }
    )
}

private func learningFeedbackInputText(for request: LearningFeedbackRequest) throws -> String {
    let requestData = try JSONEncoder().encode(LearningFeedbackRequestPayload(request))
    guard let requestJSON = String(data: requestData, encoding: .utf8) else {
        throw LearningFeedbackClientError.invalidRequestJSON
    }
    return """
    Generate concise learning feedback for this review request.
    Return JSON matching the schema exactly.
    Ground every substantive claim in the correctAnswer or sources.
    Do not introduce facts, rules, numbers, or citations that are not present in the request.
    If the request lacks enough evidence, keep the feedback narrow and say only what the revealed answer and sources support.
    Use sourceIds only from the request sources.

    Request:
    \(requestJSON)
    """
}

private func validate(feedback: LearningFeedback, request: LearningFeedbackRequest) throws {
    try validateNonEmpty(feedback.title, field: "title")
    try validateNonEmpty(feedback.whyWrong, field: "whyWrong")
    try validateNonEmpty(feedback.correctApproach, field: "correctApproach")
    try validateNonEmpty(feedback.remember, field: "remember")

    guard !feedback.sourceIds.isEmpty else {
        throw LearningFeedbackClientError.invalidCitations("Feedback must include at least one source ID.")
    }

    let validSourceIds = Set(request.sources.map(\.id))
    let invalidSourceIds = feedback.sourceIds.filter { !validSourceIds.contains($0) }
    guard invalidSourceIds.isEmpty else {
        throw LearningFeedbackClientError.invalidCitations(
            "Feedback referenced unknown source IDs: \(invalidSourceIds.joined(separator: ", "))."
        )
    }
}

private func validateNonEmpty(_ value: String, field: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw LearningFeedbackClientError.emptyField(field)
    }
}

private struct LearningFeedbackRequestPayload: Encodable {
    let title: String
    let question: String
    let userAnswer: String
    let correctAnswer: String
    let sources: [LearningFeedbackSourcePayload]

    init(_ request: LearningFeedbackRequest) {
        title = request.title
        question = request.question
        userAnswer = request.userAnswer
        correctAnswer = request.correctAnswer
        sources = request.sources.map(LearningFeedbackSourcePayload.init)
    }
}

private struct LearningFeedbackSourcePayload: Encodable {
    let id: String
    let title: String
    let body: String

    init(_ source: LearningFeedbackSource) {
        id = source.id
        title = source.title
        body = source.body
    }
}

private struct OpenAIResponsesRequest: Encodable {
    let model: String
    let input: [OpenAIInputMessage]
    let store = false
    let maxOutputTokens = maximumLearningFeedbackOutputTokens
    let reasoning = OpenAIReasoning()
    let text = OpenAIText()

    init(model: String, inputText: String) {
        self.model = model
        input = [
            OpenAIInputMessage(
                role: "user",
                content: [
                    OpenAIInputContent(type: "input_text", text: inputText),
                ]
            ),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case store
        case maxOutputTokens = "max_output_tokens"
        case reasoning
        case text
    }
}

private struct OpenAIInputMessage: Encodable {
    let role: String
    let content: [OpenAIInputContent]
}

private struct OpenAIInputContent: Encodable {
    let type: String
    let text: String
}

private struct OpenAIReasoning: Encodable {
    let effort = "low"
}

private struct OpenAIText: Encodable {
    let format = OpenAITextFormat()
}

private struct OpenAITextFormat: Encodable {
    let type = "json_schema"
    let name = "learning_feedback"
    let strict = true
    let schema = LearningFeedbackSchema()
}

private struct LearningFeedbackSchema: Encodable {
    let type = "object"
    let additionalProperties = false
    let properties = Properties()
    let required = ["title", "whyWrong", "correctApproach", "remember", "sourceIds"]

    struct Properties: Encodable {
        let title = TextProperty()
        let whyWrong = TextProperty()
        let correctApproach = TextProperty()
        let remember = TextProperty()
        let sourceIds = SourceIdsProperty()
    }

    struct TextProperty: Encodable {
        let type = "string"
        let minLength = 1
    }

    struct SourceIdsProperty: Encodable {
        let type = "array"
        let items = TextProperty()
        let minItems = 1
    }
}

private struct OpenAIResponsesResponse: Decodable {
    let output: [OutputItem]

    func firstOutputText() -> String? {
        for item in output {
            for content in item.content ?? [] where content.type == "output_text" {
                return content.text
            }
        }
        return nil
    }

    struct OutputItem: Decodable {
        let content: [OutputContent]?
    }

    struct OutputContent: Decodable {
        let type: String
        let text: String?
    }
}

public enum LearningFeedbackClientError: Error, LocalizedError, Sendable {
    case missingModel
    case invalidEndpoint
    case invalidRequestJSON
    case invalidHTTPResponse
    case httpError(statusCode: Int, body: String?)
    case noOutputText
    case invalidResponseJSON(String)
    case invalidFeedbackJSON(String)
    case invalidCitations(String)
    case emptyField(String)

    public var errorDescription: String? {
        switch self {
        case .missingModel:
            "OpenAI feedback model is empty."
        case .invalidEndpoint:
            "OpenAI Responses endpoint is invalid."
        case .invalidRequestJSON:
            "Learning feedback request could not be encoded as JSON."
        case .invalidHTTPResponse:
            "OpenAI returned a non-HTTP response."
        case .httpError(let statusCode, let body):
            if let body, !body.isEmpty {
                "OpenAI request failed with HTTP \(statusCode): \(body)"
            } else {
                "OpenAI request failed with HTTP \(statusCode)."
            }
        case .noOutputText:
            "OpenAI response did not include output text."
        case .invalidResponseJSON(let message):
            "OpenAI response JSON was invalid: \(message)"
        case .invalidFeedbackJSON(let message):
            "Learning feedback JSON was invalid: \(message)"
        case .invalidCitations(let message):
            message
        case .emptyField(let field):
            "Learning feedback field \(field) is empty."
        }
    }
}
