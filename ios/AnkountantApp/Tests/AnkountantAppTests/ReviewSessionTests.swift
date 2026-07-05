import XCTest
import SwiftUI
import UIKit
import Dependencies
import AnkiKit
import AnkiServices
@testable import AnkountantApp

private enum ReviewSessionFixtureError: LocalizedError {
    case failed

    var errorDescription: String? {
        "fixture failure"
    }
}

// MARK: - ReviewSessionTests
// Lifted from ~/Clones/ankountant/AnkiApp/Sources/Review/ReviewSessionTests.swift (82 LOC)
// Adapted to our architecture: @MainActor class, async revealAnswer(), swift-dependencies mocking.

@MainActor
final class ReviewSessionTests: XCTestCase {
    var session: ReviewSession!

    override func setUp() async throws {
        try await super.setUp()
        session = ReviewSession(deckId: 1)
    }

    override func tearDown() async throws {
        session = nil
        try await super.tearDown()
    }

    // MARK: - Deferred from fork

    // DEFERRED: fork's testCurrentCardInitiallyNil / testCurrentCardPublicAccess /
    // testCurrentCardStructure test `session.currentCard` — a public property in the
    // fork's ReviewSession. Our ReviewSession exposes `currentCardOrdinal: UInt32`
    // but keeps `currentQueuedCard` private. Exposing it would require a public accessor
    // that PR 1a did not add. Use `currentCardOrdinal == 0` as a proxy.
    // PR 1a defer: add `public private(set) var currentCard: QueuedReviewCard?` when needed.

    // MARK: - Property Exposure Tests

    /// currentCardOrdinal should be 0 before the session starts (maps to fork's currentCard == nil).
    func testCurrentCardOrdinalInitiallyZero() {
        XCTAssertEqual(session.currentCardOrdinal, 0,
                       "currentCardOrdinal should be 0 before session starts")
    }

    // MARK: - Initial State Tests

    /// Session stats should all be zero-initialised (mirrors fork's testSessionStatsInitialized).
    func testSessionStatsInitialized() {
        XCTAssertEqual(session.sessionStats.reviewed, 0, "Initial reviewed count should be 0")
        XCTAssertEqual(session.sessionStats.correct, 0, "Initial correct count should be 0")
        XCTAssertEqual(session.sessionStats.totalTimeMs, 0, "Initial time should be 0")
    }

    /// Remaining counts should be zero before start() (mirrors fork's testRemainingCountsInitialized).
    func testRemainingCountsInitialized() {
        XCTAssertEqual(session.remainingCounts.newCount, 0)
        XCTAssertEqual(session.remainingCounts.learnCount, 0)
        XCTAssertEqual(session.remainingCounts.reviewCount, 0)
    }

    /// nextIntervals should be empty before any card is loaded (mirrors fork's testNextIntervalsStructure).
    func testNextIntervalsStructure() {
        XCTAssertTrue(session.nextIntervals.isEmpty,
                      "nextIntervals should be empty initially")
    }

    /// isFinished should be false before start() (mirrors fork's testIsFinishedInitiallyFalse).
    func testIsFinishedInitiallyFalse() {
        XCTAssertFalse(session.isFinished, "Session should not be finished initially")
    }

    /// showAnswer should be false before any card is loaded (mirrors fork's testShowAnswerInitiallyFalse).
    func testShowAnswerInitiallyFalse() {
        XCTAssertFalse(session.showAnswer, "Answer should not be visible initially")
    }

    // MARK: - Additional initial-state checks (not in fork; added to fill gaps)

    func testCanUndoInitiallyFalse() {
        XCTAssertFalse(session.canUndo,
                       "canUndo should be false before any card is answered")
    }

    func testFrontHTMLInitiallyEmpty() {
        XCTAssertTrue(session.frontHTML.isEmpty,
                      "frontHTML should be empty before session starts")
    }

    func testBackHTMLInitiallyEmpty() {
        XCTAssertTrue(session.backHTML.isEmpty,
                      "backHTML should be empty before session starts")
    }

    func testCardCSSInitiallyEmpty() {
        XCTAssertTrue(session.cardCSS.isEmpty,
                      "cardCSS should be empty before session starts")
    }

    func testRequiresTypedAnswerInputInitiallyFalse() {
        XCTAssertFalse(session.requiresTypedAnswerInput,
                       "requiresTypedAnswerInput should be false initially")
    }

    // MARK: - start() with empty queue

    /// When the scheduler returns an empty queue, start() should mark the session finished.
    /// Mirrors fork's testRefreshAndAdvanceMethodExists (which was a no-op placeholder).
    func testStartWithEmptyQueueFinishesSession() throws {
        withDependencies {
            $0.decksService.setCurrentDeck = { _ in }
            $0.schedulerService.getQueuedCards = { _ in
                QueuedCardsResult(cards: [], newCount: 0, learningCount: 0, reviewCount: 0)
            }
        } operation: {
            let s = ReviewSession(deckId: 42)
            s.start()
            XCTAssertTrue(s.isFinished,
                          "Session with empty queue should be finished after start()")
            XCTAssertEqual(s.remainingCounts, .zero)
        }
    }

    func testStartFailureSurfacesError() {
        withDependencies {
            $0.decksService.setCurrentDeck = { _ in throw ReviewSessionFixtureError.failed }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            XCTAssertTrue(session.isFinished)
            XCTAssertTrue(session.errorMessage?.contains("fixture failure") == true)
        }
    }

    func testStartCanRecoverAfterFailure() {
        final class StartState: @unchecked Sendable { var calls = 0 }
        let state = StartState()
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )
        let stubNote = NoteRecord(id: 100, guid: "g", mid: 200, mod: 0, flds: "", sfld: "", csum: 0)

        withDependencies {
            $0.decksService.setCurrentDeck = { _ in
                state.calls += 1
                if state.calls == 1 {
                    throw ReviewSessionFixtureError.failed
                }
            }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.notesService.getNote = { _ in stubNote }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "front", backHTML: "back", cardCSS: "")
            }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            XCTAssertTrue(session.isFinished)
            XCTAssertTrue(session.errorMessage?.contains("fixture failure") == true)

            session.start()

            XCTAssertFalse(session.isFinished)
            XCTAssertNil(session.errorMessage)
            XCTAssertEqual(session.currentCardId, 1)
            XCTAssertEqual(session.remainingCounts.newCount, 1)
        }
    }

    func testAnswerFailureKeepsCurrentCardAndReportsError() async {
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )
        let stubNote = NoteRecord(id: 100, guid: "g", mid: 200, mod: 0, flds: "", sfld: "", csum: 0)

        await withDependencies {
            $0.decksService.setCurrentDeck = { _ in }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.schedulerService.answerReviewCard = { _, _, _, _ in throw ReviewSessionFixtureError.failed }
            $0.notesService.getNote = { _ in stubNote }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "front", backHTML: "back", cardCSS: "")
            }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            XCTAssertEqual(session.currentCardId, 1)

            await session.revealAnswer()
            session.answer(rating: .good)

            XCTAssertEqual(session.currentCardId, 1)
            XCTAssertEqual(session.sessionStats.reviewed, 0)
            XCTAssertFalse(session.isFinished)
            XCTAssertTrue(session.errorMessage?.contains("fixture failure") == true)
        }
    }

    func testAnswerBeforeRevealIsIgnored() {
        final class Counter: @unchecked Sendable { var value = 0 }
        let answerCounter = Counter()
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )
        let stubNote = NoteRecord(id: 100, guid: "g", mid: 200, mod: 0, flds: "", sfld: "", csum: 0)

        withDependencies {
            $0.decksService.setCurrentDeck = { _ in }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.schedulerService.answerReviewCard = { _, _, _, _ in
                answerCounter.value += 1
            }
            $0.notesService.getNote = { _ in stubNote }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "front", backHTML: "back", cardCSS: "")
            }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()

            session.answer(rating: .good)

            XCTAssertEqual(answerCounter.value, 0)
            XCTAssertEqual(session.currentCardId, 1)
            XCTAssertEqual(session.sessionStats.reviewed, 0)
            XCTAssertFalse(session.canUndo)
            XCTAssertFalse(session.showAnswer)
        }
    }

    func testCardActionSuccessAdvancesWithoutCountingReview() {
        final class QueueState: @unchecked Sendable { var calls = 0 }
        let state = QueueState()
        let firstCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let secondCard = QueuedReviewCard.preview(cardId: 2, noteId: 200, ord: 0)

        withDependencies {
            $0.decksService.setCurrentDeck = { _ in }
            $0.schedulerService.getQueuedCards = { _ in
                state.calls += 1
                if state.calls == 1 {
                    return QueuedCardsResult(cards: [firstCard], newCount: 1, learningCount: 0, reviewCount: 0)
                }
                return QueuedCardsResult(cards: [secondCard], newCount: 0, learningCount: 0, reviewCount: 1)
            }
            $0.notesService.getNote = { noteId in
                NoteRecord(id: noteId, guid: "g", mid: 200, mod: 0, flds: "", sfld: "", csum: 0)
            }
            $0.cardRenderingService.renderCard = { cardId in
                RenderedCard(frontHTML: "front-\(cardId)", backHTML: "back-\(cardId)", cardCSS: "")
            }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            XCTAssertEqual(session.currentCardId, 1)

            session.handleCardActionSuccess(shouldAdvance: true)

            XCTAssertEqual(session.currentCardId, 2)
            XCTAssertEqual(session.sessionStats.reviewed, 0)
            XCTAssertFalse(session.showAnswer)
            XCTAssertEqual(session.remainingCounts.reviewCount, 1)
        }
    }

    func testCardActionSuccessRefreshesFlagWithoutHidingAnswer() async {
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )
        let stubNote = NoteRecord(id: 100, guid: "g", mid: 200, mod: 0, flds: "", sfld: "", csum: 0)

        await withDependencies {
            $0.decksService.setCurrentDeck = { _ in }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.notesService.getNote = { _ in stubNote }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "front", backHTML: "back", cardCSS: "")
            }
            $0.cardClient.getCardFlags = { _ in 4 }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            await session.revealAnswer()
            XCTAssertTrue(session.showAnswer)

            session.handleCardActionSuccess(shouldAdvance: false)

            XCTAssertEqual(session.currentCardId, 1)
            XCTAssertEqual(session.currentFlag, 4)
            XCTAssertTrue(session.showAnswer)
        }
    }

    func testTypedAnswerMissingNotetypeFieldReportsError() {
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )
        let stubNote = NoteRecord(
            id: 100,
            guid: "g",
            mid: 200,
            mod: 0,
            flds: "Front value\u{1f}Back value",
            sfld: "",
            csum: 0
        )

        withDependencies {
            $0.decksService.setCurrentDeck = { _ in }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.notesService.getNote = { _ in stubNote }
            $0.notetypesService.getNotetypeFields = { _ in [
                NotetypeFieldInfo(name: "Front", ordinal: 0, fontName: "-apple-system", fontSize: 18),
                NotetypeFieldInfo(name: "Back", ordinal: 1, fontName: "-apple-system", fontSize: 18),
            ] }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "<p>Prompt [[type:Missing]]</p>", backHTML: "<p>Back [[type:Missing]]</p>", cardCSS: "")
            }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()

            XCTAssertFalse(session.requiresTypedAnswerInput)
            XCTAssertFalse(session.frontHTML.contains("[[type:Missing]]"))
            XCTAssertFalse(session.frontHTML.contains("typeans"))
            XCTAssertTrue(session.errorMessage?.contains("field \"Missing\"") == true)
        }
    }

    func testTypedAnswerMissingNoteFieldReportsError() {
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )
        let stubNote = NoteRecord(
            id: 100,
            guid: "g",
            mid: 200,
            mod: 0,
            flds: "Front value",
            sfld: "",
            csum: 0
        )

        withDependencies {
            $0.decksService.setCurrentDeck = { _ in }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.notesService.getNote = { _ in stubNote }
            $0.notetypesService.getNotetypeFields = { _ in [
                NotetypeFieldInfo(name: "Front", ordinal: 0, fontName: "-apple-system", fontSize: 18),
                NotetypeFieldInfo(name: "Back", ordinal: 1, fontName: "-apple-system", fontSize: 18),
            ] }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "<p>Prompt [[type:Back]]</p>", backHTML: "<p>Back [[type:Back]]</p>", cardCSS: "")
            }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()

            XCTAssertFalse(session.requiresTypedAnswerInput)
            XCTAssertFalse(session.frontHTML.contains("[[type:Back]]"))
            XCTAssertFalse(session.frontHTML.contains("typeans"))
            XCTAssertTrue(session.errorMessage?.contains("field \"Back\"") == true)
            XCTAssertTrue(session.errorMessage?.contains("note 100") == true)
        }
    }

    // MARK: - revealAnswer() sets showAnswer

    /// revealAnswer() when there is no typed-answer placeholder should set showAnswer = true.
    /// Tests the async path without needing a running card queue.
    func testRevealAnswerSetsShowAnswer() async {
        // No typedAnswerState is set (no cards loaded), so revealAnswer() takes
        // the non-typed branch and immediately sets showAnswer = true.
        XCTAssertFalse(session.showAnswer)
        await session.revealAnswer()
        XCTAssertTrue(session.showAnswer,
                      "showAnswer should be true after revealAnswer() with no typed-answer state")
    }

    @MainActor
    func testRevealAnswerIgnoresOverlappingTypedAnswerReveal() async {
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )
        let stubNote = NoteRecord(
            id: 100,
            guid: "g",
            mid: 200,
            mod: 0,
            flds: "Front value\u{1f}Back value",
            sfld: "",
            csum: 0
        )

        await withDependencies {
            $0.decksService.setCurrentDeck = { _ in }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.notesService.getNote = { _ in stubNote }
            $0.notetypesService.getNotetypeFields = { _ in [
                NotetypeFieldInfo(name: "Front", ordinal: 0, fontName: "-apple-system", fontSize: 18),
                NotetypeFieldInfo(name: "Back", ordinal: 1, fontName: "-apple-system", fontSize: 18),
            ] }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "<p>Prompt [[type:Back]]</p>", backHTML: "<p>Back [[type:Back]]</p>", cardCSS: "")
            }
            $0.cardRenderingService.compareAnswer = { _, typed, _ in
                "<span>\(typed)</span>"
            }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            XCTAssertTrue(session.requiresTypedAnswerInput)

            let firstReveal = Task { @MainActor in
                await session.revealAnswer()
            }
            while session.typedAnswerRequestID == 0 {
                await Task.yield()
            }

            let secondReveal = Task { @MainActor in
                await session.revealAnswer()
            }
            await Task.yield()

            XCTAssertEqual(session.typedAnswerRequestID, 1)
            XCTAssertTrue(session.isRevealingAnswer)

            session.submitTypedAnswer("typed")
            await firstReveal.value
            await secondReveal.value

            XCTAssertTrue(session.showAnswer)
            XCTAssertFalse(session.isRevealingAnswer)
            XCTAssertEqual(session.typedAnswerRequestID, 1)
        }
    }

    // MARK: - Audio / Chrome state (Task 2)

    @MainActor
    func testUpdateAudioPlayingFlipsObservableFlag() {
        let session = ReviewSession(deckId: 1)
        XCTAssertFalse(session.isAudioPlaying)
        session.updateAudioPlaying(true)
        XCTAssertTrue(session.isAudioPlaying)
        session.updateAudioPlaying(false)
        XCTAssertFalse(session.isAudioPlaying)
    }

    @MainActor
    func testUpdateCardChromeStoresColorAndDarkness() {
        let session = ReviewSession(deckId: 1)
        XCTAssertEqual(session.cardChromeColor, .clear)
        XCTAssertFalse(session.cardChromeIsDark)
        session.updateCardChrome(color: UIColor.red, isDark: false)
        XCTAssertEqual(session.cardChromeColor, Color(uiColor: UIColor.red))
        XCTAssertFalse(session.cardChromeIsDark)
        session.updateCardChrome(color: UIColor.black, isDark: true)
        XCTAssertEqual(session.cardChromeColor, Color(uiColor: UIColor.black))
        XCTAssertTrue(session.cardChromeIsDark)
    }

    // MARK: - Replay / Stop-audio bump mutators (Task 3)

    @MainActor
    func testBumpReplayRequestIncrementsCounter() {
        let session = ReviewSession(deckId: 1)
        XCTAssertEqual(session.replayRequestID, 0)
        session.bumpReplayRequest()
        XCTAssertEqual(session.replayRequestID, 1)
        session.bumpReplayRequest()
        XCTAssertEqual(session.replayRequestID, 2)
    }

    @MainActor
    func testBumpStopAudioRequestIncrementsCounter() {
        let session = ReviewSession(deckId: 1)
        XCTAssertEqual(session.stopAudioRequestID, 0)
        session.bumpStopAudioRequest()
        XCTAssertEqual(session.stopAudioRequestID, 1)
    }

    // MARK: - currentNote cache + TemplateTarget (Task 4)

    @MainActor
    func testCurrentNoteCachedOnAdvance() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let callCounter = Counter()
        let stubNote = NoteRecord(
            id: 100, guid: "g", mid: 200, mod: 0,
            flds: "", sfld: "", csum: 0
        )
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )

        try await withDependencies {
            $0.notesService.getNote = { noteId in
                callCounter.value += 1
                XCTAssertEqual(noteId, 100)
                return stubNote
            }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "<p>front</p>", backHTML: "<p>back</p>", cardCSS: "")
            }
            $0.decksService.setCurrentDeck = { _ in }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(session.currentNote, stubNote)
            XCTAssertEqual(callCounter.value, 1, "getNote should be called exactly once per advance")

            // Re-observe currentNote — must not trigger additional fetches
            _ = session.currentNote
            _ = session.currentNote
            XCTAssertEqual(callCounter.value, 1, "currentNote is cached, not refetched on observation")
        }
    }

    @MainActor
    func testCurrentTemplateTargetDerivedFromCachedNoteAndCard() async throws {
        let stubNote = NoteRecord(
            id: 100, guid: "g", mid: 200, mod: 0,
            flds: "", sfld: "", csum: 0
        )
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 3)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )

        try await withDependencies {
            $0.notesService.getNote = { _ in stubNote }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "f", backHTML: "b", cardCSS: "")
            }
            $0.decksService.setCurrentDeck = { _ in }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            try await Task.sleep(for: .milliseconds(50))
            let target = session.currentTemplateTarget
            XCTAssertNotNil(target)
            XCTAssertEqual(target?.notetypeId, 200)
            XCTAssertEqual(target?.ordinal, 3)
        }
    }

    // MARK: - Full audio/chrome round-trip (Task 11)

    @MainActor
    func testFullAudioAndChromeRoundTrip() async throws {
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )
        let stubNote = NoteRecord(id: 100, guid: "g", mid: 200, mod: 0, flds: "", sfld: "", csum: 0)

        try await withDependencies {
            $0.notesService.getNote = { _ in stubNote }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.cardRenderingService.renderCard = { _ in
                RenderedCard(frontHTML: "f", backHTML: "b", cardCSS: "")
            }
            $0.decksService.setCurrentDeck = { _ in }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            try await Task.sleep(for: .milliseconds(50))

            // Audio start
            session.updateAudioPlaying(true)
            XCTAssertTrue(session.isAudioPlaying)

            // Capture baseline: advance() already bumped stopAudioRequestID once on card load
            let stopBaselineID = session.stopAudioRequestID

            // User taps replay-while-playing → stop bump (toolbar logic, here exercised manually)
            session.bumpStopAudioRequest()
            XCTAssertEqual(session.stopAudioRequestID, stopBaselineID + 1)

            // JS replies to ankountantStopAllAudio → onAudioStateChange(false)
            session.updateAudioPlaying(false)
            XCTAssertFalse(session.isAudioPlaying)

            // User taps replay again → replay bump
            session.bumpReplayRequest()
            XCTAssertEqual(session.replayRequestID, 1)

            // JS reports a card-bg color
            session.updateCardChrome(color: UIColor.systemBlue, isDark: false)
            XCTAssertEqual(session.cardChromeColor, Color(uiColor: UIColor.systemBlue))
        }
    }

    // MARK: - refreshAfterEdit() (Task 5)

    @MainActor
    func testRefreshAfterEditRerendersCurrentCardWithoutAdvancing() async throws {
        final class State: @unchecked Sendable {
            var renderCallCount = 0
            var noteFields = "old front\u{1f}old back"
        }
        let state = State()
        let stubCard = QueuedReviewCard.preview(cardId: 1, noteId: 100, ord: 0)
        let stubResult = QueuedCardsResult(
            cards: [stubCard], newCount: 1, learningCount: 0, reviewCount: 0
        )

        try await withDependencies {
            $0.notesService.getNote = { _ in
                NoteRecord(id: 100, guid: "g", mid: 200, mod: 0, flds: state.noteFields, sfld: "", csum: 0)
            }
            $0.schedulerService.getQueuedCards = { _ in stubResult }
            $0.cardRenderingService.renderCard = { _ in
                state.renderCallCount += 1
                return RenderedCard(
                    frontHTML: "<p>render-\(state.renderCallCount)</p>",
                    backHTML: "<p>back-\(state.renderCallCount)</p>",
                    cardCSS: ""
                )
            }
            $0.decksService.setCurrentDeck = { _ in }
        } operation: {
            let session = ReviewSession(deckId: 1)
            session.start()
            try await Task.sleep(for: .milliseconds(50))

            let originalNoteId = session.currentNote?.id
            XCTAssertEqual(state.renderCallCount, 1)
            XCTAssertTrue(session.frontHTML.contains("render-1"))

            // Simulate field edit
            state.noteFields = "new front\u{1f}new back"
            await session.refreshAfterEdit()

            XCTAssertEqual(session.currentNote?.id, originalNoteId, "queue does not advance")
            XCTAssertEqual(state.renderCallCount, 2, "renderCard called again on refresh")
            XCTAssertTrue(session.frontHTML.contains("render-2"), "frontHTML reflects re-render")
        }
    }
}
