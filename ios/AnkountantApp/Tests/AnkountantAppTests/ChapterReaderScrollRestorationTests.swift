import XCTest
@testable import AnkountantApp

final class ChapterReaderScrollRestorationTests: XCTestCase {
    func testOffsetUsesReadableContentRange() {
        let offset = ReaderScrollRestoration.offset(
            for: 0.5,
            contentHeight: 1_000,
            viewportHeight: 250
        )

        XCTAssertEqual(offset, 375)
    }

    func testOffsetClampsHighProgress() {
        let offset = ReaderScrollRestoration.offset(
            for: 1.5,
            contentHeight: 1_000,
            viewportHeight: 250
        )

        XCTAssertEqual(offset, 750)
    }

    func testOffsetClampsLowProgress() {
        let offset = ReaderScrollRestoration.offset(
            for: -0.5,
            contentHeight: 1_000,
            viewportHeight: 250
        )

        XCTAssertEqual(offset, 0)
    }

    func testOffsetReturnsZeroForShortDocuments() {
        let offset = ReaderScrollRestoration.offset(
            for: 0.5,
            contentHeight: 250,
            viewportHeight: 1_000
        )

        XCTAssertEqual(offset, 0)
    }
}
