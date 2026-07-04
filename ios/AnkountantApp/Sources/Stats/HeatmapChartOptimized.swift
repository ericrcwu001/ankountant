import SwiftUI
import AnkountantTheme
import AnkiProto

/// Reviews contribution heatmap.
/// - Defaults to showing the last 6 months.
/// - The "Last …" range menu **rescales** the grid to fit the whole selected
///   window into the card width: shorter ranges render larger cells, longer
///   ranges render denser cells. (Previously the cell size was fixed and the
///   grid scrolled, so every range showed the same trailing weeks at the same
///   scale — "6 months" looked identical to "2 years".)
struct HeatmapChartOptimized: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes

    @Environment(\.palette) private var palette
    @State private var loadingManager: HeatmapLoadingManager?
    @State private var selectedDateRange: Int = 180

    // Snapshotted from actor after each mutation. Other derived values are
    // computed from this dictionary inline (cheap sync transforms).
    @State private var visibleData: [Int: Int] = [:]
    @State private var maxCount: Int = 1
    @State private var totalReviews: Int = 0

    /// Measured width of the grid viewport, used to size cells so the entire
    /// selected range fits on screen (non-compact only).
    @State private var gridWidth: CGFloat = 0

    var compactHeight: CGFloat? = nil

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private var isCompact: Bool {
        compactHeight != nil
    }

    private var weekdayLabelWidth: CGFloat {
        isCompact ? 16 : 22
    }

    /// Number of week-columns needed to cover the selected range.
    private var columnCount: Int {
        max(4, (selectedDateRange + 7) / 7 + 1)
    }

    /// Past ~9 months the grid is too dense for per-row weekday / per-column
    /// month labels to be legible, so they're dropped (the extra width goes to
    /// the cells instead).
    private var isDense: Bool {
        !isCompact && columnCount > 40
    }

    // MARK: - Derived Computed Properties (sync, over snapshot)

    private var currentStreak: Int {
        var streak = 0
        var offset = 0
        if visibleData[0] == nil || visibleData[0] == 0 {
            offset = -1
        }
        while let count = visibleData[offset], count > 0 {
            streak += 1
            offset -= 1
        }
        return streak
    }

    private var reviewsThisWeek: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let weekday = Calendar.current.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        return (0...daysFromMonday).reduce(0) { $0 + (visibleData[-$1] ?? 0) }
    }

    private var reviewsThisMonth: Int {
        let day = Calendar.current.component(.day, from: Date())
        return (0..<day).reduce(0) { $0 + (visibleData[-$1] ?? 0) }
    }

    // MARK: - Grid Model

    /// Precomputed grid geometry. Cell offsets are derived with integer math
    /// (`offset(column:day:)`) instead of a `Calendar` lookup per cell, so
    /// rescaling to a long range no longer freezes the main thread.
    private struct HeatmapGrid {
        let columns: Int
        /// Weekday index of "today" with Monday = 0 … Sunday = 6.
        let todayIndex: Int
        let cellSize: CGFloat
        let cellSpacing: CGFloat
        let labelWidth: CGFloat
        let showsSideLabels: Bool
        let monthLabels: [(label: String, column: Int)]

        /// Day offset for a cell: 0 = today, negative = past, positive = future.
        /// The rightmost column is the current week.
        func offset(column: Int, day: Int) -> Int {
            (column - (columns - 1)) * 7 + (day - todayIndex)
        }
    }

    private func makeGrid() -> HeatmapGrid {
        let columns = columnCount
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayIndex = (calendar.component(.weekday, from: today) + 5) % 7

        let dense = isDense
        let spacing: CGFloat = isCompact ? 1.25 : (columns > 52 ? 1 : 2)
        let labelWidth: CGFloat = (isCompact || !dense) ? weekdayLabelWidth : 0
        let size = cellSize(columns: columns, spacing: spacing, labelWidth: labelWidth)

        var monthLabels: [(label: String, column: Int)] = []
        if !dense {
            var lastMonth = -1
            for column in 0..<columns {
                let mondayOffset = (column - (columns - 1)) * 7 - todayIndex
                guard let date = calendar.date(byAdding: .day, value: mondayOffset, to: today) else { continue }
                let month = calendar.component(.month, from: date)
                if month != lastMonth {
                    monthLabels.append((Self.monthFormatter.string(from: date), column))
                    lastMonth = month
                }
            }
        }

        return HeatmapGrid(
            columns: columns,
            todayIndex: todayIndex,
            cellSize: size,
            cellSpacing: spacing,
            labelWidth: labelWidth,
            showsSideLabels: isCompact || !dense,
            monthLabels: monthLabels
        )
    }

    /// Cell edge length. In compact mode it's driven by the available height;
    /// otherwise it's sized so `columns` week-columns fill the measured width.
    private func cellSize(columns: Int, spacing: CGFloat, labelWidth: CGFloat) -> CGFloat {
        if let compactHeight {
            let reservedHeight: CGFloat = 92
            let availableGridHeight = max(56, compactHeight - reservedHeight)
            return min(12, max(7, (availableGridHeight - (spacing * 6)) / 7))
        }
        guard gridWidth > 0 else { return 12 }
        let available = gridWidth - labelWidth
        let perColumn = available / CGFloat(max(columns, 1))
        return min(16, max(1.5, perColumn - spacing))
    }

    // MARK: - Body

    var body: some View {
        let grid = makeGrid()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reviews")
                    .ankountantFont(.sectionHeading)
                    .foregroundStyle(palette.textPrimary)
                Spacer()

                if !isCompact {
                    Menu {
                        ForEach([30, 90, 180, 365, 730], id: \.self) { days in
                            Button(dateRangeLabel(days)) {
                                Task { await updateDateRange(days) }
                            }
                        }
                    } label: {
                        Label(dateRangeLabel(selectedDateRange), systemImage: "line.horizontal.3.decrease.circle")
                            .ankountantFont(.caption)
                            .foregroundStyle(palette.accent)
                    }
                }

                if currentStreak > 0 {
                    Label("\(currentStreak)-day streak", systemImage: "flame.fill")
                        .ankountantFont(.captionBold)
                        .foregroundStyle(.orange)
                }
            }

            if visibleData.isEmpty {
                Text("No reviews yet")
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 72 : 100)
            } else {
                if !isCompact {
                    HStack(spacing: 16) {
                        summaryItem(value: "\(totalReviews)", label: "Total")
                        summaryItem(value: "\(reviewsThisMonth)", label: "This month")
                        summaryItem(value: "\(reviewsThisWeek)", label: "This week")
                        summaryItem(value: "\(visibleData[0] ?? 0)", label: "Today")
                    }
                }

                if isCompact {
                    // Compact widgets keep the fixed-size + horizontal pan layout.
                    ScrollView(.horizontal, showsIndicators: false) {
                        gridStack(grid)
                    }
                    .defaultScrollAnchor(.trailing)
                } else {
                    // Full card: fit the whole selected range to the width
                    // (oldest → newest, left → right). Render only once the
                    // width is known so a long range doesn't lay out oversized
                    // for a frame at the fallback cell size.
                    Group {
                        if gridWidth > 0 {
                            gridStack(grid)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Color.clear.frame(height: 110)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        if abs(width - gridWidth) > 0.5 { gridWidth = width }
                    }
                }

                legendView(grid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 10 : 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
        .task {
            await initializeLoadingManager()
            await refreshFromManager()
        }
    }

    // MARK: - View Components

    private func gridStack(_ grid: HeatmapGrid) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !grid.monthLabels.isEmpty {
                monthHeaderView(grid)
            }
            gridView(grid)
        }
    }

    private func monthHeaderView(_ grid: HeatmapGrid) -> some View {
        HStack(spacing: 0) {
            if grid.showsSideLabels {
                Spacer().frame(width: grid.labelWidth)
            }
            ForEach(0..<grid.columns, id: \.self) { column in
                if let label = grid.monthLabels.first(where: { $0.column == column }) {
                    Text(label.label)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize()
                        .frame(width: grid.cellSize + grid.cellSpacing, alignment: .leading)
                } else {
                    Spacer().frame(width: grid.cellSize + grid.cellSpacing)
                }
            }
        }
        .frame(height: 14)
    }

    private func gridView(_ grid: HeatmapGrid) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if grid.showsSideLabels {
                VStack(spacing: grid.cellSpacing) {
                    ForEach(0..<7, id: \.self) { day in
                        Text(weekdayLabel(day))
                            .font(.system(size: 8))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: grid.labelWidth, height: grid.cellSize)
                    }
                }
            }

            HStack(spacing: grid.cellSpacing) {
                ForEach(0..<grid.columns, id: \.self) { column in
                    VStack(spacing: grid.cellSpacing) {
                        ForEach(0..<7, id: \.self) { day in
                            let offset = grid.offset(column: column, day: day)
                            let count = visibleData[offset] ?? 0

                            RoundedRectangle(cornerRadius: grid.cellSize > 4 ? 2 : 1)
                                .fill(offset > 0 ? Color.clear : heatColor(count: count))
                                .frame(width: grid.cellSize, height: grid.cellSize)
                        }
                    }
                }
            }
        }
    }

    private func legendView(_ grid: HeatmapGrid) -> some View {
        let swatch: CGFloat = isCompact ? 8 : 10
        return HStack(spacing: isCompact ? 3 : 4) {
            Spacer()
            Text("Less").ankountantFont(.micro).foregroundStyle(palette.textSecondary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green.opacity(max(0.1, intensity)))
                    .frame(width: swatch, height: swatch)
            }
            Text("More").ankountantFont(.micro).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Helpers

    private func summaryItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func weekdayLabel(_ index: Int) -> String {
        switch index {
        case 1: "M"
        case 3: "W"
        case 5: "F"
        default: ""
        }
    }

    private func heatColor(count: Int) -> Color {
        if count == 0 { return Color(.systemGray6) }
        let intensity = min(1.0, Double(count) / Double(max(maxCount, 1)))
        return .green.opacity(max(0.2, intensity))
    }

    private func dateRangeLabel(_ days: Int) -> String {
        switch days {
        case 30: return "Last 30 days"
        case 90: return "Last 90 days"
        case 180: return "Last 6 months"
        case 365: return "Last 1 year"
        case 730: return "Last 2 years"
        default: return "\(days) days"
        }
    }

    // MARK: - Async Snapshot Helper

    /// Reads the actor's current visible data and snapshots it into @State.
    /// Called on the @MainActor (view) after every actor mutation.
    private func refreshFromManager() async {
        guard let manager = loadingManager else { return }
        let snapshot = await manager.getVisibleData()
        var nextVisible: [Int: Int] = [:]
        var nextTotal = 0
        var nextMax = 1
        for (offset, review) in snapshot {
            nextVisible[offset] = review.total
            nextTotal += review.total
            nextMax = Swift.max(nextMax, review.total)
        }
        visibleData = nextVisible
        totalReviews = nextTotal
        maxCount = nextMax
    }

    // MARK: - State Management

    private func initializeLoadingManager() async {
        let manager = HeatmapLoadingManager(defaultVisibleDays: selectedDateRange)
        await manager.loadAllData(reviews)
        await manager.setDateRange(days: selectedDateRange)
        self.loadingManager = manager
    }

    private func updateDateRange(_ days: Int) async {
        selectedDateRange = days
        guard let manager = loadingManager else { return }
        await manager.setDateRange(days: days)
        await refreshFromManager()
    }
}
