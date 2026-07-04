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

        // Fields + section tags: the section (ADR 0008) rides in the note's
        // `sec::<SECTION>` tag, so the render model needs both to scope the
        // literature and reveal correctly.
        @Sendable func fieldsAndTags(of noteId: Int64) throws -> (fields: [String], tags: [String]) {
            let note = try notes.getNote(noteId)
            let fields = note.flds.components(separatedBy: "\u{1f}")
            let tags = note.tags.split(separator: " ").map(String.init)
            return (fields, tags)
        }

        return Self(
            listTbsTasks: {
                let query = "\"note:Ankountant TBS\" deck:Ankountant::Sealed::FAR::*"
                let ids = try notes.searchNoteIds(query)
                return try ids.map { id in
                    let model = try buildTbsModel(fields: try fields(of: id))
                    return TbsTaskSummary(noteId: id, shape: model.shape, prompt: model.prompt)
                }
            },
            loadTbs: { noteId in
                let (fields, tags) = try fieldsAndTags(of: noteId)
                return try buildTbsModel(fields: fields, tags: tags)
            },
            submitTbs: { noteId, submissionJson, confidence, latencyMs in
                try scheduler.submitPerformanceAttempt(noteId, "tbs", submissionJson, confidence, latencyMs)
            },
            submitResearch: { noteId, citation, confidence, latencyMs in
                try scheduler.submitPerformanceAttempt(noteId, "research", buildResearchSubmission(citation), confidence, latencyMs)
            },
            submitDocReview: { noteId, submissionJson, confidence, latencyMs in
                try scheduler.submitPerformanceAttempt(noteId, "doc_review", submissionJson, confidence, latencyMs)
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
