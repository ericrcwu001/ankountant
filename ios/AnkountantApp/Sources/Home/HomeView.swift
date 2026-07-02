import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import AnkiServices
import Dependencies

/// The Ankountant Home hub — the Decks tab root. Its hero widget is a
/// days-until-exam countdown fed by a user-entered exam date; saving that date
/// (via `ExamConfigClient` → the shared `ankountant.<section>.exam.date` config)
/// is what makes the live scheduler deadline-anchored (A1-live). The hero also
/// surfaces Readiness and a "Start review" entry, then the existing deck list
/// scrolls beneath it.
struct HomeView: View {
    @Binding var pendingReviewDeckId: Int64?

    @Dependency(\.schedulerService) private var schedulerService
    @Dependency(\.examConfigClient) private var examConfigClient
    @Dependency(\.deckClient) private var deckClient

    @Environment(\.palette) private var palette

    @State private var examDate = Date()
    @State private var hasExamDate = false
    @State private var readiness: ReadinessSummary?
    @State private var readinessLoaded = false
    @State private var farDeckId: Int64?
    @State private var showConfusion = false

    private let section = "FAR"

    var body: some View {
        DeckListView(header: AnyView(hero), navigationTitle: "Home")
            .task { await load() }
            .navigationDestination(isPresented: $showConfusion) {
                ConfusionDrillView()
            }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            countdownCard
            readinessCard
            topicsCard
            actions
        }
    }

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AnkountantSpacing.sm) {
                // The countdown is the display hero — neutral ink + tabular
                // digits, never the brand navy (which is chrome-only).
                Text(countdownNumeral)
                    .ankountantFont(.displayHero)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text(countdownCaption)
                    .ankountantFont(.callout)
                    .foregroundStyle(palette.textSecondary)
            }
            DatePicker(
                "Exam date",
                selection: examDateBinding,
                displayedComponents: [.date]
            )
            .tint(palette.accent)
            .ankountantFont(.body)
            .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ankountantCard(elevated: true)
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("Exam-day projection")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            if let readiness {
                if readiness.band.abstain {
                    abstain(reason: readiness.band.reason)
                    Text("\(pct(readiness.band.coverage)) of exam topics covered")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: AnkountantSpacing.sm) {
                        Text(bandLabel(readiness.band))
                            .ankountantFont(.sectionHeading)
                            .foregroundStyle(palette.accent)
                            .monospacedDigit()
                        Text("point \(Int(readiness.band.pointEstimate.rounded()))")
                            .ankountantFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }
                    Text("\(readiness.band.confidence) confidence · \(pct(readiness.band.coverage)) of exam covered")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                    // Factual drivers (restated numbers, never a claimed cause).
                    ForEach(readiness.band.reasons.prefix(3), id: \.self) { reason in
                        Text("• \(reason)")
                            .ankountantFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text("Rough CPA 0–99 projection (pass 75) — not an official score.\(updatedSuffix(readiness.band.generatedAt))")
                        .ankountantFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: AnkountantSpacing.xl) {
                        quickStat("\(readiness.topics.count)", "Topics")
                        quickStat("\(gapsToClose(readiness))", "Gaps to close")
                    }
                    .padding(.top, AnkountantSpacing.xs)
                }
            } else if readinessLoaded {
                // Loaded, but no projection is available (no data yet, or the
                // readiness call failed) — show the abstain state rather than
                // spinning forever.
                abstain(reason: "complete a few reviews to project a score")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ankountantCard(elevated: true)
    }

    /// Per-topic Memory vs Performance, each with its confidence range (#3).
    @ViewBuilder
    private var topicsCard: some View {
        if let readiness, !readiness.band.abstain, !readiness.topics.isEmpty {
            VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
                Text("Topic breakdown")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textSecondary)
                    .textCase(.uppercase)
                ForEach(readiness.topics) { topic in
                    HStack(alignment: .firstTextBaseline) {
                        Text(topic.setId.replacingOccurrences(of: "_", with: " "))
                            .ankountantFont(.caption)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("M \(scoreWithRange(topic.memoryInsufficient ? nil : topic.memory, topic.memoryLow, topic.memoryHigh))")
                            Text("P \(scoreWithRange(topic.performance, topic.performanceLow, topic.performanceHigh))")
                        }
                        .ankountantFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ankountantCard(elevated: true)
        }
    }

    private var actions: some View {
        VStack(spacing: AnkountantSpacing.sm) {
            // The primary action is phase-aware: its label, subtitle, and target
            // follow the days-to-exam + memory-base recommendation (see
            // `choosePhase`). Recall opens the FAR study deck; discrimination
            // opens the confusion drill.
            Button(action: runCta) {
                VStack(spacing: AnkountantSpacing.xxs) {
                    Text(cta.label)
                        .ankountantFont(.bodyEmphasis)
                    Text(cta.subtitle)
                        .ankountantFont(.caption)
                        .opacity(0.85)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AnkountantPrimaryButtonStyle())
            .disabled(cta.target == .recall && farDeckId == nil)

            NavigationLink {
                StatsDashboardView()
            } label: {
                Text("View stats")
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
    }

    @ViewBuilder
    private func abstain(reason: String) -> some View {
        HStack(alignment: .top, spacing: AnkountantSpacing.sm) {
            Image(systemName: "square.dashed")
                .foregroundStyle(palette.textSecondary)
            VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
                Text("Not enough data yet")
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Text("\(reason).")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func quickStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
            Text(value)
                .ankountantFont(.cardTitle)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Derived

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
        guard let days = daysUntilExam else { return "Set your exam date" }
        if days > 0 { return days == 1 ? "day until exam" : "days until exam" }
        if days == 0 { return "Exam day — good luck" }
        return abs(days) == 1 ? "day since exam" : "days since exam"
    }

    // CPA scaled-score band (0-99), not a percentage (ADR 0005).
    private func bandLabel(_ band: ReadinessBand) -> String {
        "\(Int(band.bandLow.rounded()))–\(Int(band.bandHigh.rounded()))"
    }

    private func gapsToClose(_ summary: ReadinessSummary) -> Int {
        summary.topics.filter { $0.gap >= 0.25 }.count
    }

    /// A 0..1 fraction as an integer percent string ("62%").
    private func pct(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// A point score plus its confidence range ("62% (54–70%)"), or
    /// "insufficient" when the metric has no reliable value.
    private func scoreWithRange(_ value: Double?, _ low: Double, _ high: Double) -> String {
        guard let value else { return "insufficient" }
        let lo = Int((low * 100).rounded())
        let hi = Int((high * 100).rounded())
        if hi > lo {
            return "\(Int((value * 100).rounded()))% (\(lo)–\(hi)%)"
        }
        return "\(Int((value * 100).rounded()))%"
    }

    /// " · updated 3:04 PM" suffix from unix seconds, empty when unknown.
    private func updatedSuffix(_ generatedAt: Int64) -> String {
        guard generatedAt > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(generatedAt))
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return " · updated \(formatter.string(from: date))"
    }

    // MARK: Phase-aware CTA

    /// A memory base exists once at least one topic has enough in-window recall
    /// reps (i.e. is not memory-insufficient). No base => beginner => foundation.
    private var memoryReady: Bool {
        guard let readiness else { return false }
        return readiness.topics.contains { !$0.memoryInsufficient }
    }

    private var phase: StudyPhase {
        choosePhase(daysUntilExam: daysUntilExam, memoryReady: memoryReady)
    }

    private var cta: PhaseCta { buildPhaseCta(phase) }

    private func runCta() {
        switch cta.target {
        case .recall: startReview()
        case .confusion: showConfusion = true
        }
    }

    // MARK: Actions

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
            print("[HomeView] failed to save exam date: \(error)")
        }
    }

    private func startReview() {
        if let farDeckId {
            pendingReviewDeckId = farDeckId
        }
    }

    private func load() async {
        if let iso = try? examConfigClient.loadExamDate(section),
           let parsed = Self.isoFormatter.date(from: iso) {
            examDate = parsed
            hasExamDate = true
        }
        readiness = try? schedulerService.getReadiness(section)
        readinessLoaded = true
        if let tree = try? deckClient.fetchTree() {
            farDeckId = Self.findDeckId(in: tree, fullName: "Ankountant::Study::FAR")
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
