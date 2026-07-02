public import Dependencies
import DependenciesMacros

/// A1 — the section's exam date, stored in the Anki collection config so it
/// syncs across devices (and matches the desktop). Saving a date is what makes
/// the live scheduler deadline-anchored: `rslib` reads this same key
/// (`ankountant.<section>.exam.date`) in `card_state_updater`.
///
/// Lives in `AnkiClients` because the bridge to `setConfigJSONValue` is an Anki
/// concern; the value is a bare ISO-8601 (YYYY-MM-DD) string.
@DependencyClient
public struct ExamConfigClient: Sendable {
    /// The section's exam date as an ISO-8601 string, or nil when unset.
    public var loadExamDate: @Sendable (_ section: String) throws -> String?
    /// Persist the section's exam date (ISO-8601 YYYY-MM-DD).
    public var saveExamDate: @Sendable (_ section: String, _ iso: String) throws -> Void
}

extension ExamConfigClient: TestDependencyKey {
    public static let testValue = ExamConfigClient()
}

extension DependencyValues {
    public var examConfigClient: ExamConfigClient {
        get { self[ExamConfigClient.self] }
        set { self[ExamConfigClient.self] = newValue }
    }
}
