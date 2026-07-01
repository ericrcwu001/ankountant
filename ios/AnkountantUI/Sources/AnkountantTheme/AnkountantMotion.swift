public import SwiftUI

/// Motion durations from `design-tokens.json` → `motion.duration` (ms → s).
/// Callers should gate large motion behind `@Environment(\.accessibilityReduceMotion)`
/// via `AnkountantMotion.animation(_:reduceMotion:)`.
public enum AnkountantMotion {
    /// 100ms — reduced-motion / instant feedback.
    public static let instant: Duration = .milliseconds(100)
    /// 160ms — fast transitions.
    public static let fast: Duration = .milliseconds(160)
    /// 240ms — base transitions.
    public static let base: Duration = .milliseconds(240)
    /// 400ms — slow / hero transitions.
    public static let slow: Duration = .milliseconds(400)

    /// The iOS spring from the token set (`motion.easing.iosSpring`).
    public static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.9)

    /// Build an eased animation for the given duration, collapsing to a short
    /// opacity-friendly fade when Reduce Motion is enabled (per the token
    /// `motion.reducedMotion` rule).
    public static func animation(_ duration: Duration, reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: seconds(instant))
        }
        return .easeInOut(duration: seconds(duration))
    }

    private static func seconds(_ duration: Duration) -> Double {
        let comps = duration.components
        return Double(comps.seconds) + Double(comps.attoseconds) / 1e18
    }
}
