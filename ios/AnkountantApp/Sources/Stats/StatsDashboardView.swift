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
                .font(.caption)
            Text(label)
                .ankountantFont(.captionBold)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(palette.surfaceElevated)
        .overlay {
            Capsule().stroke(palette.borderSubtle, lineWidth: 1)
        }
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
        RetentionChart(trueRetention: graphs.trueRetention)
        StudyHealthCard(graphs: graphs)
        HeatmapChartOptimized(reviews: graphs.reviews)
        ReviewsChart(reviews: graphs.reviews, period: period)
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
