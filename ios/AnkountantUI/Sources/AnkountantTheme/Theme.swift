/// Appearance override for the single-identity Ledger theme. The visual
/// identity no longer has variants (the beige "muted" theme was retired); only
/// the light/dark scheme is selectable, and the palette is resolved from the
/// resulting `ColorScheme`.
public enum Appearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}
