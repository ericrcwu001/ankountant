import SwiftUI
import AnkountantTheme
import AnkiKit
import Sharing

struct ReviewView: View {
    let deckId: Int64
    let onDismiss: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Shared(.appStorage(ReviewPreferences.Keys.showAudioReplayButton))
    private var showAudioReplayButton: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showContextMenuButton))
    private var showContextMenuButton: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.openLinksExternally))
    private var openLinksExternally: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.cardContentAlignment))
    private var cardContentAlignment: String = CardWebViewContentAlignment.center.rawValue

    @Shared(.appStorage(ReviewPreferences.Keys.autoMatchCardBackground))
    private var autoMatchCardBackground: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showRemainingDays))
    private var showRemainingDays: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showNextReviewTime))
    private var showNextReviewTime: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.disperseAnswerButtons))
    private var disperseAnswerButtons: Bool = false

    @Shared(.appStorage(ReaderPreferences.Keys.tapLookup))
    private var tapLookup: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.playAudioInSilentMode))
    private var playAudioInSilentMode: Bool = false

    @Shared(.appStorage(LearningFeedbackPreferenceKeys.enabled))
    private var learningFeedbackEnabled: Bool = LearningFeedbackPreferenceKeys.defaultEnabled

    @Shared(.appStorage(LearningFeedbackPreferenceKeys.model))
    private var learningFeedbackModel: String = defaultLearningFeedbackModel

    @State private var session: ReviewSession
    @State private var editingNote: NoteRecord?
    @State private var editingTemplate: ReviewSession.TemplateTarget?
    @State private var lookupQuery: String?
    @State private var committedConfidence: ConfidenceLevel?

    init(deckId: Int64, onDismiss: @escaping () -> Void) {
        self.deckId = deckId
        self.onDismiss = onDismiss
        self._session = State(initialValue: ReviewSession(deckId: deckId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showRemainingDays {
                    HStack(spacing: 12) {
                        DeckCountsView(counts: session.remainingCounts)
                        Spacer()
                        Text("\(session.sessionStats.reviewed) reviewed")
                            .ankountantFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if session.isFinished {
                    if let errorMessage = session.errorMessage {
                        failedView(errorMessage)
                    } else {
                        ReviewFinishedView(
                            summary: ReviewCompletionSummary(
                                reviewed: session.sessionStats.reviewed,
                                accuracy: session.sessionStats.accuracy
                            ),
                            onDone: onDismiss
                        )
                    }
                } else {
                    cardView
                }
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo answer", systemImage: "arrow.uturn.backward") {
                        Task { await session.undo() }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!session.canUndo)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit note", systemImage: "pencil") {
                        editingNote = session.currentNote
                    }
                    .labelStyle(.iconOnly)
                    .disabled(session.currentNote == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Look up word", systemImage: "character.book.closed") {
                        lookupQuery = ""
                    }
                    .labelStyle(.iconOnly)
                }
                if showAudioReplayButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            session.isAudioPlaying ? "Pause audio" : "Replay audio",
                            systemImage: session.isAudioPlaying ? "pause.circle" : "play.circle"
                        ) {
                            if session.isAudioPlaying {
                                session.bumpStopAudioRequest()
                            } else {
                                session.bumpReplayRequest()
                            }
                        }
                        .labelStyle(.iconOnly)
                        .disabled(session.currentNote == nil)
                    }
                }
                if showContextMenuButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let cardId = session.currentCardId {
                                CardContextMenu(
                                    cardId: cardId,
                                    noteId: session.currentNote?.id,
                                    onActionSuccess: { shouldAdvance in
                                        Task {
                                            await session.handleCardActionSuccess(shouldAdvance: shouldAdvance)
                                        }
                                    }
                                )
                            }
                            Divider()
                            Button {
                                editingTemplate = session.currentTemplateTarget
                            } label: {
                                Label("Edit Template", systemImage: "square.and.pencil")
                            }
                            .disabled(session.currentTemplateTarget == nil)
                        } label: {
                            if session.currentFlag != 0 {
                                Label("Review actions", systemImage: "flag.fill")
                                    .foregroundStyle(flagColor(for: session.currentFlag))
                                    .labelStyle(.iconOnly)
                            } else {
                                Label("Review actions", systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                            }
                        }
                        .disabled(session.currentNote == nil)
                    }
                }
            }
            .toolbarBackground(
                autoMatchCardBackground ? session.cardChromeColor : Color.clear,
                for: .navigationBar
            )
            .toolbarBackground(
                autoMatchCardBackground ? .visible : .automatic,
                for: .navigationBar
            )
            .toolbarColorScheme(
                reviewToolbarColorScheme(
                    autoMatchCardBackground: autoMatchCardBackground,
                    cardChromeIsDark: session.cardChromeIsDark
                ),
                for: .navigationBar
            )
            .sheet(item: $editingNote) { note in
                NavigationStack {
                    NoteEditorView(note: note) {
                        Task { await session.refreshAfterEdit() }
                    }
                }
            }
            .sheet(item: $editingTemplate) { target in
                NavigationStack {
                    TemplateEditorView(
                        notetypeId: target.notetypeId,
                        initialTemplateIndex: target.ordinal,
                        mode: .currentCard,
                        onSaved: { await session.refreshAfterEdit() }
                    )
                }
            }
            .sheet(item: Binding(
                get: { lookupQuery.map(ReviewLookupQuery.init) },
                set: { lookupQuery = $0?.text }
            )) { wrapped in
                LookupPopupView(initialQuery: wrapped.text) {
                    lookupQuery = nil
                }
            }
            .alert(
                "Review error",
                isPresented: Binding(
                    get: { session.errorMessage != nil && !session.isFinished },
                    set: { if !$0 { session.clearError() } }
                ),
                presenting: session.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
        .task {
            ReviewAudioSession.apply(playInSilent: playAudioInSilentMode)
            await session.start()
        }
        .onChange(of: playAudioInSilentMode) { _, newValue in
            ReviewAudioSession.apply(playInSilent: newValue)
        }
        .onDisappear {
            Task { await writeWidgetSnapshot() }
        }
    }

    @ViewBuilder
    private var cardView: some View {
        VStack(spacing: 0) {
            CardWebView(
                html: session.showAnswer ? session.backHTML : session.frontHTML,
                cardCSS: session.cardCSS,
                isAnswerSide: session.showAnswer,
                cardOrdinal: session.currentCardOrdinal,
                replayRequestID: session.replayRequestID,
                stopAudioRequestID: session.stopAudioRequestID,
                typedAnswerRequestID: session.typedAnswerRequestID,
                openLinksExternally: openLinksExternally,
                contentAlignment: CardWebViewContentAlignment(rawValue: cardContentAlignment) ?? .center,
                onTypedAnswerSubmitted: { typed in session.submitTypedAnswer(typed) },
                onAudioStateChange: { playing in session.updateAudioPlaying(playing) },
                onCardBackgroundColorChange: { color, isDark in
                    session.updateCardChrome(color: color, isDark: isDark)
                },
                onLookupRequested: tapLookup ? { text, _, _ in
                    if let text, !text.isEmpty { lookupQuery = text }
                } : nil,
                onRenderError: { message in session.reportRenderError(message) }
            )

            if let learningFeedbackState = session.learningFeedbackState {
                LearningFeedbackPanel(state: learningFeedbackState)
                    .padding(.horizontal)
                    .padding(.top, AnkountantSpacing.md)
            }

            Spacer()

            if session.showAnswer {
                if session.learningFeedbackState == nil {
                    answerButtons
                } else {
                    learningFeedbackContinueButton
                }
            } else {
                confidencePanel
            }
        }
        .onChange(of: session.currentCardId) { _, _ in
            committedConfidence = nil
        }
    }

    private var confidencePanel: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            HStack {
                Label("Confidence Check", systemImage: "checkmark.seal")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(session.currentCardId == nil ? "" : "Before reveal")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            ConfidenceGateView(committed: $committedConfidence)
            Button {
                Task { await session.revealAnswer() }
            } label: {
                Text("Reveal answer")
                    .ankountantFont(.bodyEmphasis)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AnkountantPrimaryButtonStyle())
            .disabled(committedConfidence == nil || session.isRevealingAnswer)
        }
        .padding(AnkountantSpacing.lg)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .padding()
    }

    private var answerButtons: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AnkountantSpacing.sm) {
                    ratingButtons
                }
            } else {
                HStack(spacing: disperseAnswerButtons ? 16 : 8) {
                    ratingButtons
                }
            }
        }
        .padding(.horizontal, disperseAnswerButtons ? 20 : 16)
        .padding(.vertical, 16)
    }

    private var learningFeedbackContinueButton: some View {
        Button("Continue", systemImage: "arrow.right") {
            committedConfidence = nil
            Task { await session.continueAfterLearningFeedback() }
        }
        .buttonStyle(AnkountantPrimaryButtonStyle())
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var ratingButtons: some View {
        Group {
            ratingButton(.again, color: palette.danger)
            ratingButton(.hard, color: palette.warning)
            ratingButton(.good, color: palette.positive)
            ratingButton(.easy, color: palette.info)
        }
    }

    private func ratingButton(_ rating: Rating, color: Color) -> some View {
        Button {
            let confidence = committedConfidence
            committedConfidence = nil
            Task {
                await session.answer(
                    rating: rating,
                    confidence: confidence,
                    learningFeedbackEnabled: learningFeedbackEnabled,
                    learningFeedbackModel: learningFeedbackModel
                )
            }
        } label: {
            VStack(spacing: 4) {
                if showNextReviewTime {
                    Text(session.nextIntervals[rating] ?? "")
                        .ankountantFont(.micro)
                        .lineLimit(1)
                }
                Text(ratingLabel(rating))
                    .ankountantFont(.captionBold)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private func ratingLabel(_ rating: Rating) -> String {
        switch rating {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    private func flagColor(for value: UInt32) -> Color {
        switch value & 0b111 {
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        case 5: return .pink
        case 6: return .cyan
        case 7: return .purple
        default: return .secondary
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: AnkountantSpacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(palette.warning)
            Text("Review unavailable")
                .ankountantFont(.sectionHeading)
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .ankountantFont(.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            VStack(spacing: AnkountantSpacing.sm) {
                Button("Retry", systemImage: "arrow.clockwise") {
                    Task { await session.start() }
                }
                .buttonStyle(AnkountantPrimaryButtonStyle())

                Button("Done") { onDismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}

/// Identifiable wrapper so `.sheet(item:)` can distinguish "not
/// presented" from "presented with empty query" — the toolbar button
/// opens the lookup popup focused on the search bar with no query yet.
private struct ReviewLookupQuery: Identifiable {
    let id = UUID()
    let text: String
}
