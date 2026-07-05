import SwiftUI
import UIKit
import AnkiClients
import AnkiKit
import AnkiServices
import Dependencies
import Foundation

@Observable @MainActor
final class ReviewSession {
    let deckId: Int64

    @ObservationIgnored @Dependency(\.decksService) var decks
    @ObservationIgnored @Dependency(\.schedulerService) var scheduler
    @ObservationIgnored @Dependency(\.cardRenderingService) var cardRendering
    @ObservationIgnored @Dependency(\.collectionService) var collection
    @ObservationIgnored @Dependency(\.notesService) var notes
    @ObservationIgnored @Dependency(\.notetypesService) var notetypes
    @ObservationIgnored @Dependency(\.cardClient) var cardClient

    private(set) var frontHTML: String = ""
    private(set) var backHTML: String = ""
    private(set) var cardCSS: String = ""
    private(set) var showAnswer: Bool = false
    private(set) var sessionStats: SessionStats = .init()
    private(set) var remainingCounts: DeckCounts = .zero
    private(set) var isFinished: Bool = false
    private(set) var canUndo: Bool = false
    private(set) var nextIntervals: [Rating: String] = [:]
    private(set) var typedAnswerRequestID: Int = 0
    private(set) var isRevealingAnswer: Bool = false
    private(set) var replayRequestID: Int = 0       // plumbed; consumer is PR 1b
    private(set) var stopAudioRequestID: Int = 0    // plumbed; consumer is PR 1b
    private(set) var isAudioPlaying: Bool = false
    private(set) var currentNote: NoteRecord?
    private(set) var cardChromeColor: Color = .clear
    private(set) var cardChromeIsDark: Bool = false
    private(set) var errorMessage: String?
    private(set) var currentFlag: UInt32 = 0

    private var reviewStartTime: Date = .now
    private var cardQueue: [QueuedReviewCard] = []
    private var currentQueuedCard: QueuedReviewCard?
    private var lastRating: Rating? = nil

    // Typed-answer state
    private var renderedFrontHTML: String = ""
    private var renderedBackHTML: String = ""
    private var typedAnswerState: TypedAnswerState?
    private var typedAnswerContinuation: CheckedContinuation<String?, Never>?

    // MARK: - Computed

    var requiresTypedAnswerInput: Bool {
        typedAnswerState != nil && !showAnswer
    }

    var currentCardOrdinal: UInt32 {
        UInt32(currentQueuedCard?.card.ord ?? 0)
    }

    struct TemplateTarget: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let notetypeId: Int64
        public let ordinal: Int

        public static func == (lhs: TemplateTarget, rhs: TemplateTarget) -> Bool {
            lhs.notetypeId == rhs.notetypeId && lhs.ordinal == rhs.ordinal
        }
    }

    var currentTemplateTarget: TemplateTarget? {
        guard let card = currentQueuedCard?.card, let note = currentNote else { return nil }
        return TemplateTarget(notetypeId: note.mid, ordinal: Int(card.ord))
    }

    var currentCardId: Int64? {
        currentQueuedCard?.card.id
    }

    // MARK: - Init

    init(deckId: Int64) {
        self.deckId = deckId
    }

    // MARK: - Public interface

    func clearError() {
        errorMessage = nil
    }

    func reportRenderError(_ message: String) {
        errorMessage = message
    }

    func start() async {
        errorMessage = nil
        isFinished = false
        showAnswer = false
        canUndo = false
        sessionStats = .init()
        remainingCounts = .zero
        cardQueue = []
        currentQueuedCard = nil
        currentNote = nil
        currentFlag = 0
        nextIntervals = [:]
        typedAnswerState = nil

        do {
            let setCurrentDeck = decks.setCurrentDeck
            let getQueuedCards = scheduler.getQueuedCards
            let deckId = deckId
            let result = try await Task.detached(priority: .userInitiated) {
                try setCurrentDeck(deckId)
                return try getQueuedCards(200)
            }.value
            cardQueue = result.cards
            remainingCounts = DeckCounts(
                newCount: result.newCount,
                learnCount: result.learningCount,
                reviewCount: result.reviewCount
            )
            await advanceToNextCard()
        } catch {
            errorMessage = "Failed to start review: \(error.localizedDescription)"
            isFinished = true
        }
    }

    func revealAnswer() async {
        guard !showAnswer, !isRevealingAnswer else { return }
        isRevealingAnswer = true
        defer { isRevealingAnswer = false }

        if typedAnswerState == nil {
            backHTML = strippingTypedAnswerPlaceholders(from: renderedBackHTML)
            showAnswer = true
            return
        }

        typedAnswerRequestID += 1  // triggers JS to read <input> via updateUIView

        let typed = await readTypedAnswerWithTimeout()
        if let state = typedAnswerState {
            do {
                backHTML = try await makeTypedAnswerBackHTML(state: state, typedAnswer: typed ?? "")
            } catch {
                errorMessage = "Failed to compare typed answer: \(error.localizedDescription)"
                backHTML = renderedBackHTML.replacingOccurrences(of: state.placeholder, with: "")
            }
        } else {
            backHTML = strippingTypedAnswerPlaceholders(from: renderedBackHTML)
        }
        showAnswer = true
    }

    /// Called by CardWebViewCoordinator when JS delivers the typed answer.
    func submitTypedAnswer(_ typed: String?) {
        typedAnswerContinuation?.resume(returning: typed)
        typedAnswerContinuation = nil
    }

    func answer(rating: Rating, confidence: ConfidenceLevel? = nil) async {
        guard showAnswer, let queued = currentQueuedCard else { return }

        let timeSpent = UInt32(Date.now.timeIntervalSince(reviewStartTime) * 1000)

        do {
            let states = try queued.states.recordingConfidence(confidence?.rawValue)
            let answerReviewCard = scheduler.answerReviewCard
            let getQueuedCards = scheduler.getQueuedCards
            let result = try await Task.detached(priority: .userInitiated) {
                try answerReviewCard(queued.card.id, rating, timeSpent, states)
                return try getQueuedCards(200)
            }.value

            sessionStats.reviewed += 1
            if rating != .again { sessionStats.correct += 1 }
            sessionStats.totalTimeMs += Int(timeSpent)
            lastRating = rating
            canUndo = true

            cardQueue = result.cards
            remainingCounts = DeckCounts(
                newCount: result.newCount,
                learnCount: result.learningCount,
                reviewCount: result.reviewCount
            )
            await advanceToNextCard()
        } catch {
            errorMessage = "Failed to answer card: \(error.localizedDescription)"
        }
    }

    func undo() async {
        guard canUndo else { return }

        do {
            let undoLast = collection.undoLast
            let getQueuedCards = scheduler.getQueuedCards
            let result = try await Task.detached(priority: .userInitiated) {
                try undoLast()
                return try getQueuedCards(200)
            }.value
            canUndo = false

            sessionStats.reviewed -= 1
            if let last = lastRating, last != .again {
                sessionStats.correct -= 1
            }
            lastRating = nil

            cardQueue = result.cards
            remainingCounts = DeckCounts(
                newCount: result.newCount,
                learnCount: result.learningCount,
                reviewCount: result.reviewCount
            )
            await advanceToNextCard()
        } catch {
            errorMessage = "Failed to undo review: \(error.localizedDescription)"
        }
    }

    func handleCardActionSuccess(shouldAdvance: Bool) async {
        if shouldAdvance {
            await refreshQueueAfterCardAction()
        } else {
            await refreshCurrentCardMetadata()
        }
    }

    func updateAudioPlaying(_ playing: Bool) {
        isAudioPlaying = playing
    }

    func updateCardChrome(color: UIColor, isDark: Bool) {
        cardChromeColor = Color(uiColor: color)
        cardChromeIsDark = isDark
    }

    func bumpReplayRequest() {
        replayRequestID += 1
    }

    func bumpStopAudioRequest() {
        stopAudioRequestID += 1
    }

    func refreshAfterEdit() async {
        guard let queued = currentQueuedCard else { return }

        do {
            let loaded = try await loadCardPresentation(for: queued)
            currentNote = loaded.note
            renderedFrontHTML = loaded.rendered.frontHTML
            renderedBackHTML = loaded.rendered.backHTML
            cardCSS = loaded.rendered.cardCSS

            typedAnswerState = loaded.typedAnswerState
            frontHTML = makeTypedAnswerFrontHTML(state: typedAnswerState, raw: renderedFrontHTML)

            if showAnswer, let state = typedAnswerState {
                do {
                    backHTML = try await makeTypedAnswerBackHTML(state: state, typedAnswer: "")
                } catch {
                    errorMessage = "Failed to compare typed answer: \(error.localizedDescription)"
                    backHTML = strippingTypedAnswerPlaceholders(from: renderedBackHTML)
                }
            } else if showAnswer {
                backHTML = strippingTypedAnswerPlaceholders(from: renderedBackHTML)
            } else {
                backHTML = renderedBackHTML
            }
            if let typedAnswerError = loaded.typedAnswerError {
                errorMessage = typedAnswerError
            }
        } catch {
            errorMessage = "Failed to render edited card: \(error.localizedDescription)"
        }
    }

    // MARK: - Private: card advancement

    private func advanceToNextCard() async {
        guard let next = cardQueue.first else {
            isFinished = true
            currentQueuedCard = nil
            currentNote = nil
            currentFlag = 0
            return
        }

        currentQueuedCard = next
        currentFlag = UInt32(next.card.flags) & 0b111
        showAnswer = false
        reviewStartTime = .now
        nextIntervals = next.nextIntervals
        typedAnswerState = nil
        stopAudioRequestID += 1

        do {
            let loaded = try await loadCardPresentation(for: next)
            currentNote = loaded.note
            renderedFrontHTML = loaded.rendered.frontHTML
            renderedBackHTML = loaded.rendered.backHTML
            cardCSS = loaded.rendered.cardCSS

            typedAnswerState = loaded.typedAnswerState
            frontHTML = makeTypedAnswerFrontHTML(state: typedAnswerState, raw: renderedFrontHTML)
            backHTML = renderedBackHTML
            if let typedAnswerError = loaded.typedAnswerError {
                errorMessage = typedAnswerError
            }
        } catch {
            errorMessage = "Failed to render card: \(error.localizedDescription)"
            currentNote = nil
            renderedFrontHTML = "<p>Unable to render this card.</p>"
            renderedBackHTML = "<p>Unable to render this card.</p>"
            cardCSS = ""
            frontHTML = renderedFrontHTML
            backHTML = renderedBackHTML
            typedAnswerState = nil
        }
    }

    private func loadCardPresentation(for queued: QueuedReviewCard) async throws -> LoadedCardPresentation {
        let getNote = notes.getNote
        let renderCard = cardRendering.renderCard
        let getNotetypeFields = notetypes.getNotetypeFields
        let extractClozeForTyping = cardRendering.extractClozeForTyping
        let cardOrdinal = Int(queued.card.ord)
        return try await Task.detached(priority: .userInitiated) {
            let note = try getNote(queued.card.nid)
            let rendered = try renderCard(queued.card.id)
            let typedAnswerState: TypedAnswerState?
            let typedAnswerError: String?
            do {
                typedAnswerState = try resolvedTypedAnswerState(
                    for: queued,
                    note: note,
                    frontHTML: rendered.frontHTML,
                    cardOrdinal: cardOrdinal,
                    getNotetypeFields: getNotetypeFields,
                    extractClozeForTyping: extractClozeForTyping
                )
                typedAnswerError = nil
            } catch {
                typedAnswerState = nil
                typedAnswerError = "Failed to prepare typed answer: \(error.localizedDescription)"
            }
            return LoadedCardPresentation(
                note: note,
                rendered: rendered,
                typedAnswerState: typedAnswerState,
                typedAnswerError: typedAnswerError
            )
        }.value
    }

    private func refreshQueueAfterCardAction() async {
        do {
            let getQueuedCards = scheduler.getQueuedCards
            let result = try await Task.detached(priority: .userInitiated) {
                try getQueuedCards(200)
            }.value
            cardQueue = result.cards
            remainingCounts = DeckCounts(
                newCount: result.newCount,
                learnCount: result.learningCount,
                reviewCount: result.reviewCount
            )
            await advanceToNextCard()
        } catch {
            errorMessage = "Failed to refresh review after card action: \(error.localizedDescription)"
        }
    }

    private func refreshCurrentCardMetadata() async {
        guard let cardId = currentCardId else { return }

        do {
            let getCardFlags = cardClient.getCardFlags
            currentFlag = try await Task.detached(priority: .userInitiated) {
                try getCardFlags(cardId)
            }.value
        } catch {
            errorMessage = "Failed to refresh card action state: \(error.localizedDescription)"
        }
    }

    // MARK: - Typed-answer HTML generation

    private func makeTypedAnswerFrontHTML(state: TypedAnswerState?, raw: String) -> String {
        guard let state, raw.contains(state.placeholder) else {
            return strippingTypedAnswerPlaceholders(from: raw)
        }
        if state.expected.isEmpty {
            return raw.replacingOccurrences(of: state.placeholder, with: "")
        }
        let inputHTML = """
        <center>
        <input type="text" id="typeans" autocapitalize="none" autocomplete="off" autocorrect="off" spellcheck="false" onkeypress="return ankountantHandleTypeAnswerKey(event);" style="font-family: '\(state.fontName)'; font-size: \(state.fontSize)px;">
        </center>
        """
        return raw.replacingOccurrences(of: state.placeholder, with: inputHTML)
    }

    private func makeTypedAnswerBackHTML(state: TypedAnswerState, typedAnswer: String) async throws -> String {
        guard renderedBackHTML.contains(state.placeholder) else {
            return renderedBackHTML
        }
        if state.expected.isEmpty {
            return renderedBackHTML.replacingOccurrences(of: state.placeholder, with: "")
        }
        let compareAnswer = cardRendering.compareAnswer
        let diff = try await Task.detached(priority: .userInitiated) {
            try compareAnswer(state.expected, typedAnswer, state.combining)
        }.value
        let wrapped = "<div style=\"font-family: '\(state.fontName)'; font-size: \(state.fontSize)px\">\(diff)</div>"
        return renderedBackHTML.replacingOccurrences(of: state.placeholder, with: wrapped)
    }

    private func strippingTypedAnswerPlaceholders(from html: String) -> String {
        let regex = typedAnswerRegex(pattern: #"\[\[type:.+?\]\]"#)
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    // MARK: - Typed-answer async read

    private func readTypedAnswerWithTimeout() async -> String? {
        // Suspend until JS calls submitTypedAnswer or 100 ms elapses.
        // We register our continuation on the MainActor, then launch a timeout
        // Task that also runs on MainActor and cancels if the continuation fires first.
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            // Store continuation — submitTypedAnswer will resume it
            typedAnswerContinuation = cont
            // Timeout: if the continuation is still pending after 100 ms, drain it with nil
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.typedAnswerContinuation != nil else { return }
                self.typedAnswerContinuation?.resume(returning: nil)
                self.typedAnswerContinuation = nil
            }
        }
    }
}

private struct LoadedCardPresentation: Sendable {
    let note: NoteRecord
    let rendered: RenderedCard
    let typedAnswerState: TypedAnswerState?
    let typedAnswerError: String?
}

private struct TypedAnswerPlaceholder {
    let rawToken: String
    let fieldName: String
    let combining: Bool
    let clozeOrdinal: UInt32?
}

private func resolvedTypedAnswerState(
    for queued: QueuedReviewCard,
    note: NoteRecord,
    frontHTML: String,
    cardOrdinal: Int,
    getNotetypeFields: @Sendable (_ id: Int64) throws -> [NotetypeFieldInfo],
    extractClozeForTyping: @Sendable (_ text: String, _ ordinal: UInt32) throws -> String
) throws -> TypedAnswerState? {
    guard let placeholder = firstTypedAnswerPlaceholder(in: frontHTML, cardOrdinal: cardOrdinal) else {
        return nil
    }

    let fields = try getNotetypeFields(note.mid)

    guard let field = fields.first(where: { $0.name == placeholder.fieldName }) else {
        throw ReviewTypedAnswerError.missingField(placeholder.fieldName, note.mid)
    }

    let fieldValues = note.flds.components(separatedBy: "\u{1f}")
    guard fieldValues.indices.contains(field.ordinal) else {
        throw ReviewTypedAnswerError.missingNoteField(field.name, note.id)
    }

    var expected = fieldValues[field.ordinal]

    if let clozeOrdinal = placeholder.clozeOrdinal {
        expected = try extractClozeForTyping(expected, clozeOrdinal)
    }

    return TypedAnswerState(
        placeholder: placeholder.rawToken,
        expected: expected,
        combining: placeholder.combining,
        fontName: field.fontName,
        fontSize: field.fontSize
    )
}

private enum ReviewTypedAnswerError: LocalizedError {
    case missingField(String, Int64)
    case missingNoteField(String, Int64)

    var errorDescription: String? {
        switch self {
        case .missingField(let fieldName, let notetypeId):
            "field \"\(fieldName)\" does not exist on notetype \(notetypeId)."
        case .missingNoteField(let fieldName, let noteId):
            "field \"\(fieldName)\" is missing from note \(noteId)."
        }
    }
}

private func firstTypedAnswerPlaceholder(in html: String, cardOrdinal: Int) -> TypedAnswerPlaceholder? {
    let regex = typedAnswerRegex(pattern: #"\[\[type:(.+?)\]\]"#)
    let nsRange = NSRange(html.startIndex..., in: html)
    guard let match = regex.firstMatch(in: html, range: nsRange),
          let rawRange = Range(match.range(at: 0), in: html),
          let specRange = Range(match.range(at: 1), in: html)
    else {
        return nil
    }

    var spec = String(html[specRange])
    var combining = true
    var clozeOrdinal: UInt32?

    if spec.hasPrefix("cloze:") {
        spec.removeFirst("cloze:".count)
        clozeOrdinal = UInt32(cardOrdinal) + 1
    }
    if spec.hasPrefix("nc:") {
        spec.removeFirst("nc:".count)
        combining = false
    }

    guard !spec.isEmpty else { return nil }

    return TypedAnswerPlaceholder(
        rawToken: String(html[rawRange]),
        fieldName: spec,
        combining: combining,
        clozeOrdinal: clozeOrdinal
    )
}

private func typedAnswerRegex(pattern: String) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern)
    } catch {
        preconditionFailure("Invalid typed-answer regex: \(error)")
    }
}
