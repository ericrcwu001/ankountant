// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import AnkiServices
import Dependencies
import Sharing

/// The Ankountant Home hub — the Decks tab root. The hero stacks a days-until-exam
/// countdown, the FAR readiness Wilson band (the headline), a topographic "range"
/// across the CPA sections, and a per-section list; the deck list scrolls beneath.
/// Tapping a section peak/row drills into its per-topic Memory/Performance
/// breakdown. Saving the exam date (via `ExamConfigClient`) is what makes the live
/// scheduler deadline-anchored (A1-live). Styled with the Ledger tokens: navy is
/// chrome-only + the readiness band; numerals are neutral ink + tabular figures;
/// abstain ("Not enough data yet") is first-class.
struct HomeView: View {
    @Binding var pendingReviewDeckId: Int64?

    @Dependency(\.schedulerService) private var schedulerService
    @Dependency(\.examConfigClient) private var examConfigClient
    @Dependency(\.deckClient) private var deckClient

    @Environment(\.palette) private var palette

    @State private var examDate = Date()
    @State private var hasExamDate = false
    // One entry per summit section (FAR first); nil summary until loaded / on error.
    @State private var sections: [SectionReadiness] = CPASection.homeOrder.map {
        SectionReadiness(section: $0, summary: nil)
    }
    @State private var readinessLoaded = false
    @State private var farDeckId: Int64?
    @State private var showConfusion = false

    // Bumped by the Debug "demo phases" actions after they reseed. Observed via
    // .task(id:) below so Home reloads when the demo profile changes.
    @Shared(.appStorage(DemoSeed.versionKey)) private var demoSeedVersion = 0

    // The focus section: FAR drives the countdown, headline readiness, and CTA.
    private let section = "FAR"

    var body: some View {
        DeckListView(
            header: AnyView(hero),
            onAdditionalRefresh: { await load() },
            reloadID: demoSeedVersion,
            navigationTitle: "Home"
        )
        .task(id: demoSeedVersion) { await load() }
        .navigationDestination(isPresented: $showConfusion) {
            ConfusionDrillView()
        }
        .navigationDestination(for: CPASection.self) { tapped in
            SectionDetailView(section: tapped)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            countdownCard
            readinessCard
            RangeHeroChart(sections: sections)
            sectionList
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

    // Headline: the FAR exam-day projection (Constraint 3). Abstain-aware.
    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("FAR · Exam-day projection")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            if let far = farReadiness {
                ReadinessBandView(band: far.band)
                if !far.band.abstain {
                    HStack(spacing: AnkountantSpacing.xl) {
                        quickStat("\(far.topics.count)", "FAR topics")
                        quickStat("\(far.gapsToCloseCount)", "Gaps to close")
                    }
                    .padding(.top, AnkountantSpacing.xs)
                }
            } else if readinessLoaded {
                AbstainView(reason: "complete a few reviews to project a score")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ankountantCard(elevated: true)
    }

    // One tappable row per section, sharing the CPASection navigation destination
    // with the range peaks above.
    private var sectionList: some View {
        VStack(spacing: AnkountantSpacing.sm) {
            ForEach(sections) { readiness in
                NavigationLink(value: readiness.section) {
                    SectionReadinessRow(section: readiness)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ankountantCard(elevated: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: AnkountantSpacing.sm) {
            // Phase-aware primary CTA: recall opens the FAR study deck; the
            // discrimination phase opens the confusion drill.
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

    private var farReadiness: ReadinessSummary? {
        sections.first(where: { $0.section == .far })?.summary
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
        guard let days = daysUntilExam else { return "Set your exam date" }
        if days > 0 { return days == 1 ? "day until exam" : "days until exam" }
        if days == 0 { return "Exam day — good luck" }
        return abs(days) == 1 ? "day since exam" : "days since exam"
    }

    // MARK: Phase-aware CTA

    /// A memory base exists once at least one FAR topic has enough in-window
    /// recall reps (i.e. is not memory-insufficient).
    private var memoryReady: Bool {
        farReadiness?.topics.contains { !$0.memoryInsufficient } ?? false
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
        // Exam date (FAR) — cheap config read. An empty stored string counts as
        // "no date" (foundation phase).
        if let iso = try? examConfigClient.loadExamDate(section),
           !iso.isEmpty,
           let parsed = Self.isoFormatter.date(from: iso) {
            examDate = parsed
            hasExamDate = true
        } else {
            examDate = Date()
            hasExamDate = false
        }

        // Readiness for all summit sections, off the main actor. The backend
        // serializes FFI under a lock, so a sequential loop is correct and
        // simplest (a task group buys no real parallelism). FAR is first in
        // homeOrder, so the headline paints before the rest fill in.
        let getReadiness = schedulerService.getReadiness
        for cpaSection in CPASection.homeOrder {
            let code = cpaSection.code
            let summary = await Task.detached(priority: .userInitiated) {
                try? getReadiness(code)
            }.value
            guard !Task.isCancelled else { return }
            update(cpaSection, summary: summary)
            if cpaSection == .far { readinessLoaded = true }
        }
        readinessLoaded = true

        // FAR study deck id for the recall CTA — also off the main actor.
        let fetchTree = deckClient.fetchTree
        farDeckId = await Task.detached(priority: .userInitiated) {
            (try? fetchTree()).flatMap {
                Self.findDeckId(in: $0, fullName: "Ankountant::Study::FAR")
            }
        }.value
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
