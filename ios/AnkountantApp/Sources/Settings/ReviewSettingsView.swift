import AnkiKit
import AnkiSync
import SwiftUI
import Sharing

struct ReviewSettingsView: View {
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

    @Shared(.appStorage(ReviewPreferences.Keys.playAudioInSilentMode))
    private var playAudioInSilentMode: Bool = false

    @Shared(.appStorage(LearningFeedbackPreferenceKeys.enabled))
    private var learningFeedbackEnabled: Bool = LearningFeedbackPreferenceKeys.defaultEnabled

    @Shared(.appStorage(LearningFeedbackPreferenceKeys.model))
    private var learningFeedbackModel: String = defaultLearningFeedbackModel

    @State private var openAIAPIKey = ""
    @State private var openAIAPIKeySaved = false
    @State private var openAIAPIKeyStatus: String?

    var body: some View {
        Form {
            Section("Toolbar") {
                Toggle("Show audio replay button", isOn: Binding($showAudioReplayButton))
                Toggle("Show context menu", isOn: Binding($showContextMenuButton))
            }

            Section("Card Display") {
                Toggle("Match toolbar to card background", isOn: Binding($autoMatchCardBackground))
                Toggle("Open links externally", isOn: Binding($openLinksExternally))
                Picker("Content alignment", selection: Binding($cardContentAlignment)) {
                    Text("Center").tag(CardWebViewContentAlignment.center.rawValue)
                    Text("Top").tag(CardWebViewContentAlignment.top.rawValue)
                }
            }

            Section("Answer Buttons") {
                Toggle("Show remaining counts", isOn: Binding($showRemainingDays))
                Toggle("Show next review time", isOn: Binding($showNextReviewTime))
                Toggle("Spread answer buttons", isOn: Binding($disperseAnswerButtons))
            }

            Section("Audio") {
                Toggle("Play audio in silent mode", isOn: Binding($playAudioInSilentMode))
            }

            Section("Feedback") {
                Toggle("AI feedback", isOn: Binding($learningFeedbackEnabled))
                TextField("Model", text: Binding($learningFeedbackModel))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("OpenAI API key", text: $openAIAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Button("Save", action: saveOpenAIAPIKey)
                        .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Clear", role: .destructive, action: clearOpenAIAPIKey)
                        .disabled(!openAIAPIKeySaved)
                }

                Text(openAIAPIKeySaved ? "OpenAI API key saved" : "No OpenAI API key saved")
                    .foregroundStyle(.secondary)

                if let openAIAPIKeyStatus {
                    Text(openAIAPIKeyStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshOpenAIAPIKeyStatus()
        }
    }

    private func refreshOpenAIAPIKeyStatus() {
        do {
            let key = try KeychainHelper.loadOpenAIAPIKey()
            openAIAPIKeySaved = key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            openAIAPIKeyStatus = nil
        } catch {
            openAIAPIKeySaved = false
            openAIAPIKeyStatus = error.localizedDescription
        }
    }

    private func saveOpenAIAPIKey() {
        do {
            try KeychainHelper.saveOpenAIAPIKey(openAIAPIKey)
            openAIAPIKey = ""
            openAIAPIKeySaved = true
            openAIAPIKeyStatus = "OpenAI API key saved"
        } catch {
            openAIAPIKeyStatus = error.localizedDescription
        }
    }

    private func clearOpenAIAPIKey() {
        do {
            try KeychainHelper.deleteOpenAIAPIKey()
            openAIAPIKey = ""
            openAIAPIKeySaved = false
            openAIAPIKeyStatus = "OpenAI API key cleared"
        } catch {
            openAIAPIKeyStatus = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ReviewSettingsView()
    }
}
