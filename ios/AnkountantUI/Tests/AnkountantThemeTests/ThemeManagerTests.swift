import XCTest
import SwiftUI
@testable import AnkountantTheme

@MainActor
final class ThemeManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-suite-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultValuesOnEmptyStore() {
        let manager = ThemeManager(defaults: defaults)
        XCTAssertEqual(manager.appearance, .system)
    }

    func testSettingAppearancePersistsAcrossInstances() {
        let m1 = ThemeManager(defaults: defaults)
        m1.appearance = .dark

        let m2 = ThemeManager(defaults: defaults)
        XCTAssertEqual(m2.appearance, .dark)
    }

    func testInvalidStoredValueFallsBackToDefault() {
        defaults.set("nonsense", forKey: "theme.appearance")

        let manager = ThemeManager(defaults: defaults)
        XCTAssertEqual(manager.appearance, .system)
    }

    func testPaletteForSystemSchemeFollowsSystem() {
        let manager = ThemeManager(defaults: defaults)
        manager.appearance = .system

        XCTAssertEqual(manager.palette(for: .light), .light)
        XCTAssertEqual(manager.palette(for: .dark), .dark)
    }

    func testPaletteForLightOverrideIgnoresSystem() {
        let manager = ThemeManager(defaults: defaults)
        manager.appearance = .light

        XCTAssertEqual(manager.palette(for: .light), .light)
        XCTAssertEqual(manager.palette(for: .dark), .light)
    }

    func testPaletteForDarkOverrideIgnoresSystem() {
        let manager = ThemeManager(defaults: defaults)
        manager.appearance = .dark

        XCTAssertEqual(manager.palette(for: .light), .dark)
        XCTAssertEqual(manager.palette(for: .dark), .dark)
    }
}
