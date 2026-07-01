import XCTest
import SwiftUI
@testable import AnkountantTheme

final class PaletteTests: XCTestCase {
    func testResolveBothSchemes() {
        XCTAssertEqual(Palette.resolve(scheme: .light), .light)
        XCTAssertEqual(Palette.resolve(scheme: .dark), .dark)
    }

    func testLightHasAllSlotsPopulated() {
        let p = Palette.light
        XCTAssertNotEqual(p.background, p.surface)
        XCTAssertNotEqual(p.textPrimary, p.textSecondary)
        XCTAssertNotEqual(p.accent, p.danger)
        XCTAssertNotEqual(p.surfaceInset, p.background)
        XCTAssertNotEqual(p.onAccent, p.accent)
    }

    func testLightDiffersFromDark() {
        XCTAssertNotEqual(Palette.light.accent, Palette.dark.accent)
        XCTAssertNotEqual(Palette.light.background, Palette.dark.background)
    }

    func testCardStateTokensAlignToSemanticStates() {
        // learn is reconciled to the shared danger token (was iOS orange).
        XCTAssertEqual(Palette.light.stateLearn, Palette.light.danger)
        XCTAssertEqual(Palette.light.stateNew, Palette.light.info)
        XCTAssertEqual(Palette.light.stateReview, Palette.light.positive)
        XCTAssertEqual(Palette.light.stateBuried, Palette.light.warning)

        XCTAssertEqual(Palette.dark.stateLearn, Palette.dark.danger)
        XCTAssertEqual(Palette.dark.stateNew, Palette.dark.info)
        XCTAssertEqual(Palette.dark.stateReview, Palette.dark.positive)
        XCTAssertEqual(Palette.dark.stateBuried, Palette.dark.warning)
    }
}
