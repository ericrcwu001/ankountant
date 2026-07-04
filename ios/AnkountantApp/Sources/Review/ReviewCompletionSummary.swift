struct ReviewCompletionSummary: Equatable {
    let reviewed: Int
    let title: String
    let message: String
    let accuracyText: String?
    let systemImage: String

    var hasReviews: Bool {
        reviewed > 0
    }

    init(reviewed: Int, accuracy: Double) {
        precondition(reviewed >= 0, "Reviewed count cannot be negative")

        self.reviewed = reviewed

        if reviewed == 0 {
            title = "All caught up"
            message = "No cards are due in this deck right now."
            accuracyText = nil
            systemImage = "checkmark.circle"
        } else {
            title = "Review complete"
            message = reviewed == 1 ? "You've reviewed 1 card" : "You've reviewed \(reviewed) cards"
            accuracyText = "Accuracy: \(Int(accuracy * 100))%"
            systemImage = "checkmark.circle.fill"
        }
    }
}
