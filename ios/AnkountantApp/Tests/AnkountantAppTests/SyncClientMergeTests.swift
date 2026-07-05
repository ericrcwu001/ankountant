import XCTest
import Dependencies
import AnkiClients
import AnkiKit
import AnkiServices
import AnkiSync

final class SyncClientMergeTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        KeychainHelper.deleteHostKey()
        KeychainHelper.deleteEndpoint()
        KeychainHelper.deleteCurrentEndpoint()
        try KeychainHelper.saveHostKey("host-key")
        try KeychainHelper.saveEndpoint("https://sync.example.invalid")
    }

    override func tearDownWithError() throws {
        KeychainHelper.deleteHostKey()
        KeychainHelper.deleteEndpoint()
        KeychainHelper.deleteCurrentEndpoint()
        try super.tearDownWithError()
    }

    func testMergeDownloadsServerImportsLocalBackupUploadsMergedCollectionAndDeletesBackup() async throws {
        let recorder = SyncMergeRecorder()

        try await withDependencies {
            $0.syncService.fullSync = { endpoint, hostKey, direction in
                recorder.events.append("fullSync:\(direction.label):\(endpoint):\(hostKey)")
            }
            $0.importExportService.exportApkgForMerge = { path in
                recorder.backupPath = path
                recorder.events.append("export")
                guard FileManager.default.createFile(atPath: path, contents: Data("backup".utf8)) else {
                    throw NSError(domain: "SyncClientMergeTests", code: 1)
                }
            }
            $0.importExportService.importApkgForMerge = { path in
                recorder.events.append("import:\(path == recorder.backupPath)")
                return "Merged"
            }
        } operation: {
            let client = SyncClient.liveValue
            try await client.merge { message in
                recorder.events.append("progress:\(message)")
            }
        }

        XCTAssertEqual(recorder.events, [
            "progress:Backing up local collection...",
            "export",
            "progress:Downloading from server...",
            "fullSync:download:https://sync.example.invalid:host-key",
            "progress:Merging in local data...",
            "import:true",
            "progress:Uploading merged collection...",
            "fullSync:upload:https://sync.example.invalid:host-key",
        ])
        let backupPath = try XCTUnwrap(recorder.backupPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupPath))
    }
}

private final class SyncMergeRecorder: @unchecked Sendable {
    var events: [String] = []
    var backupPath: String?
}

private extension SyncDirection {
    var label: String {
        switch self {
        case .download: "download"
        case .upload: "upload"
        }
    }
}
