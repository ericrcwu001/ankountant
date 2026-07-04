import AnkiBackend
public import Dependencies
import DependenciesMacros

extension ExamConfigClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            loadExamDate: { section in
                let date = try backend.getExamDate(section: section)
                return date.isEmpty ? nil : date
            },
            saveExamDate: { section, iso in
                try backend.setExamDate(section: section, date: iso)
            }
        )
    }()
}
