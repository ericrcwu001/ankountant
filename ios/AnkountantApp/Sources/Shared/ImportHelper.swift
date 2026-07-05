import AnkiServices
import Dependencies
import Foundation

enum ImportError: Error, LocalizedError {
    case accessDenied
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Cannot access the selected file"
        case .importFailed(let msg): return msg
        }
    }
}

enum ImportHelper {
    static func importPackage(from url: URL) throws -> String {
        @Dependency(\.importExportService) var importExportService
        return try importPackage(from: url, importAnkiPackage: importExportService.importAnkiPackage)
    }

    static func importPackageInBackground(from url: URL) async throws -> String {
        @Dependency(\.importExportService) var importExportService
        let importAnkiPackage = importExportService.importAnkiPackage
        return try await Task.detached(priority: .userInitiated) {
            try importPackage(from: url, importAnkiPackage: importAnkiPackage)
        }.value
    }

    private static func importPackage(
        from url: URL,
        importAnkiPackage: @Sendable (_ path: String) throws -> String
    ) throws -> String {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(url.lastPathComponent)
        try removeExistingFile(at: tempFile)
        try FileManager.default.copyItem(at: url, to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        return try importAnkiPackage(tempFile.path)
    }

    static func exportCollection(to filename: String = "collection.colpkg") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outPath = tempDir.appendingPathComponent(filename)
        try removeExistingFile(at: outPath)

        @Dependency(\.importExportService) var importExportService
        try importExportService.exportCollectionPackage(outPath.path, true)

        return outPath
    }

    /// Exports a single deck as an `.apkg` file in the temporary directory and
    /// returns the URL. The default options preserve scheduling, deck configs,
    /// and media — matching upstream Anki's "Export including media" preset.
    static func exportDeck(
        deckId: Int64,
        deckName: String,
        withScheduling: Bool = true,
        withDeckConfigs: Bool = true,
        withMedia: Bool = true
    ) throws -> URL {
        @Dependency(\.importExportService) var importExportService
        return try exportDeck(
            deckId: deckId,
            deckName: deckName,
            withScheduling: withScheduling,
            withDeckConfigs: withDeckConfigs,
            withMedia: withMedia,
            exportDeckPackage: importExportService.exportDeckPackage
        )
    }

    static func exportDeckInBackground(
        deckId: Int64,
        deckName: String,
        withScheduling: Bool = true,
        withDeckConfigs: Bool = true,
        withMedia: Bool = true
    ) async throws -> URL {
        @Dependency(\.importExportService) var importExportService
        let exportDeckPackage = importExportService.exportDeckPackage
        return try await Task.detached(priority: .userInitiated) {
            try exportDeck(
                deckId: deckId,
                deckName: deckName,
                withScheduling: withScheduling,
                withDeckConfigs: withDeckConfigs,
                withMedia: withMedia,
                exportDeckPackage: exportDeckPackage
            )
        }.value
    }

    private static func exportDeck(
        deckId: Int64,
        deckName: String,
        withScheduling: Bool,
        withDeckConfigs: Bool,
        withMedia: Bool,
        exportDeckPackage: @Sendable (Int64, String, Bool, Bool, Bool, Bool) throws -> UInt32
    ) throws -> URL {
        let safeName = deckName
            .replacingOccurrences(of: "::", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let filename = "\(safeName).apkg"
        let tempDir = FileManager.default.temporaryDirectory
        let outPath = tempDir.appendingPathComponent(filename)
        try removeExistingFile(at: outPath)

        _ = try exportDeckPackage(
            deckId,
            outPath.path,
            withScheduling,
            withDeckConfigs,
            withMedia,
            false  // legacy
        )

        return outPath
    }

    private static func removeExistingFile(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
