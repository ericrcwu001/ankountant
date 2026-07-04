import SwiftUI
import Testing
@testable import AnkountantApp

@Suite("Review toolbar chrome")
struct ReviewToolbarChromeTests {
    @Test func disabledAutoMatchUsesSystemToolbarScheme() {
        #expect(reviewToolbarColorScheme(autoMatchCardBackground: false, cardChromeIsDark: false) == nil)
        #expect(reviewToolbarColorScheme(autoMatchCardBackground: false, cardChromeIsDark: true) == nil)
    }

    @Test func enabledAutoMatchUsesCardBackgroundDarkness() {
        #expect(reviewToolbarColorScheme(autoMatchCardBackground: true, cardChromeIsDark: false) == .light)
        #expect(reviewToolbarColorScheme(autoMatchCardBackground: true, cardChromeIsDark: true) == .dark)
    }
}
