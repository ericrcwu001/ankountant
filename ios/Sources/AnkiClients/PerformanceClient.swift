public import AnkiKit
public import Dependencies
import DependenciesMacros

/// Facade for the Ankountant "performance" surfaces (TBS + Confusion). Backed by
/// NotesService (to load sealed TBS notes) and SchedulerService (to build the
/// confusion queue and submit graded attempts). Grading is authoritative on the
/// Rust side; this client only loads note structure and forwards submissions.
@DependencyClient
public struct PerformanceClient: Sendable {
    /// List the sealed TBS tasks (search "note:Ankountant TBS" in the sealed
    /// FAR decks), each summarised for the task list.
    public var listTbsTasks: @Sendable () throws -> [TbsTaskSummary]
    /// Load one sealed TBS note into its render model (answer keys stripped).
    public var loadTbs: @Sendable (_ noteId: Int64) throws -> TbsModel
    /// Submit a graded TBS attempt (mode "tbs" — journal-entry / numeric).
    public var submitTbs: @Sendable (_ noteId: Int64, _ submissionJson: String, _ confidence: String, _ latencyMs: UInt32) throws -> PerformanceAttemptResult
    /// Submit a graded research attempt (mode "research"; all-or-nothing on the
    /// citation). `latencyMs` is recorded as time-to-cite, never folded into
    /// credit.
    public var submitResearch: @Sendable (_ noteId: Int64, _ citation: String, _ confidence: String, _ latencyMs: UInt32) throws -> PerformanceAttemptResult
    /// Submit a graded document-review attempt (mode "doc_review"; per-blank
    /// partial credit). `submissionJson` is `{"steps":[{id,value}]}` from
    /// `buildStepsSubmission`.
    public var submitDocReview: @Sendable (_ noteId: Int64, _ submissionJson: String, _ confidence: String, _ latencyMs: UInt32) throws -> PerformanceAttemptResult
    /// Build the interleaved, label-stripped confusion queue for a section.
    public var confusionQueue: @Sendable (_ section: String, _ maxItems: Int32) throws -> [ConfusionItemModel]
    /// Submit a graded confusion discrimination choice (mode "confusion").
    public var submitConfusion: @Sendable (_ noteId: Int64, _ choice: String, _ confidence: String, _ latencyMs: UInt32) throws -> PerformanceAttemptResult
}

extension PerformanceClient: TestDependencyKey {
    public static let testValue = PerformanceClient()
}

extension DependencyValues {
    public var performanceClient: PerformanceClient {
        get { self[PerformanceClient.self] }
        set { self[PerformanceClient.self] = newValue }
    }
}
