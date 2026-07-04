import SwiftUI

struct StatsEmptyChartView: View {
    let title: String
    let systemImage: String
    var height: CGFloat = 180

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(height: height)
    }
}
