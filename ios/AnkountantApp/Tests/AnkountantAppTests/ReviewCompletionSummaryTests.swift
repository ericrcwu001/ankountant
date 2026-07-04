import Testing
@testable import AnkountantApp

@Suite("Review completion summary")
struct ReviewCompletionSummaryTests {
    @Test func emptyQueueUsesCaughtUpCopy() {
        let summary = ReviewCompletionSummary(reviewed: 0, accuracy: 0)

        #expect(summary.hasReviews == false)
        #expect(summary.title == "All caught up")
        #expect(summary.message == "No cards are due in this deck right now.")
        #expect(summary.accuracyText == nil)
        #expect(summary.systemImage == "checkmark.circle")
    }

    @Test func singleReviewUsesSingularCardLabel() {
        let summary = ReviewCompletionSummary(reviewed: 1, accuracy: 1)

        #expect(summary.hasReviews)
        #expect(summary.title == "Review complete")
        #expect(summary.message == "You've reviewed 1 card")
        #expect(summary.accuracyText == "Accuracy: 100%")
        #expect(summary.systemImage == "checkmark.circle.fill")
    }

    @Test func multipleReviewsIncludeAccuracy() {
        let summary = ReviewCompletionSummary(reviewed: 7, accuracy: 0.824)

        #expect(summary.hasReviews)
        #expect(summary.message == "You've reviewed 7 cards")
        #expect(summary.accuracyText == "Accuracy: 82%")
    }
}
