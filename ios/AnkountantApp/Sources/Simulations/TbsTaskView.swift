import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import Dependencies

let journalEntrySpareLineCount = 2

func spareJournalEntryLines(count: Int = journalEntrySpareLineCount) -> [JeLineInput] {
    (0..<count).map { JeLineInput(id: "spare-\($0 + 1)") }
}

struct TbsTaskView: View {
    let noteId: Int64

    @Environment(\.palette) private var palette
    @Dependency(\.performanceClient) var performanceClient

    @State private var model: TbsModel?
    @State private var jeLines: [JeLineInput] = []
    @State private var spareJeLines: [JeLineInput] = spareJournalEntryLines()
    @State private var numericCells: [NumericCellInput] = []
    @State private var confidence: ConfidenceLevel?
    @State private var results: [PerformanceStepResult]?
    @State private var reveal: TbsRevealModel?
    @State private var total: Double?
    @State private var submitting = false
    @State private var loadError: String?
    @State private var submitError: String?
    @State private var revealError: String?
    @State private var startedAt = Date.now

    private var answerInputsLocked: Bool {
        submitting || results != nil
    }

    init(noteId: Int64) {
        self.noteId = noteId
    }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't Load Simulation",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Simulation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ model: TbsModel) -> some View {
        switch model.shape {
        case .research:
            // Section-agnostic research surface (literature search + citation).
            ResearchTaskView(noteId: noteId, model: model)
        case .docReview:
            // Section-agnostic document-review surface (blanks + partial credit).
            DocReviewTaskView(noteId: noteId, model: model)
        case .numeric, .journalEntry:
            jeNumericContent(model)
        }
    }

    @ViewBuilder
    private func jeNumericContent(_ model: TbsModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.prompt)
                    .ankountantFont(.cardTitle)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ConfidenceGateView(committed: $confidence)

                switch model.shape {
                case .numeric:
                    numericGrid(model)
                    submitSection(model)
                case .journalEntry:
                    journalEntryGrid(model)
                    submitSection(model)
                default:
                    EmptyView()
                }

                let exhibits = paneExhibits(model)
                if !exhibits.isEmpty {
                    SimulationExhibitsView(exhibits: exhibits)
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }

    // MARK: - Numeric grid

    @ViewBuilder
    private func numericGrid(_ model: TbsModel) -> some View {
        VStack(spacing: 0) {
            ForEach($numericCells) { $cell in
                HStack(spacing: 12) {
                    Text(stepLabel(model, cell.id))
                        .ankountantFont(.body)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Value", text: $cell.value)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .ankountantFont(.mono)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .disabled(answerInputsLocked)
                    stepMark(for: cell.id)
                }
                .padding(.vertical, 10)
                if cell.id != numericCells.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    // MARK: - Journal-entry grid

    @ViewBuilder
    private func journalEntryGrid(_ model: TbsModel) -> some View {
        VStack(spacing: 12) {
            ForEach($jeLines) { $line in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(stepLabel(model, line.id))
                            .ankountantFont(.captionBold)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        stepMark(for: line.id)
                    }
                    Picker("Account", selection: $line.account) {
                        Text("Select account").tag("")
                        ForEach(journalEntryAccounts, id: \.self) { account in
                            Text(account).tag(account)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(answerInputsLocked || line.noEntry)
                    HStack(spacing: 12) {
                        Picker("Debit / Credit", selection: $line.side) {
                            Text("Select").tag("")
                            Text("Debit").tag("dr")
                            Text("Credit").tag("cr")
                        }
                        .pickerStyle(.menu)
                        .disabled(answerInputsLocked || line.noEntry)
                        Spacer()
                        TextField("Amount", text: $line.amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .ankountantFont(.mono)
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                            .disabled(answerInputsLocked || line.noEntry)
                    }
                    Toggle("No entry", isOn: $line.noEntry)
                        .disabled(answerInputsLocked)
                        .onChange(of: line.noEntry) { _, noEntry in
                            if noEntry {
                                line.account = ""
                                line.side = ""
                                line.amount = ""
                            }
                        }
                }
                .padding(12)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
            }
            ForEach($spareJeLines) { $line in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spare line")
                        .ankountantFont(.captionBold)
                        .foregroundStyle(palette.textSecondary)
                    Picker("Spare account", selection: $line.account) {
                        Text("Spare account").tag("")
                        ForEach(journalEntryAccounts, id: \.self) { account in
                            Text(account).tag(account)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(answerInputsLocked)
                    HStack(spacing: 12) {
                        Picker("Spare debit / credit", selection: $line.side) {
                            Text("Select").tag("")
                            Text("Debit").tag("dr")
                            Text("Credit").tag("cr")
                        }
                        .pickerStyle(.menu)
                        .disabled(answerInputsLocked)
                        Spacer()
                        TextField("Spare amount", text: $line.amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .ankountantFont(.mono)
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                            .disabled(answerInputsLocked)
                    }
                }
                .padding(12)
                .background(palette.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Submit

    @ViewBuilder
    private func submitSection(_ model: TbsModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await submit(model) }
            } label: {
                Text(submitting ? "Submitting…" : "Submit")
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
                HStack(spacing: 6) {
                    Text("Partial credit:")
                        .ankountantFont(.body)
                        .foregroundStyle(palette.textSecondary)
                    Text("\(Int((total * 100).rounded()))%")
                        .ankountantFont(.bodyEmphasis)
                        .foregroundStyle(palette.accent)
                }
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
        .padding(.top, 4)
    }

    // MARK: - Step mark

    @ViewBuilder
    private func stepMark(for id: String) -> some View {
        if let result = resultById[id] {
            Image(systemName: result.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.correct ? palette.positive : palette.danger)
                .accessibilityLabel(result.correct ? "Correct" : "Incorrect")
        }
    }

    // MARK: - Helpers

    private var resultById: [String: PerformanceStepResult] {
        Dictionary(uniqueKeysWithValues: (results ?? []).map { ($0.id, $0) })
    }

    private func stepLabel(_ model: TbsModel, _ id: String) -> String {
        model.steps.first(where: { $0.id == id })?.label ?? id
    }

    // MARK: - Data

    private func load() async {
        do {
            let m = try performanceClient.loadTbs(noteId)
            model = m
            jeLines = m.steps.map { JeLineInput(id: $0.id) }
            spareJeLines = spareJournalEntryLines()
            numericCells = m.steps.map { NumericCellInput(id: $0.id) }
            confidence = nil
            results = nil
            reveal = nil
            total = nil
            submitError = nil
            revealError = nil
            startedAt = Date.now
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func submit(_ model: TbsModel) async {
        guard let confidence, !submitting, results == nil else { return }
        submitting = true
        submitError = nil
        revealError = nil
        defer { submitting = false }
        do {
            let submissionJson: String
            if model.shape == .numeric {
                submissionJson = try buildNumericSubmission(numericCells)
            } else {
                submissionJson = try buildJeSubmission(jeLines)
            }
            let latencyMs = UInt32(clamping: Int((Date.now.timeIntervalSince(startedAt) * 1000).rounded()))
            let resp = try performanceClient.submitTbs(noteId, submissionJson, confidence.rawValue, latencyMs)
            results = resp.steps
            total = resp.totalCredit
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
