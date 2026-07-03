// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

/// The CPA exam sections, as a stable value type shared by the summit Home range,
/// the per-section detail, and navigation. `rawValue` is the exact string every
/// backend RPC and `sec::` tag uses (`getReadiness(section)`, `examConfigClient`,
/// `buildConfusionQueue`), so no conversion is ever needed.
///
/// Case order mirrors the Rust `SECTIONS` / `AnkiKit.TBS_SECTIONS` list (all six)
/// for parity. The Home summit shows only `homeOrder` (five — BAR, the discipline
/// the candidate did not pick, is intentionally omitted).
public enum CPASection: String, Sendable, Hashable, CaseIterable, Identifiable {
    case aud = "AUD"
    case far = "FAR"
    case reg = "REG"
    case bar = "BAR"
    case isc = "ISC"
    case tcp = "TCP"

    public var id: String { rawValue }

    /// The backend/tag string for this section (identical to `rawValue`).
    public var code: String { rawValue }

    /// Full AICPA section name for headers and accessibility labels.
    public var displayName: String {
        switch self {
        case .far: "Financial Accounting and Reporting"
        case .aud: "Auditing and Attestation"
        case .reg: "Regulation"
        case .tcp: "Tax Compliance and Planning"
        case .isc: "Information Systems and Controls"
        case .bar: "Business Analysis and Reporting"
        }
    }

    /// The five peaks shown on the Home summit, FAR first. BAR excluded by design.
    public static let homeOrder: [CPASection] = [.far, .aud, .reg, .tcp, .isc]

    /// Build from a backend/tag string; unknown codes return nil (callers may
    /// fall back to `.far`).
    public init?(code: String) {
        self.init(rawValue: code)
    }
}
