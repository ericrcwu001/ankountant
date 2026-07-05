import SwiftUI

struct StatsEmptyChartView: View {
    let title: String
    let systemImage: String
    var description: String? = nil
    var height: CGFloat = 180

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        }
            .frame(height: height)
    }
}
