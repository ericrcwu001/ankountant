import SwiftUI
import AnkountantTheme
import AnkiSync
import Sharing

struct OnboardingView: View {
    @Environment(\.palette) private var palette
    @Shared(.onboardingCompleted) private var onboardingCompleted
    @Shared(.syncMode) private var syncMode
    @State private var showServerSetup = false
    @State private var serverURL = ""

    var body: some View {
        VStack(spacing: AnkountantSpacing.xxl) {
            Spacer()

            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 64))
                .foregroundStyle(palette.accent)

            Text("Welcome")
                .ankountantFont(.displayHero)
                .foregroundStyle(palette.textPrimary)

            Text("Choose how to sync your collection")
                .ankountantFont(.body)
                .foregroundStyle(palette.textSecondary)

            VStack(spacing: AnkountantSpacing.md) {
                if showServerSetup {
                    VStack(spacing: AnkountantSpacing.md) {
                        AnkiMobileAttributionView()
                            .padding(.horizontal)

                        TextField("Server URL", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .padding(.horizontal)

                        Button("Continue") {
                            saveAndContinue()
                        }
                        .buttonStyle(AnkountantPrimaryButtonStyle())
                        .disabled(serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Back") {
                            showServerSetup = false
                        }
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                    }
                } else {
                    Button {
                        showServerSetup = true
                    } label: {
                        Label("Custom Server", systemImage: "server.rack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AnkountantPrimaryButtonStyle())

                    Button {
                        $syncMode.withLock { $0 = .local }
                        $onboardingCompleted.withLock { $0 = true }
                    } label: {
                        Label("Use Locally", systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AnkountantSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 32)

            Text("You can change this anytime in sync settings")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textTertiary)

            Spacer()
        }
        .background(palette.background)
    }

    private func saveAndContinue() {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        try? KeychainHelper.saveEndpoint(url)
        $syncMode.withLock { $0 = .custom }
        $onboardingCompleted.withLock { $0 = true }
    }
}
