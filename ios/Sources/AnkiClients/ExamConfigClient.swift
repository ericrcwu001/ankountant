public import Dependencies
import DependenciesMacros

/// A1 — the section's exam date. The backend stores it as a sync-safe settings
/// note so desktop and iOS merge date edits through normal object sync.
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
