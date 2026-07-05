import AnkountantTheme
import AnkiClients
import AnkiProto
import Dependencies
import SwiftProtobuf
import SwiftUI

/// Reviews heatmap shown above the deck list on Home. Reuses the same
/// `HeatmapChartOptimized` component the Stats dashboard renders.
///
/// Loads `Anki_Stats_GraphsResponse` once on appear. The window is fetched
/// wide enough to back the heatmap's largest in-widget "Last …" range so that
/// selecting a longer range actually reveals more history (the menu filters
/// this data client-side rather than re-fetching).
struct DecksReviewsChart: View {
    var days: Int = 730

    @Dependency(\.statsClient) private var statsClient
    @State private var reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 200)
            } else if let reviews {
                // Full-size heatmap — same call shape as StatsDashboardView
                // so the visual matches what the Stats tab renders.
                HeatmapChartOptimized(reviews: reviews)
            } else {
                StatsEmptyChartView(
                    title: errorMessage == nil ? "No reviews yet" : "Couldn't load reviews",
                    systemImage: errorMessage == nil ? "calendar" : "exclamationmark.triangle",
                    description: errorMessage ?? "Review cards to build your study heatmap.",
                    height: 200
                )
            }
        }
        .task { await load() }
    }

    private func load() async {
        // Off the main actor: fetchGraphs is a synchronous FFI call and decoding
        // the (2-year) response is CPU-heavy — running either on @MainActor hitches
        // the Home screen. Capture the @Sendable closure first so swift-dependencies
        // overrides survive the hop.
        let fetch = statsClient.fetchGraphs
        let days = UInt32(days)
        do {
            let response = try await Task.detached(priority: .userInitiated) {
                let data = try fetch("", days)
                return try Anki_Stats_GraphsResponse(serializedBytes: data)
            }.value
            guard !Task.isCancelled else { return }
            reviews = response.reviews
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            reviews = nil
        }
        isLoading = false
    }
}
