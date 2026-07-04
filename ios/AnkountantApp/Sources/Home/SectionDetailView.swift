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
    @State private var loadErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
                header

                if let summary {
                    TopicBreakdownList(summary: summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ankountantCard(elevated: true)
                } else if loaded {
                    VStack(spacing: AnkountantSpacing.md) {
                        AnkountantStatusMessageView(
                            title: "Readiness unavailable",
                            message: loadErrorMessage ?? "Couldn't load \(section.code) readiness.",
                            systemImage: "exclamationmark.triangle",
                            tone: .warning
                        )

                        Button("Retry") {
                            Task { await load() }
                        }
                        .buttonStyle(AnkountantPrimaryButtonStyle())
                    }
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
                ReadinessBandView(band: summary.band, topics: summary.topics)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ankountantCard(elevated: true)
    }

    private func load() async {
        loaded = false
        summary = nil
        loadErrorMessage = nil

        let getReadiness = schedulerService.getReadiness
        let code = section.code
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try getReadiness(code)
            }
        }.value
        guard !Task.isCancelled else { return }

        switch result {
        case .success(let loadedSummary):
            summary = loadedSummary
            loadErrorMessage = nil
        case .failure(let error):
            summary = nil
            loadErrorMessage = "Failed to load \(code) readiness: \(error.localizedDescription)"
        }

        loaded = true
    }
}
