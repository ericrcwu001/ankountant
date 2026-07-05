import SwiftUI
import AnkountantTheme

struct ProgressRing: View {
    let fraction: Double
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.borderSubtle, lineWidth: 14)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: AnkountantSpacing.xxs) {
                Text("\(Int((fraction * 100).rounded()))")
                    .ankountantFont(.sectionHeading)
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("%")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .accessibilityLabel("Progress \(Int((fraction * 100).rounded())) percent")
    }
}
