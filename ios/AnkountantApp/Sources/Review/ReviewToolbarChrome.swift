import SwiftUI

func reviewToolbarColorScheme(
    autoMatchCardBackground: Bool,
    cardChromeIsDark: Bool
) -> ColorScheme? {
    guard autoMatchCardBackground else { return nil }
    return cardChromeIsDark ? .dark : .light
}
