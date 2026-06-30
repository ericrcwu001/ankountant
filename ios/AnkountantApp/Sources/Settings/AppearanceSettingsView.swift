import SwiftUI
import AnkountantTheme

struct AppearanceSettingsView: View {
    @Bindable var manager: ThemeManager

    var body: some View {
        Form {
            Section("Theme") {
                themePickerRow
            }

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

    @ViewBuilder
    private var themePickerRow: some View {
        HStack(spacing: AnkountantSpacing.md) {
            ThemeCard(theme: .vivid, label: "Vivid", isSelected: manager.theme == .vivid) {
                manager.theme = .vivid
            }
            ThemeCard(theme: .muted, label: "Muted", isSelected: manager.theme == .muted) {
                manager.theme = .muted
            }
        }
        .padding(.vertical, AnkountantSpacing.xs)
    }
}

private struct ThemeCard: View {
    let theme: Theme
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let preview = Palette.resolve(theme: theme, scheme: systemScheme)
        Button(action: onTap) {
            VStack(spacing: AnkountantSpacing.sm) {
                VStack(spacing: 4) {
                    bar(color: preview.background)
                    bar(color: preview.surface)
                    bar(color: preview.accent)
                }
                .padding(AnkountantSpacing.sm)
                .background(preview.surface, in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(label).bold()
                }
                .font(.subheadline)
            }
            .padding(AnkountantSpacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? preview.accent : preview.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func bar(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color).frame(height: 10)
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
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .ankountantFont(.captionBold)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }
}

#Preview("Vivid Light") {
    NavigationStack { AppearanceSettingsView(manager: ThemeManager(defaults: UserDefaults(suiteName: "preview-vivid-light")!)) }
        .environment(\.palette, .vividLight)
        .preferredColorScheme(.light)
}

#Preview("Muted Dark") {
    NavigationStack { AppearanceSettingsView(manager: ThemeManager(defaults: UserDefaults(suiteName: "preview-muted-dark")!)) }
        .environment(\.palette, .mutedDark)
        .preferredColorScheme(.dark)
}
