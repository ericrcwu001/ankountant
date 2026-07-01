public import CoreGraphics

/// Corner-radius scale from `design-tokens.json` → `radius`.
/// Buttons/inputs use `control` (8). `pill` is for status chips only.
public enum AnkountantRadius {
    public static let inner: CGFloat = 6
    public static let control: CGFloat = 8
    public static let card: CGFloat = 12
    public static let container: CGFloat = 16
    /// Sentinel for a fully-rounded (Capsule-equivalent) corner.
    public static let pill: CGFloat = 9999
}
