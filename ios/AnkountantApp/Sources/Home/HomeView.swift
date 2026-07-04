// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import Foundation
import AnkountantTheme
import AnkiKit
import AnkiClients
import AnkiServices
import Dependencies
import Sharing

struct HomeView: View {
    @Binding var pendingReviewDeckId: Int64?
    @Binding var path: NavigationPath

    @Dependency(\.schedulerService) private var schedulerService
    @Dependency(\.examConfigClient) private var examConfigClient
    @Dependency(\.deckClient) private var deckClient

    @Environment(\.palette) private var palette

    @State private var examDate = Date.now
    @State private var hasExamDate = false
    @State private var sections: [SectionReadiness] = CPASection.homeOrder.map {
        SectionReadiness(section: $0, summary: nil)
    }
    @State private var readinessLoaded = false
    @State private var farDeckId: Int64?
    @State private var loadError: String?

    @Shared(.appStorage(DemoSeed.versionKey)) private var demoSeedVersion = 0

    private let section = "FAR"

    /// Home push destinations, driven programmatically by appending to `path`.
    /// The hero renders as a single `List` row (DeckListView's header), and
    /// multiple `NavigationLink`s inside one List row all activate on any tap —
    /// which pushed every FAR topic plus the drill at once and always surfaced the
    /// confusion screen. Buttons that append to the stack path hit-test per row.
    private enum HomeRoute: Hashable {
        case confusion
    }

    var body: some View {
        DeckListView(
            header: AnyView(hero),
            onAdditionalRefresh: { await load() },
            reloadID: demoSeedVersion,
            navigationTitle: ""
        )
        .task(id: demoSeedVersion) { await load() }
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .confusion:
                ConfusionDrillView(section: .far)
            }
        }
        .navigationDestination(for: CPASection.self) { section in
            SectionDetailView(section: section)
        }
        .navigationDestination(for: FarTopicCard.self) { topic in
            FarTopicDetailView(
                topic: topic,
                canStudy: farDeckId != nil,
                onStudy: startReview
            )
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            summitHero
            metricDeck
            sectionReadinessOverview
            if let farReadiness {
                ReadinessEvidencePanel(
                    evidence: readinessEvidence(band: farReadiness.band, topics: farReadiness.topics),
                    compact: true
                )
                .padding(AnkountantSpacing.md)
                .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                        .stroke(palette.borderSubtle, lineWidth: 1)
                )
            }
            examScheduleControl
            farTopicList
            actions
            if let loadError {
                AnkountantStatusMessageView(
                    title: "Home data failed",
                    message: loadError,
                    systemImage: "exclamationmark.triangle",
                    tone: .danger
                )
                .frame(maxWidth: .infinity)
                .ankountantCard(elevated: true)
            }
        }
    }

    private var sectionReadinessOverview: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            RangeHeroChart(sections: sections)
            VStack(spacing: 0) {
                ForEach(sections) { section in
                    Button {
                        path.append(section.section)
                    } label: {
                        SectionReadinessRow(section: section)
                            .padding(.horizontal, AnkountantSpacing.md)
                            .padding(.vertical, AnkountantSpacing.sm)
                    }
                    .buttonStyle(.plain)
                    if section.id != sections.last?.id {
                        Rectangle().fill(palette.borderSubtle).frame(height: 1)
                    }
                }
            }
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
        }
    }

    private var summitHero: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ankountant")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                    Text("CPA EXAM PREP")
                        .ankountantFont(.micro)
                        .foregroundStyle(Color.white.opacity(0.68))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label(heroFreshnessTitle, systemImage: heroFreshnessIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(heroFreshnessDetail)
                        .ankountantFont(.micro)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: 132, alignment: .trailing)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(heroFreshnessAccessibilityLabel)
            }

            FarTopicHeroChart(topics: farTopics)
                .frame(height: 150)
        }
        .padding(AnkountantSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.19, blue: 0.33), Color(red: 0.05, green: 0.13, blue: 0.24)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.container, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ankountant CPA exam prep readiness and FAR topic mastery")
    }

    private var metricDeck: some View {
        VStack(spacing: AnkountantSpacing.sm) {
            HStack(spacing: AnkountantSpacing.sm) {
                HomeMetricCard(value: countdownNumeral, label: countdownCaption)
                HomeMetricCard(value: coverageValue, label: coverageCaption)
            }
            ReadinessScoreStrip(scores: readinessScores)
        }
    }

    private var examScheduleControl: some View {
        HStack(spacing: AnkountantSpacing.md) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 34, height: 34)
                .background(palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Exam date")
                    .ankountantFont(.micro)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.textSecondary)
                Text(hasExamDate ? countdownCaption : "Set exam date")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            DatePicker("", selection: examDateBinding, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(AnkountantSpacing.md)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
    }

    private var farTopicList: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("FAR focus topics")
                .ankountantFont(.micro)
                .textCase(.uppercase)
                .foregroundStyle(palette.textSecondary)
            VStack(spacing: 0) {
                ForEach(farTopics.prefix(7)) { topic in
                    Button {
                        path.append(topic)
                    } label: {
                        FarTopicRow(topic: topic)
                    }
                    .buttonStyle(.plain)
                    if topic.id != farTopics.prefix(7).last?.id {
                        Rectangle().fill(palette.borderSubtle).frame(height: 1)
                    }
                }
            }
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                    .stroke(palette.borderSubtle, lineWidth: 1)
            )
        }
    }

    private var actions: some View {
        VStack(spacing: AnkountantSpacing.sm) {
            primaryCta

            Button {
                path.append(HomeRoute.confusion)
            } label: {
                Text("Practice FAR confusion sets")
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AnkountantSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                            .stroke(palette.accent, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // Recall raises the review cover via `pendingReviewDeckId` (not a push); the
    // confusion drill is a pushed destination. Both are Buttons appending to the
    // stack path — never NavigationLinks — because the hero is one List row, where
    // multiple NavigationLinks would all fire on a single tap.
    @ViewBuilder
    private var primaryCta: some View {
        let label = VStack(spacing: AnkountantSpacing.xxs) {
            Text(cta.label)
                .ankountantFont(.bodyEmphasis)
            Text(cta.subtitle)
                .ankountantFont(.caption)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity)

        switch cta.target {
        case .recall:
            Button(action: startReview) { label }
                .buttonStyle(AnkountantPrimaryButtonStyle())
                .disabled(farDeckId == nil)
        case .confusion:
            Button { path.append(HomeRoute.confusion) } label: { label }
                .buttonStyle(AnkountantPrimaryButtonStyle())
        }
    }

    private var farReadiness: ReadinessSummary? {
        sections.first(where: { $0.section == .far })?.summary
    }

    private var farTopics: [FarTopicCard] {
        FarTopicCard.build(from: farReadiness)
    }

    private var daysUntilExam: Int? {
        guard hasExamDate else { return nil }
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date())
        let to = calendar.startOfDay(for: examDate)
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    private var countdownNumeral: String {
        guard let days = daysUntilExam else { return "—" }
        return String(abs(days))
    }

    private var countdownCaption: String {
        guard let days = daysUntilExam else { return "Set exam date" }
        if days > 0 { return days == 1 ? "Day until exam" : "Days until exam" }
        if days == 0 { return "Exam day" }
        return abs(days) == 1 ? "Day since exam" : "Days since exam"
    }

    private var readinessScores: [ReadinessScoreSummary] {
        farReadiness?.scoreSummaries ?? ReadinessScoreSummary.pendingSummaries(loaded: readinessLoaded)
    }

    private var coverageValue: String {
        guard let band = farReadiness?.band else { return readinessLoaded ? "—" : "..." }
        return formatPercent(band.coverage)
    }

    private var coverageCaption: String {
        guard farReadiness?.band != nil else {
            return readinessLoaded ? "No coverage" : "Loading"
        }
        return "Coverage"
    }

    private var heroFreshnessIcon: String {
        guard readinessLoaded else { return "clock" }
        guard let band = farReadiness?.band, band.generatedAt > 0 else { return "exclamationmark.triangle" }
        return band.abstain ? "hourglass" : "clock"
    }

    private var heroFreshnessTitle: String {
        guard readinessLoaded else { return "Loading" }
        guard let band = farReadiness?.band, band.generatedAt > 0 else { return "Needs evidence" }
        return band.abstain ? "Withheld" : "Updated"
    }

    private var heroFreshnessDetail: String {
        guard readinessLoaded else { return "Readiness" }
        guard let generatedAt = farReadiness?.band.generatedAt, generatedAt > 0 else { return "Practice first" }
        let date = Date(timeIntervalSince1970: TimeInterval(generatedAt))
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var heroFreshnessAccessibilityLabel: String {
        "\(heroFreshnessTitle), \(heroFreshnessDetail)"
    }

    private var memoryReady: Bool {
        farReadiness?.topics.contains { !$0.memoryInsufficient } ?? false
    }

    private var phase: StudyPhase {
        choosePhase(daysUntilExam: daysUntilExam, memoryReady: memoryReady)
    }

    private var cta: PhaseCta { buildPhaseCta(phase) }

    private var examDateBinding: Binding<Date> {
        Binding(
            get: { examDate },
            set: { newValue in
                examDate = newValue
                hasExamDate = true
                saveExamDate(newValue)
            }
        )
    }

    private func saveExamDate(_ date: Date) {
        do {
            try examConfigClient.saveExamDate(section, Self.isoFormatter.string(from: date))
        } catch {
            loadError = "Could not save exam date: \(error.localizedDescription)"
        }
    }

    private func startReview() {
        if let farDeckId {
            pendingReviewDeckId = farDeckId
        }
    }

    private func load() async {
        loadError = nil
        do {
            if let iso = try examConfigClient.loadExamDate(section),
               !iso.isEmpty,
               let parsed = Self.isoFormatter.date(from: iso) {
                examDate = parsed
                hasExamDate = true
            } else {
                examDate = Date.now
                hasExamDate = false
            }

            let getReadiness = schedulerService.getReadiness
            for cpaSection in CPASection.homeOrder {
                let code = cpaSection.code
                let summary = try await Task.detached(priority: .userInitiated) {
                    try getReadiness(code)
                }.value
                guard !Task.isCancelled else { return }
                update(cpaSection, summary: summary)
                if cpaSection == .far { readinessLoaded = true }
            }
            readinessLoaded = true

            let fetchTree = deckClient.fetchTree
            let tree = try await Task.detached(priority: .userInitiated) {
                try fetchTree()
            }.value
            farDeckId = Self.findDeckId(in: tree, fullName: "Ankountant::Study::FAR")
        } catch {
            readinessLoaded = true
            loadError = error.localizedDescription
        }
    }

    private func update(_ cpaSection: CPASection, summary: ReadinessSummary?) {
        if let index = sections.firstIndex(where: { $0.section == cpaSection }) {
            sections[index] = SectionReadiness(section: cpaSection, summary: summary)
        }
    }

    private static func findDeckId(in nodes: [DeckTreeNode], fullName: String) -> Int64? {
        for node in nodes {
            if node.fullName == fullName { return node.id }
            if let found = findDeckId(in: node.children, fullName: fullName) { return found }
        }
        return nil
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

}

private struct HomeMetricCard: View {
    let value: String
    let label: String
    var gauge: Double?

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: AnkountantSpacing.sm) {
            Text(value)
                .ankountantFont(.sectionHeading)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AnkountantSpacing.sm)
            if let gauge {
                MiniGauge(fraction: gauge)
                    .frame(width: 40, height: 40)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(AnkountantSpacing.md)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
    }
}

private struct MiniGauge: View {
    let fraction: Double
    @Environment(\.palette) private var palette

    private let lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.surfaceInset, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

private struct FarTopicRow: View {
    let topic: FarTopicCard
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: AnkountantSpacing.md) {
            FarTopicSparkline(topic: topic)
                .frame(width: 46, height: 28)
            Text(topic.label)
                .ankountantFont(.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(topic.scoreLabel)
                .ankountantFont(.captionBold)
                .monospacedDigit()
                .foregroundStyle(topic.isUnproven ? palette.textTertiary : palette.textPrimary)
        }
        .padding(.horizontal, AnkountantSpacing.md)
        .padding(.vertical, AnkountantSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(topic.accessibilityLabel)
    }
}

private struct FarTopicDetailView: View {
    let topic: FarTopicCard
    let canStudy: Bool
    let onStudy: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
                FarTopicPeakCard(topic: topic)
                metricPanel
                chipPanel
                Button(action: onStudy) {
                    Label("Study \(topic.label)", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AnkountantPrimaryButtonStyle())
                .disabled(!canStudy)
                NavigationLink(value: CPASection.far) {
                    Label("View FAR readiness", systemImage: "chart.line.uptrend.xyaxis")
                        .ankountantFont(.bodyEmphasis)
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AnkountantSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                                .stroke(palette.accent, lineWidth: 1)
                        )
                }
            }
            .padding(AnkountantSpacing.lg)
        }
        .ankountantSectionBackground()
        .navigationTitle(topic.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metricPanel: some View {
        VStack(spacing: AnkountantSpacing.sm) {
            metric("Memory", value: topic.memory, detail: topic.memoryRange)
            metric("Performance", value: topic.performance, detail: topic.performanceRange)
            metric("Gap", value: topic.gap, detail: "")
        }
        .ankountantCard(elevated: true)
    }

    private var chipPanel: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("Confusion sets")
                .ankountantFont(.micro)
                .textCase(.uppercase)
                .foregroundStyle(palette.textSecondary)
            FlowLayout(items: topic.tokens) { token in
                Text(token)
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(palette.surfaceInset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.borderSubtle, lineWidth: 1)
                    )
            }
        }
        .ankountantCard(elevated: true)
    }

    private func metric(_ label: String, value: Int?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(value.map { "\($0)%" } ?? "insufficient")
                    .ankountantFont(.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
            }
            if !detail.isEmpty {
                Text(detail)
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            PositionMeter(fraction: value.map { Double($0) / 100 })
        }
    }
}

private struct FarTopicPeakCard: View {
    let topic: FarTopicCard
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            HStack {
                Text(topic.label)
                    .ankountantFont(.sectionHeading)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "bookmark")
                    .foregroundStyle(palette.textSecondary)
            }
            FarSinglePeakChart(topic: topic)
                .frame(height: 180)
        }
        .ankountantCard(elevated: true)
    }
}

private struct FarTopicHeroChart: View {
    let topics: [FarTopicCard]
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let front = Array(topics.prefix(7))
            ZStack(alignment: .topLeading) {
                MountainRangeCanvas(topics: front)
                passLine(size)
                ForEach(front) { topic in
                    let point = topic.point(in: size)
                    VStack(spacing: 1) {
                        Text(topic.shortLabel)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.86))
                        Text(topic.scoreLabel)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.86))
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(topic.isBelow ? Color.orange : Color.white)
                    }
                    .position(x: point.x, y: max(12, point.y - 30))
                }
            }
        }
    }

    private func passLine(_ size: CGSize) -> some View {
        Path { path in
            let y = size.height * 0.56
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

private struct MountainRangeCanvas: View {
    let topics: [FarTopicCard]

    var body: some View {
        Canvas { context, size in
            let base = size.height * 0.93
            let plot = size.height * 0.72
            var far = Path()
            far.move(to: CGPoint(x: 0, y: base))
            for index in 0...80 {
                let t = Double(index) / 80
                let x = t * size.width
                let y = base - (0.12 + 0.08 * sin(t * .pi * 3)) * plot
                far.addLine(to: CGPoint(x: x, y: y))
            }
            far.addLine(to: CGPoint(x: size.width, y: base))
            far.closeSubpath()
            context.fill(far, with: .color(Color.white.opacity(0.18)))

            for topic in topics {
                let x = topic.cx * size.width
                let peak = base - topic.height * plot
                var path = Path()
                path.move(to: CGPoint(x: max(0, x - 54), y: base))
                path.addLine(to: CGPoint(x: x, y: peak))
                path.addLine(to: CGPoint(x: min(size.width, x + 60), y: base))
                path.closeSubpath()
                context.fill(path, with: .color(Color.white.opacity(topic.isUnproven ? 0.2 : 0.34)))
                context.stroke(path, with: .color(Color.white.opacity(0.36)), lineWidth: 1)
            }
        }
    }
}

private struct FarSinglePeakChart: View {
    let topic: FarTopicCard
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                MountainRangeCanvas(topics: [topic])
                Path { path in
                    let y = size.height * 0.52
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(palette.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Text("PASS LINE · 75")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.accent)
                    .position(x: size.width - 50, y: size.height * 0.52 - 12)
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        }
    }
}

private struct FarTopicSparkline: View {
    let topic: FarTopicCard
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let base = size.height - 2
            let peak = base - size.height * 0.72
            Path { path in
                path.move(to: CGPoint(x: 1, y: base))
                path.addLine(to: CGPoint(x: size.width * 0.52, y: peak))
                path.addLine(to: CGPoint(x: size.width - 1, y: base))
                path.closeSubpath()
            }
            .fill(palette.accent.opacity(topic.isUnproven ? 0.1 : 0.18))
            Path { path in
                path.move(to: CGPoint(x: 1, y: base))
                path.addLine(to: CGPoint(x: size.width * 0.52, y: peak))
                path.addLine(to: CGPoint(x: size.width - 1, y: base))
            }
            .stroke(palette.accent.opacity(0.6), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct PositionMeter: View {
    let fraction: Double?
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceInset)
                if let fraction {
                    Capsule()
                        .fill(palette.accent.opacity(0.75))
                        .frame(width: max(2, min(max(fraction, 0), 1) * geo.size.width))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    init(items: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
            }
        }
    }
}

private struct FarTopicCard: Identifiable, Hashable {
    let id: String
    let setId: String
    let label: String
    let cx: Double
    let height: Double
    let memory: Int?
    let performance: Int?
    let gap: Int?
    let memoryRange: String
    let performanceRange: String
    let isUnproven: Bool

    var scoreLabel: String { performance.map(String.init) ?? "—" }
    var isBelow: Bool { performance.map { $0 < 75 } ?? false }
    var shortLabel: String { label.replacingOccurrences(of: " & ", with: "\n") }

    var tokens: [String] {
        setId
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    var accessibilityLabel: String {
        if isUnproven { return "\(label), not enough data yet" }
        return "\(label), performance \(scoreLabel) percent"
    }

    func point(in size: CGSize) -> CGPoint {
        let base = size.height * 0.93
        let plot = size.height * 0.72
        return CGPoint(x: cx * size.width, y: base - height * plot)
    }

    static func build(from summary: ReadinessSummary?) -> [FarTopicCard] {
        let byId = Dictionary(uniqueKeysWithValues: (summary?.topics ?? []).map { ($0.setId, $0) })
        return specs.map { spec in
            make(spec: spec, topic: byId[spec.setId])
        }
    }

    private static func make(spec: Spec, topic: TopicScoreModel?) -> FarTopicCard {
        let missingPerformance = topic == nil
            || (topic?.performance == 0 && topic?.performanceLow == 0 && topic?.performanceHigh == 0)
        let performance = topic.flatMap { missingPerformance ? nil : pct($0.performance) }
        let memory = topic.flatMap { $0.memoryInsufficient ? nil : pct($0.memory) }
        let gap = topic.flatMap { t in
            memory == nil || performance == nil ? nil : pct(t.gap)
        }
        return FarTopicCard(
            id: spec.setId,
            setId: spec.setId,
            label: spec.label,
            cx: spec.cx,
            height: spec.height,
            memory: memory,
            performance: performance,
            gap: gap,
            memoryRange: topic.flatMap { $0.memoryInsufficient ? nil : range($0.memoryLow, $0.memoryHigh) } ?? "",
            performanceRange: topic.flatMap { missingPerformance ? nil : range($0.performanceLow, $0.performanceHigh) } ?? "",
            isUnproven: performance == nil
        )
    }

    private static func pct(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    private static func range(_ low: Double, _ high: Double) -> String {
        let lo = pct(low)
        let hi = pct(high)
        return hi > lo ? "\(lo)-\(hi)%" : ""
    }

    private struct Spec {
        let setId: String
        let label: String
        let cx: Double
        let height: Double
    }

    private static let specs = [
        Spec(setId: "operating_vs_finance_lease", label: "Leases", cx: 0.12, height: 0.88),
        Spec(setId: "revrec_step_selection", label: "Revenue", cx: 0.27, height: 0.92),
        Spec(setId: "capitalize_vs_expense", label: "PP&E", cx: 0.42, height: 0.87),
        Spec(setId: "inventory_valuation", label: "Inventory", cx: 0.56, height: 0.78),
        Spec(setId: "trading_afs_htm", label: "Investments", cx: 0.69, height: 0.85),
        Spec(setId: "tax_timing", label: "Taxes", cx: 0.82, height: 0.75),
        Spec(setId: "debt_extinguishment", label: "Debt", cx: 0.94, height: 0.68),
    ]
}
