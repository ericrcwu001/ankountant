import AnkiBackend
public import Dependencies
import DependenciesMacros

extension ExamConfigClient: DependencyKey {
    /// Matches `rslib` `config::exam_date_key(section)` and the desktop TS
    /// caller. Keep stable so a synced collection reads the same date on every
    /// client.
    private static func key(_ section: String) -> String {
        "ankountant.\(section).exam.date"
    }

    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            loadExamDate: { section in
                // The stored value is a bare JSON string; decode it as such.
                try backend.getConfigJSONValue(for: key(section))
            },
            saveExamDate: { section, iso in
                try backend.setConfigJSONValue(iso, for: key(section))
            }
        )
    }()
}
