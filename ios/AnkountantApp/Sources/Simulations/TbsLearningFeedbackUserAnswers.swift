import AnkiKit
import Foundation

func tbsAttemptNeedsLearningFeedback(results: [PerformanceStepResult], totalCredit: Double) -> Bool {
    results.contains { !$0.correct } || totalCredit < 1
}

func journalEntryLearningFeedbackUserAnswer(model: TbsModel, lines: [JeLineInput]) -> String {
    lines.map { line in
        let label = tbsStepLabel(model, line.id)
        if line.noEntry {
            return "\(label): No entry"
        }
        return "\(label): \(line.side.uppercased()) \(line.account) \(line.amount)"
    }
    .joined(separator: "\n")
}

func numericLearningFeedbackUserAnswer(model: TbsModel, cells: [NumericCellInput]) -> String {
    cells.map { cell in
        "\(tbsStepLabel(model, cell.id)): \(cell.value)"
    }
    .joined(separator: "\n")
}

func researchLearningFeedbackUserAnswer(citation: String) -> String {
    "Citation entered: \(citation.trimmingCharacters(in: .whitespacesAndNewlines))"
}

func docReviewLearningFeedbackUserAnswer(model: TbsModel, blanks: [DocReviewBlankInput]) -> String {
    blanks.map { blank in
        let optionText = model.steps
            .first(where: { $0.id == blank.id })?
            .options
            .first(where: { $0.id == blank.selection })?
            .text ?? blank.selection
        return "\(tbsStepLabel(model, blank.id)): \(optionText)"
    }
    .joined(separator: "\n")
}

private func tbsStepLabel(_ model: TbsModel, _ id: String) -> String {
    model.steps.first(where: { $0.id == id })?.label ?? id
}
