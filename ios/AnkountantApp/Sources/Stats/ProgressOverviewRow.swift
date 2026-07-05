import SwiftUI
import AnkountantTheme

struct ProgressOverviewRow: View {
    let icon: String
    let title: String
    let value: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: AnkountantSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 34, height: 34)
                .background(palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .ankountantFont(.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value)
                .ankountantFont(.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, AnkountantSpacing.md)
        .padding(.vertical, AnkountantSpacing.sm)
    }
}
