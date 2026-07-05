import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import AnkiProto
import Dependencies
import SwiftProtobuf

struct StatsDashboardView: View {
    @Environment(\.palette) private var palette
    @Dependency(\.statsClient) var statsClient
    @Dependency(\.deckClient) var deckClient

    @State private var graphs: Anki_Stats_GraphsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var period: StatsPeriod = .month
    @State private var decks: [DeckInfo] = []
    @State private var selectedDeck: DeckInfo?
    @State private var deckLoadErrorMessage: String?
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AnkountantSpacing.lg) {
                if isLoading {
                    ProgressView("Loading statistics...")
                        .padding(.top, 40)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Failed to Load Stats", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadStats() }
                        }
                    }
                } else if let graphs {
                    if analyticsEvidenceIsEmpty(graphs) {
                        emptyAnalyticsState
                    } else {
                        analyticsDashboard(graphs)
                    }
                }
            }
            .padding(AnkountantSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .ankountantTabBarClearance()
        .background(palette.surface)
        .navigationTitle("Statistics")
        .task { await loadDecks() }
        .task(id: loadKey) { await loadStats() }
        .refreshable {
            await loadDecks()
            await loadStats()
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    /// Identity for the stats fetch: changing deck or period re-runs `loadStats`
    /// (and cancels the in-flight one) via `.task(id:)`.
    private var loadKey: String {
        "\(selectedDeck?.id.description ?? "all")|\(period.rawValue)"
    }

    private var deckMenu: some View {
        Menu {
            Button { selectedDeck = nil } label: {
                if selectedDeck == nil { Label("Whole Collection", systemImage: "checkmark") }
                else { Text("Whole Collection") }
            }
            Divider()
            ForEach(decks.filter({ !$0.name.contains("::") })) { deck in
                Button { selectedDeck = deck } label: {
                    if selectedDeck?.id == deck.id { Label(deck.name, systemImage: "checkmark") }
                    else { Text(deck.name) }
                }
            }
        } label: {
            filterCapsule(
                icon: "rectangle.stack",
                label: selectedDeck?.name ?? "Collection",
                accessibilityLabel: "Deck filter: \(selectedDeck?.name ?? "Whole Collection")"
            )
        }
    }

    private var periodMenu: some View {
        Menu {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Button { period = p } label: {
                    if period == p { Label(p.rawValue, systemImage: "checkmark") }
                    else { Text(p.rawValue) }
                }
            }
        } label: {
            filterCapsule(
                icon: "calendar",
                label: period.shortLabel,
                accessibilityLabel: "History period: \(period.rawValue)"
            )
        }
    }

    private func filterCapsule(icon: String, label: String, accessibilityLabel: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .fontWeight(.medium)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func analyticsDashboard(_ graphs: Anki_Stats_GraphsResponse) -> some View {
        ProgressOverviewCard(graphs: graphs)

        HStack(spacing: AnkountantSpacing.sm) {
            deckMenu
            periodMenu
            Spacer()
        }

        if let deckLoadErrorMessage {
            Text(deckLoadErrorMessage)
                .ankountantStatusText(.danger, font: .caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        PeriodStatsCard(period: period, today: graphs.today, reviews: graphs.reviews)
        FutureDueChart(futureDue: graphs.futureDue, period: period)
        HeatmapChartOptimized(reviews: graphs.reviews)
        ReviewsChart(reviews: graphs.reviews, period: period)
        CardCountsChart(cardCounts: graphs.cardCounts)
        IntervalsChart(intervals: graphs.intervals)
        EaseChart(eases: graphs.eases)
        HourlyChart(hours: graphs.hours, period: period)
        ButtonsChart(buttons: graphs.buttons, period: period)
        AddedChart(added: graphs.added, period: period)
        RetentionChart(trueRetention: graphs.trueRetention)
        RetrievabilityChart(retrievability: graphs.retrievability)
    }

    private var emptyAnalyticsState: some View {
        ContentUnavailableView {
            Label(emptyAnalyticsTitle, systemImage: "chart.bar.doc.horizontal")
        } description: {
            Text(emptyAnalyticsDescription)
        } actions: {
            VStack(spacing: AnkountantSpacing.sm) {
                if selectedDeck != nil {
                    Button("Clear deck filter", systemImage: "line.3.horizontal.decrease.circle") {
                        selectedDeck = nil
                    }
                }
                Button("Import package", systemImage: "square.and.arrow.down") {
                    showImport = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var emptyAnalyticsTitle: String {
        if let selectedDeck {
            return "No analytics for \(selectedDeck.name)"
        }
        return "No analytics evidence yet"
    }

    private var emptyAnalyticsDescription: String {
        if selectedDeck != nil {
            return "This deck has no cards or review history. Clear the filter or import a study package to start tracking evidence."
        }
        return "Import a study package, then review cards to fill retention, due load, and progress."
    }

    private func analyticsEvidenceIsEmpty(_ graphs: Anki_Stats_GraphsResponse) -> Bool {
        cardCountTotal(graphs.cardCounts.excludingInactive) == 0
            && graphs.added.added.values.allSatisfy { $0 == 0 }
            && graphs.futureDue.futureDue.values.allSatisfy { $0 == 0 }
            && graphs.today.answerCount == 0
            && graphs.reviews.count.values.allSatisfy { reviewTotal($0) == 0 }
    }

    private func cardCountTotal(_ counts: Anki_Stats_GraphsResponse.CardCounts.Counts) -> UInt64 {
        UInt64(counts.newCards)
            + UInt64(counts.learn)
            + UInt64(counts.relearn)
            + UInt64(counts.young)
            + UInt64(counts.mature)
            + UInt64(counts.suspended)
            + UInt64(counts.buried)
    }

    private func reviewTotal(_ reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews) -> UInt64 {
        UInt64(reviews.learn)
            + UInt64(reviews.relearn)
            + UInt64(reviews.young)
            + UInt64(reviews.mature)
            + UInt64(reviews.filtered)
    }

    private func loadDecks() async {
        let fetchAll = deckClient.fetchAll
        do {
            decks = try await Task.detached(priority: .userInitiated) {
                try fetchAll()
            }.value
            deckLoadErrorMessage = nil
        } catch {
            decks = []
            selectedDeck = nil
            deckLoadErrorMessage = "Failed to load deck filters: \(error.localizedDescription)"
        }
    }

    private func loadStats() async {
        if graphs == nil { isLoading = true }
        errorMessage = nil
        // Off the main actor: fetchGraphs is a synchronous FFI call and decoding
        // the (potentially large, e.g. "All Time") response is CPU-heavy. Running
        // either on @MainActor freezes the UI while switching time frames.
        // Capture the @Sendable closure first so swift-dependencies overrides survive.
        let fetch = statsClient.fetchGraphs
        let search = selectedDeck.map { "deck:\"\($0.name)\"" } ?? ""
        let days = UInt32(period.days)
        do {
            let response = try await Task.detached(priority: .userInitiated) {
                let data = try fetch(search, days)
                return try Anki_Stats_GraphsResponse(serializedBytes: data)
            }.value
            guard !Task.isCancelled else { return }
            graphs = response
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let ext = url.pathExtension.lowercased()
            guard ext == "apkg" || ext == "colpkg" else {
                importMessage = "Unsupported file type. Please select an .apkg or .colpkg file."
                showImportAlert = true
                return
            }
            Task { @MainActor in
                do {
                    importMessage = try await ImportHelper.importPackageInBackground(from: url)
                    await loadDecks()
                    await loadStats()
                } catch {
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
                showImportAlert = true
            }
        case .failure(let error):
            importMessage = "Could not select file: \(error.localizedDescription)"
            showImportAlert = true
        }
    }
}

private struct ProgressOverviewCard: View {
    let graphs: Anki_Stats_GraphsResponse
    @Environment(\.palette) private var palette

    private var counts: Anki_Stats_GraphsResponse.CardCounts.Counts {
        graphs.cardCounts.excludingInactive
    }

    private var activeCards: UInt32 {
        counts.newCards + counts.learn + counts.relearn + counts.young + counts.mature
    }

    private var masteredFraction: Double {
        guard activeCards > 0 else { return 0 }
        return Double(counts.mature) / Double(activeCards)
    }

    private var retentionFraction: Double? {
        let retention = graphs.trueRetention.month
        let passed = retention.youngPassed + retention.maturePassed
        let total = passed + retention.youngFailed + retention.matureFailed
        guard total > 0 else { return nil }
        return Double(passed) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.lg) {
            HStack(alignment: .center, spacing: AnkountantSpacing.lg) {
                ProgressRing(fraction: masteredFraction)
                    .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                    Text("Progress")
                        .ankountantFont(.displayHero)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(Int((masteredFraction * 100).rounded()))% mastered")
                        .ankountantFont(.bodyEmphasis)
                        .foregroundStyle(palette.textSecondary)
                    Text("\(formatNumber(activeCards)) active cards")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ProgressOverviewRow(
                    icon: "checkmark.seal",
                    title: "Cards mastered",
                    value: formatNumber(counts.mature)
                )
                Divider()
                ProgressOverviewRow(
                    icon: "target",
                    title: "Month retention",
                    value: retentionFraction.map(formatPercent) ?? "--"
                )
                Divider()
                ProgressOverviewRow(
                    icon: "clock.arrow.circlepath",
                    title: "Reviewed today",
                    value: formatNumber(graphs.today.answerCount)
                )
                Divider()
                ProgressOverviewRow(
                    icon: "calendar",
                    title: "Daily load",
                    value: formatNumber(graphs.futureDue.dailyLoad)
                )
            }
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
        }
        .padding(AnkountantSpacing.lg)
        .background(
            LinearGradient(
                colors: [palette.surfaceElevated, palette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatNumber(_ value: UInt32) -> String {
        value.formatted(.number)
    }
}

private struct ProgressRing: View {
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
            VStack(spacing: 2) {
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

private struct ProgressOverviewRow: View {
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
