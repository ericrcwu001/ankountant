import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import Dependencies

/// Document-review simulation (T3) — parity with the desktop
/// ts/routes/(ankountant)/ankountant-doc-review/DocReviewSurface.svelte. The
/// primary document (an exhibit with role:"document") is split on inline
/// `<blank step="id">` markers; each blank gets a label-stripped menu `Picker`
/// of its keep/delete/replace options. All blanks submit in one attempt
/// (mode "doc_review"); grading is per-blank with a partial-credit total (A10).
/// Options never reveal which is correct before submit.
struct DocReviewTaskView: View {
    let noteId: Int64
    let model: TbsModel

    @Environment(\.palette) private var palette
    @Dependency(\.performanceClient) private var performanceClient

    @State private var confidence: ConfidenceLevel?
    @State private var blanks: [DocReviewBlankInput]
    @State private var results: [PerformanceStepResult]?
    @State private var total: Double?
    @State private var submitting = false
    @State private var submitError: String?
    @State private var startedAt = Date()

    init(noteId: Int64, model: TbsModel) {
        self.noteId = noteId
        self.model = model
        _blanks = State(initialValue: model.steps.map { DocReviewBlankInput(id: $0.id) })
    }

    private var segments: [DocSegment] { segmentDocument(model.document) }

    private var stepById: [String: RenderStep] {
        Dictionary(model.steps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var resultById: [String: PerformanceStepResult] {
        Dictionary((results ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var documentExhibit: Exhibit? {
        model.exhibits.first(where: { $0.role == "document" })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AnkountantSpacing.lg) {
                SimulationHeaderView(title: "Document review", section: model.section, prompt: model.prompt)

                ConfidenceGateView(committed: $confidence)

                documentCard
                blanksSection
                submitSection

                let exhibits = paneExhibits(model)
                if !exhibits.isEmpty {
                    SimulationExhibitsView(exhibits: exhibits)
                }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }

    // MARK: - Document (prose with the blanks resolved inline)

    private var documentCard: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            if let title = documentExhibit?.title {
                Text(title)
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
            }
            documentProse
                .ankountantFont(.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(AnkountantSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
    }

    /// The document body as flowing text, with each blank rendered inline as a
    /// numbered, underlined span showing the current selection (or the original
    /// text until one is picked). The interactive picker lives in `blanksSection`.
    private var documentProse: Text {
        var prose = Text("")
        var blankNumber = 0
        for segment in segments {
            switch segment {
            case let .text(_, text):
                prose = prose + Text(text)
            case let .blank(_, blankId, original):
                blankNumber += 1
                let shown = selectedText(for: blankId) ?? original
                prose = prose
                    + Text("[\(blankNumber)] \(shown)")
                    .underline()
                    .foregroundStyle(palette.accent)
            }
        }
        return prose
    }

    private func selectedText(for blankId: String) -> String? {
        guard let selection = blanks.first(where: { $0.id == blankId })?.selection,
              !selection.isEmpty,
              let option = stepById[blankId]?.options.first(where: { $0.id == selection })
        else {
            return nil
        }
        return option.text
    }

    // MARK: - Blanks (label-stripped menu picker per blank)

    private var blanksSection: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            Text("Your edits")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                blankRow(number: index + 1, step: step, selection: $blanks[index].selection)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blankRow(number: Int, step: RenderStep, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: AnkountantSpacing.sm) {
                Text("\(number).")
                    .ankountantFont(.captionBold)
                    .foregroundStyle(palette.textSecondary)
                Text(step.label)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                stepMark(for: step.id)
            }
            Picker(step.label, selection: selection) {
                Text("Select…").tag("")
                ForEach(step.options) { option in
                    Text(option.text).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(results != nil)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AnkountantSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func stepMark(for id: String) -> some View {
        if let result = resultById[id] {
            Image(systemName: result.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.correct ? palette.positive : palette.danger)
                .accessibilityLabel(result.correct ? "Correct" : "Incorrect")
        }
    }

    // MARK: - Submit

    private var submitSection: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Button {
                Task { await submit() }
            } label: {
                Text(submitting ? "Submitting…" : "Submit review")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AnkountantPrimaryButtonStyle())
            .disabled(submitting || confidence == nil || results != nil)

            if confidence == nil {
                Text("Commit a confidence level first.")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if let total {
                HStack(spacing: AnkountantSpacing.xs) {
                    Text("Partial credit:")
                        .ankountantFont(.body)
                        .foregroundStyle(palette.textSecondary)
                    Text("\(Int((total * 100).rounded()))%")
                        .ankountantFont(.bodyEmphasis)
                        .foregroundStyle(palette.accent)
                }
            }

            if let submitError {
                Text(submitError)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() async {
        guard confidence != nil, !submitting, results == nil else { return }
        submitting = true
        submitError = nil
        defer { submitting = false }
        let submissionJson = buildStepsSubmission(blanks.map { (id: $0.id, value: $0.selection) })
        let latency = UInt32(clamping: Int((Date().timeIntervalSince(startedAt) * 1000).rounded()))
        do {
            let resp = try performanceClient.submitDocReview(noteId, submissionJson, confidence!.rawValue, latency)
            results = resp.steps
            total = resp.totalCredit
        } catch {
            submitError = error.localizedDescription
        }
    }
}
