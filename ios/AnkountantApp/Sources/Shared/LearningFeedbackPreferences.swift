import AnkiKit
import Foundation

enum LearningFeedbackPreferenceKeys {
    static let enabled = ReviewPreferences.Keys.learningFeedbackEnabled
    static let model = ReviewPreferences.Keys.learningFeedbackModel
    static let defaultEnabled = true
}

func resolvedLearningFeedbackModel(_ model: String) -> String {
    let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? defaultLearningFeedbackModel : trimmed
}
