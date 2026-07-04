import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import Dependencies

/// Research simulation (T1) — parity with the desktop
/// ts/routes/(ankountant)/ankountant-research/ResearchSurface.svelte. The
/// learner searches the client-side, per-section literature browser, enters the
/// governing citation, and submits (mode "research"). Grading is all-or-nothing
/// (authoritative on the Rust side); time-to-cite is reported as a neutral
/// signal, never a credit multiplier (OQ-2). Section-agnostic: ASC (FAR/BAR)
/// shows paraphrase + link, IRC/PCAOB/NIST show verbatim text.
struct ResearchTaskView: View {
    let noteId: Int64
    let model: TbsModel

    @Environment(\.palette) private var palette
    @Dependency(\.performanceClient) private var performanceClient

    @State private var confidence: ConfidenceLevel?
    @State private var citation = ""
    @State private var submitting = false
    @State private var correct: Bool?
    @State private var results: [PerformanceStepResult]?
    @State private var reveal: TbsRevealModel?
    @State private var elapsedMs: UInt32 = 0
    @State private var submitError: String?
    @State private var revealError: String?
    @State private var startedAt = Date.now

    private var placeholder: String {
        model.steps.first?.placeholder ?? "e.g. ASC 842-20-25-1"
    }

    private var trimmedCitation: String {
        citation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var citationEntered: Bool {
        researchCitationComplete(citation)
    }

    private var responseLocked: Bool {
        submitting || correct != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AnkountantSpacing.lg) {
                SimulationHeaderView(title: "Research simulation", section: model.section, prompt: model.prompt)

                ConfidenceGateView(committed: $confidence)

                responseSection

                let exhibits = paneExhibits(model)
                if !exhibits.isEmpty {
                    SimulationExhibitsView(exhibits: exhibits)
                }

                LiteraturePaneView(section: model.section, citationEnabled: !responseLocked) {
                    citation = $0
                }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }

    private var responseSection: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            Text("Find the governing citation in the Literature browser below, then enter it.")
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                Text("Governing citation")
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textSecondary)
                    .textCase(.uppercase)
                TextField(placeholder, text: $citation)
                    .textFieldStyle(.roundedBorder)
                    .ankountantFont(.mono)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .disabled(responseLocked)
            }

            Button {
                Task { await submit() }
            } label: {
                Text(submitting ? "Submitting…" : "Submit citation")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AnkountantPrimaryButtonStyle())
            .disabled(submitting || confidence == nil || !citationEntered || correct != nil)

            if confidence == nil {
                Text("Commit a confidence level first.")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if !citationEntered {
                Text("Enter a governing citation.")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if let correct {
                verdict(correct)
            }

            if let reveal, let results {
                SimulationResultsRevealView(reveal: reveal, results: results)
            }

            if let revealError {
                SimulationRevealErrorView(message: revealError)
            }

            if let submitError {
                SimulationSubmitErrorView(message: submitError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verdict(_ correct: Bool) -> some View {
        let tone = correct ? palette.positive : palette.danger
        return VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
            // Feedback pairs colour with an icon + text label — never colour alone.
            HStack(spacing: AnkountantSpacing.sm) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(correct ? "Correct citation" : "Incorrect citation")
                    .ankountantFont(.bodyEmphasis)
            }
            .foregroundStyle(tone)
            Text("Found in \(secondsText)s — time is a signal, not part of the score.")
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AnkountantSpacing.md)
        .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(tone.opacity(0.4), lineWidth: 1)
        )
    }

    private var secondsText: String {
        (Double(elapsedMs) / 1000).formatted(.number.precision(.fractionLength(1)))
    }

    private func submit() async {
        guard let confidence, !submitting, correct == nil, citationEntered else { return }
        submitting = true
        submitError = nil
        revealError = nil
        defer { submitting = false }
        let latency = UInt32(clamping: Int((Date.now.timeIntervalSince(startedAt) * 1000).rounded()))
        do {
            let resp = try performanceClient.submitResearch(noteId, trimmedCitation, confidence.rawValue, latency)
            elapsedMs = latency
            results = resp.steps
            correct = resp.totalCredit >= 1
            do {
                reveal = try performanceClient.loadTbsReveal(noteId)
            } catch {
                revealError = "Attempt recorded, but the answer key could not be shown: \(error.localizedDescription)"
            }
        } catch {
            submitError = "Could not record this attempt: \(error.localizedDescription)"
        }
    }
}
