import AnkiKit

enum LearningFeedbackPanelState: Equatable, Sendable {
    case loading
    case content(LearningFeedback, sources: [LearningFeedbackSource])
    case error(String)
}
