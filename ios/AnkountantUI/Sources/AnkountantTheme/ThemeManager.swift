public import Foundation
public import SwiftUI

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .ankountantAppGroup) {
        self.defaults = defaults
        let storedAppearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:))
        self.appearance = storedAppearance ?? .system
    }

    public func palette(for systemScheme: ColorScheme) -> Palette {
        let resolved: ColorScheme
        switch appearance {
        case .system: resolved = systemScheme
        case .light: resolved = .light
        case .dark: resolved = .dark
        }
        return Palette.resolve(scheme: resolved)
    }

    private enum Keys {
        static let appearance = "theme.appearance"
    }
}
