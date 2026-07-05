import XCTest
import AnkiBackend

final class SharedRustBackendSmokeTests: XCTestCase {
    func testBackendOpensTemporaryCollectionThroughFFI() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ankountant-ffi-\(UUID().uuidString)", isDirectory: true)
        let media = root.appendingPathComponent("media", isDirectory: true)
        let collection = root.appendingPathComponent("collection.anki2")
        let mediaDb = root.appendingPathComponent("media.db")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let backend = try AnkiBackend(preferredLangs: ["en"])
        try backend.openCollection(
            collectionPath: collection.path,
            mediaFolderPath: media.path,
            mediaDbPath: mediaDb.path
        )
        defer { try? backend.closeCollection() }

        try backend.checkDatabase()
        XCTAssertEqual(backend.currentMediaFolderPath, media.path)
    }
}
