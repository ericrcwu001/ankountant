import SwiftUI
import AnkiKit
import AnkiClients
import Dependencies
import AnkountantTheme

/// B3 confusion-set drill (mirrors the desktop
/// ts/routes/(ankountant)/ankountant-confusion/ConfusionMode.svelte). Plays the
/// interleaved, label-stripped queue: per item it runs the B1 confidence gate,
/// then the which-treatment gate, submits the choice via SubmitPerformanceAttempt
/// (grading is authoritative on the Rust side), shows a verdict, and advances.
/// A finished card is shown once the queue is exhausted.
struct ConfusionDrillView: View {
    private let section: CPASection?

    @Dependency(\.performanceClient) var performanceClient
    @Environment(\.palette) private var palette

    @State private var items: [ConfusionItemModel] = []
    @State private var index: Int = 0
    @State private var confidence: ConfidenceLevel? = nil
    @State private var itemStartedAt = Date.now
    @State private var lastCorrect: Bool? = nil
    @State private var reveal: ConfusionRevealModel?
    @State private var submitError: String?
    @State private var revealError: String?
    @State private var submitting = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    private var done: Bool { index >= items.count }
    private var queueSection: String { section?.code ?? "ALL" }
    private var title: String { section.map { "\($0.code) Confusion" } ?? "Confusion" }
    private var readinessSection: CPASection { confusionReadinessSection(after: section) }
    private var readinessButtonLabel: String { confusionReadinessButtonLabel(for: section) }
    private var emptyDescription: String {
        if let section {
            return "No \(section.code) confusion items are available yet. Load or import section practice to build the drill queue."
        }
        return "Load or import CPA practice to build the drill queue."
    }

    init(section: CPASection? = nil) {
        self.section = section
    }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
                handleImport(result)
            }
            .alert("Import", isPresented: $showImportAlert) {
                Button("OK") {}
            } message: {
                Text(importMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView {
                Label("Couldn't load drill", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Retry") {
                    Task { await load() }
                }
            }
        } else if items.isEmpty {
            ContentUnavailableView {
                Label("No confusion items", systemImage: "questionmark.circle")
            } description: {
                Text(emptyDescription)
            } actions: {
                Button("Import package", systemImage: "square.and.arrow.down") {
                    showImport = true
                }
                NavigationLink(value: readinessSection) {
                    Label(readinessButtonLabel, systemImage: "chart.line.uptrend.xyaxis")
                }
                Button("Retry") {
                    Task { await load() }
                }
            }
        } else if done {
            finishedCard
        } else {
            itemCard(items[index])
        }
    }

    private var finishedCard: some View {
        VStack(spacing: AnkountantSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(palette.positive)
            Text("Queue complete — \(items.count) items reviewed.")
                .ankountantFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            NavigationLink(value: readinessSection) {
                Label(readinessButtonLabel, systemImage: "chart.line.uptrend.xyaxis")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AnkountantPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AnkountantSpacing.xl)
    }

    private func itemCard(_ current: ConfusionItemModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AnkountantSpacing.lg) {
                // Label-stripped stem: content only, never the set/category label.
                Text(stripConfusionSlug(current.prompt))
                    .ankountantFont(.cardTitle)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ConfidenceGateView(committed: $confidence)

                if confidence != nil {
                    VStack(spacing: AnkountantSpacing.sm) {
                        ForEach(current.treatments, id: \.self) { treatment in
                            treatmentButton(current, treatment)
                        }
                    }
                }

                if let submitError {
                    SimulationSubmitErrorView(message: submitError)
                }

                if let lastCorrect {
                    verdict(lastCorrect)
                }
            }
            .padding(AnkountantSpacing.lg)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func treatmentButton(_ current: ConfusionItemModel, _ treatment: String) -> some View {
        Button {
            Task { await choose(current, treatment) }
        } label: {
            Text(treatment)
                .ankountantFont(.body)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, AnkountantSpacing.md)
                .padding(.vertical, AnkountantSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                        .fill(palette.surfaceInset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(submitting || lastCorrect != nil)
    }

    private func verdict(_ correct: Bool) -> some View {
        let tone = correct ? palette.positive : palette.danger
        return VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            // Feedback dominates post-reveal: colour is paired with an icon and a
            // text label so it never rides on colour alone.
            HStack(spacing: AnkountantSpacing.sm) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(correct ? "Correct" : "Incorrect")
                    .ankountantFont(.bodyEmphasis)
            }
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AnkountantSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                    .fill(tone.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                    .stroke(tone.opacity(0.4), lineWidth: 1)
            )

            if let reveal {
                confusionReveal(reveal)
            }

            if let revealError {
                SimulationRevealErrorView(message: revealError)
            }

            HStack {
                Spacer()
                Button("Next") { next() }
                    .buttonStyle(AnkountantPrimaryButtonStyle())
            }
        }
    }

    private func confusionReveal(_ reveal: ConfusionRevealModel) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
            Text("Correct treatment")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            Text(reveal.correctText)
                .ankountantFont(.bodyEmphasis)
                .foregroundStyle(palette.accent)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(revealBlueprint(reveal))
                .ankountantFont(.micro)
                .foregroundStyle(palette.accent)
                .padding(.horizontal, AnkountantSpacing.sm)
                .padding(.vertical, 2)
                .background(palette.accent.opacity(0.12), in: Capsule())
            if !reveal.source.isEmpty {
                Text(reveal.source)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(AnkountantSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
    }

    private func revealBlueprint(_ reveal: ConfusionRevealModel) -> String {
        let topic = topicDisplayName(reveal.setId)
        let schema = schemaTagDisplayName(reveal.schemaTag)
        return schema.isEmpty ? topic : "\(topic) · \(schema)"
    }

    private func load() async {
        isLoading = true
        loadError = nil
        let confusionQueue = performanceClient.confusionQueue
        let queueSection = queueSection
        defer {
            if !Task.isCancelled {
                isLoading = false
            }
        }
        do {
            let loadedItems = try await Task.detached(priority: .userInitiated) {
                try confusionQueue(queueSection, 60)
            }.value
            guard !Task.isCancelled else { return }
            items = loadedItems
            index = 0
            confidence = nil
            lastCorrect = nil
            reveal = nil
            submitError = nil
            revealError = nil
            itemStartedAt = Date.now
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            items = []
            loadError = error.localizedDescription
        }
    }

    private func choose(_ current: ConfusionItemModel, _ treatment: String) async {
        guard let confidence, !submitting, lastCorrect == nil else { return }
        submitError = nil
        reveal = nil
        revealError = nil
        submitting = true
        defer { submitting = false }
        let latencyMs = UInt32(clamping: Int((Date.now.timeIntervalSince(itemStartedAt) * 1000).rounded()))
        let submitConfusion = performanceClient.submitConfusion
        let loadConfusionReveal = performanceClient.loadConfusionReveal
        let confidenceValue = confidence.rawValue
        do {
            let resp = try await Task.detached(priority: .userInitiated) {
                try submitConfusion(current.noteId, treatment, confidenceValue, latencyMs)
            }.value
            guard !Task.isCancelled else { return }
            lastCorrect = resp.totalCredit >= 1
            do {
                reveal = try await Task.detached(priority: .userInitiated) {
                    try loadConfusionReveal(current.noteId, current.setId)
                }.value
            } catch {
                guard !Task.isCancelled else { return }
                revealError = "Attempt recorded, but the correct treatment could not be shown: \(error.localizedDescription)"
            }
        } catch {
            guard !Task.isCancelled else { return }
            submitError = "Could not record this attempt: \(error.localizedDescription)"
        }
    }

    private func next() {
        index += 1
        confidence = nil
        lastCorrect = nil
        reveal = nil
        submitError = nil
        revealError = nil
        itemStartedAt = Date.now
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
                    await load()
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

func confusionReadinessSection(after section: CPASection?) -> CPASection {
    section ?? .far
}

func confusionReadinessButtonLabel(for section: CPASection?) -> String {
    guard let section else {
        return "View FAR readiness"
    }
    return "View \(section.code) readiness"
}
