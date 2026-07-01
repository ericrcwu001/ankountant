import SwiftUI
import AnkountantTheme

struct AppearanceSettingsView: View {
    @Bindable var manager: ThemeManager

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $manager.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented)
            }

            Section("Preview") {
                PreviewCard()
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PreviewCard: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("Preview")
                .ankountantFont(.cardTitle)
                .foregroundStyle(palette.textPrimary)
            Text("Body text in the active palette.")
                .ankountantFont(.body)
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: AnkountantSpacing.sm) {
                badge("Positive", color: palette.positive)
                badge("Warning", color: palette.warning)
                badge("Danger", color: palette.danger)
            }

            Button("Primary action") {}
                .buttonStyle(AnkountantPrimaryButtonStyle())
        }
        .padding(AnkountantSpacing.lg)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: AnkountantRadius.card))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .ankountantFont(.captionBold)
            .foregroundStyle(color)
            .padding(.horizontal, AnkountantSpacing.sm).padding(.vertical, AnkountantSpacing.xs)
            .background(color.opacity(0.15), in: Capsule())
    }
}

#Preview("Light") {
    NavigationStack { AppearanceSettingsView(manager: ThemeManager(defaults: UserDefaults(suiteName: "preview-light")!)) }
        .environment(\.palette, .light)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack { AppearanceSettingsView(manager: ThemeManager(defaults: UserDefaults(suiteName: "preview-dark")!)) }
        .environment(\.palette, .dark)
        .preferredColorScheme(.dark)
}
