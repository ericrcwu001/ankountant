import AnkiKit
import AnkiServices
public import Dependencies
import DependenciesMacros
import Foundation

extension PerformanceClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.notesService) var notes
        @Dependency(\.schedulerService) var scheduler

        @Sendable func fields(of noteId: Int64) throws -> [String] {
            let note = try notes.getNote(noteId)
            return note.flds.components(separatedBy: "\u{1f}")
        }

        return Self(
            listTbsTasks: {
                let query = "\"note:Ankountant TBS\" deck:Ankountant::Sealed::FAR::*"
                let ids = try notes.searchNoteIds(query)
                return try ids.map { id in
                    let model = buildTbsModel(fields: try fields(of: id))
                    return TbsTaskSummary(noteId: id, shape: model.shape, prompt: model.prompt)
                }
            },
            loadTbs: { noteId in
                buildTbsModel(fields: try fields(of: noteId))
            },
            submitTbs: { noteId, submissionJson, confidence, latencyMs in
                try scheduler.submitPerformanceAttempt(noteId, "tbs", submissionJson, confidence, latencyMs)
            },
            confusionQueue: { section, maxItems in
                try scheduler.buildConfusionQueue(section, maxItems)
            },
            submitConfusion: { noteId, choice, confidence, latencyMs in
                try scheduler.submitPerformanceAttempt(noteId, "confusion", buildChoiceSubmission(choice), confidence, latencyMs)
            }
        )
    }()
}
