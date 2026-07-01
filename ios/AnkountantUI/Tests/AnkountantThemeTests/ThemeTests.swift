import XCTest
@testable import AnkountantTheme

final class ThemeTests: XCTestCase {
    func testAppearanceRawValues() {
        XCTAssertEqual(Appearance.system.rawValue, "system")
        XCTAssertEqual(Appearance.light.rawValue, "light")
        XCTAssertEqual(Appearance.dark.rawValue, "dark")
    }

    func testAppearanceAllCases() {
        XCTAssertEqual(Appearance.allCases, [.system, .light, .dark])
    }
}
