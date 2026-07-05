public import AnkiKit
public import Dependencies
import DependenciesMacros

@DependencyClient
public struct LearningFeedbackClient: Sendable {
    public var generate: @Sendable (_ request: LearningFeedbackRequest, _ model: String) async throws -> LearningFeedback
}

extension LearningFeedbackClient: TestDependencyKey {
    public static let testValue = LearningFeedbackClient()
}

extension DependencyValues {
    public var learningFeedbackClient: LearningFeedbackClient {
        get { self[LearningFeedbackClient.self] }
        set { self[LearningFeedbackClient.self] = newValue }
    }
}
