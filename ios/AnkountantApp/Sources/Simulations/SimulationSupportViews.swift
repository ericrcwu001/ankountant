import SwiftUI
import AnkiKit
import AnkountantTheme

// Shared building blocks for the section-agnostic TBS surfaces (research +
// document-review), mirroring the desktop exam shell's Exhibits pane, Literature
// browser, and header (ts/routes/(ankountant)/ankountant-tbs/*). Kept here so
// ResearchTaskView and DocReviewTaskView stay small.

/// The bundled per-section literature corpus, decoded once. A top-level `let`
/// is lazily initialised a single time, so the JSON is read/parsed only once
/// regardless of how many times the panes re-render.
private let bundledCorpus: [String: [CorpusEntry]] = {
    do {
        return try loadLiteratureCorpus()
    } catch {
        fatalError("Could not load bundled literature corpus: \(error.localizedDescription)")
    }
}()

/// Prompt + section chip header shared by the research / doc-review surfaces
/// (parity with the desktop `ExamShell` head).
struct SimulationHeaderView: View {
    let title: String
    let section: String
    let prompt: String

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            HStack(spacing: AnkountantSpacing.sm) {
                Text(title)
                    .ankountantFont(.cardTitle)
                    .foregroundStyle(palette.textPrimary)
                Text(section)
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, AnkountantSpacing.sm)
                    .padding(.vertical, 2)
                    .background(palette.accent.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Section \(section)")
            }
            if !prompt.isEmpty {
                Text(prompt)
                    .ankountantFont(.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Typed exhibits list (ADR 0008 / D9): `table` exhibits get a real grid
/// (columns + rows); every other kind renders its text body in a mono block.
/// Mirrors the desktop `ExhibitsPane`.
struct SimulationExhibitsView: View {
    let exhibits: [Exhibit]

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            Text("Exhibits")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            ForEach(exhibits) { exhibit in
                exhibitCard(exhibit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func exhibitCard(_ exhibit: Exhibit) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(exhibit.title)
                    .ankountantFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: AnkountantSpacing.sm)
                Text(exhibit.kind.uppercased())
                    .ankountantFont(.micro)
                    .foregroundStyle(palette.textSecondary)
            }
            if exhibit.kind == "table", let rows = exhibit.rows, !rows.isEmpty {
                exhibitTable(columns: exhibit.columns ?? [], rows: rows)
            } else if !exhibit.body.isEmpty {
                Text(exhibit.body)
                    .ankountantFont(.mono)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
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
    private func exhibitTable(columns: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: AnkountantSpacing.md, verticalSpacing: AnkountantSpacing.xs) {
            if !columns.isEmpty {
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(column)
                            .ankountantFont(.captionBold)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Divider()
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .ankountantFont(.mono)
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

struct SimulationSubmitErrorView: View {
    let message: String

    var body: some View {
        AnkountantStatusMessageView(
            title: "Attempt not recorded",
            message: message,
            systemImage: "exclamationmark.triangle",
            tone: .danger
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, AnkountantSpacing.sm)
        .ankountantStatusPanel(.danger)
    }
}

struct SimulationRevealErrorView: View {
    let message: String

    var body: some View {
        AnkountantStatusMessageView(
            title: "Answer key unavailable",
            message: message,
            systemImage: "exclamationmark.triangle",
            tone: .warning
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, AnkountantSpacing.sm)
        .ankountantStatusPanel(.warning)
    }
}

struct SimulationResultsRevealView: View {
    let reveal: TbsRevealModel
    let results: [PerformanceStepResult]

    @Environment(\.palette) private var palette

    private var correctById: [String: Bool] {
        Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0.correct) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            Text("Answer key & rationale")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
                ForEach(reveal.steps) { step in
                    revealRow(step)
                }
            }

            VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
                Text(reveal.schemaTag.isEmpty ? reveal.section : "\(reveal.section) · \(reveal.schemaTag)")
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
            .padding(.top, AnkountantSpacing.xs)
        }
        .padding(AnkountantSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AnkountantRadius.card, style: .continuous)
                .stroke(palette.borderSubtle, lineWidth: 1)
        )
    }

    private func revealRow(_ step: StepReveal) -> some View {
        let correct = correctById[step.id] ?? false
        return HStack(alignment: .top, spacing: AnkountantSpacing.sm) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(correct ? palette.positive : palette.danger)
                .accessibilityLabel(correct ? "You were correct" : "You were incorrect")
            VStack(alignment: .leading, spacing: AnkountantSpacing.xxs) {
                Text(step.label)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textPrimary)
                Text(step.correctText)
                    .ankountantFont(.mono)
                    .foregroundStyle(palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Read-only authoritative-literature browser (T2 / OQ-3): client-side search
/// over the bundled, per-section corpus. Handles BOTH bodies (D10): ASC
/// (FAR/BAR) shows OUR paraphrase + a deep link; IRC/PCAOB/NIST show real
/// verbatim public-domain text. `onCite` fills a caller's citation field.
/// Mirrors the desktop `LiteraturePane`.
struct LiteraturePaneView: View {
    let section: String
    var citationEnabled = true
    var onCite: ((String) -> Void)? = nil

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var query = ""

    private enum CorpusState {
        case ready([CorpusEntry])
        case failed(String)
    }

    private var corpusState: CorpusState {
        do {
            return .ready(try corpusForSection(bundledCorpus, section))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.md) {
            Text("Authoritative literature — \(section)")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            TextField("Search the \(section) literature…", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("Search literature")
            switch corpusState {
            case let .ready(entries):
                literatureResults(entries)
            case let .failed(message):
                literatureError(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func literatureResults(_ entries: [CorpusEntry]) -> some View {
        let results = searchCorpus(entries, query: query)
        if results.isEmpty {
            Text(query.isEmpty
                ? "No literature bundled for this section yet."
                : "No passages match \"\(query)\".")
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
        } else {
            ForEach(results) { entry in
                resultCard(entry)
            }
        }
    }

    private func literatureError(_ message: String) -> some View {
        AnkountantStatusMessageView(
            title: "Literature unavailable",
            message: message,
            systemImage: "exclamationmark.triangle",
            tone: .danger
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, AnkountantSpacing.sm)
        .ankountantStatusPanel(.danger)
    }

    private func resultCard(_ entry: CorpusEntry) -> some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.citation)
                    .ankountantFont(.captionBold)
                    .foregroundStyle(palette.accent)
                Spacer(minLength: AnkountantSpacing.sm)
                Text(entry.verbatim ? "Verbatim · public domain" : "Paraphrase · cite-only")
                    .ankountantFont(.micro)
                    .foregroundStyle(entry.verbatim ? palette.accent : palette.textSecondary)
            }
            Text(entry.title)
                .ankountantFont(.captionBold)
                .foregroundStyle(palette.textPrimary)
            Text(entry.body)
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
                .italic(!entry.verbatim)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: AnkountantSpacing.md) {
                if let deepLink = entry.deepLink, let url = URL(string: deepLink) {
                    Button("Open source ↗") { openURL(url) }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.link)
                        .ankountantFont(.caption)
                }
                if let onCite {
                    Button("Use this citation") { onCite(entry.citation) }
                        .buttonStyle(AnkountantSecondaryButtonStyle())
                        .disabled(!citationEnabled)
                }
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
}
