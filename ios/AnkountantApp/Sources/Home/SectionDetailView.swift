// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiServices
import Dependencies

/// Per-section readiness detail, pushed from a summit peak/row. Reuses the shared
/// `ReadinessBandView` (abstain-aware CPA band) and `TopicBreakdownList` (Constraint
/// 2: per-confusion-set Memory / Performance with Wilson ranges). Loads its own
/// readiness off the main actor from the section code.
struct SectionDetailView: View {
    let section: CPASection

    @Dependency(\.schedulerService) private var schedulerService
    @Environment(\.palette) private var palette

    @State private var summary: ReadinessSummary?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
                header

                if let summary {
                    TopicBreakdownList(summary: summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ankountantCard(elevated: true)
                } else if loaded {
                    AnkountantStatusMessageView(
                        title: "Readiness unavailable",
                        message: "Couldn't load \(section.code) readiness.",
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AnkountantSpacing.xl)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AnkountantSpacing.xl)
                }
            }
            .padding(AnkountantSpacing.lg)
        }
        .ankountantSectionBackground()
        .navigationTitle(section.code)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: section.code) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text(section.displayName)
                .ankountantFont(.sectionHeading)
                .foregroundStyle(palette.textPrimary)
            if let summary {
                ReadinessBandView(band: summary.band)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ankountantCard(elevated: true)
    }

    private func load() async {
        // Off the main actor: getReadiness is a synchronous FFI call. Capture the
        // @Sendable closure before hopping so swift-dependencies overrides survive.
        let getReadiness = schedulerService.getReadiness
        let code = section.code
        let result = await Task.detached(priority: .userInitiated) {
            try? getReadiness(code)
        }.value
        guard !Task.isCancelled else { return }
        summary = result
        loaded = true
    }
}
