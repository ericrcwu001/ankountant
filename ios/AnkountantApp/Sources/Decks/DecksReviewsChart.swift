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
                Text(errorMessage ?? "No reviews yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 200)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let data = try statsClient.fetchGraphs("", UInt32(days))
            let response = try Anki_Stats_GraphsResponse(serializedBytes: data)
            reviews = response.reviews
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            reviews = nil
        }
        isLoading = false
    }
}
