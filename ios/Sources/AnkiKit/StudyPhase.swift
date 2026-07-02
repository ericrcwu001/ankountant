/// The study "phase" that drives the Home screen's primary call-to-action. The
/// single dial is days-to-exam (brainlift SPOV 1): effortful discrimination far
/// from the exam, consolidation in the final stretch — with a beginner override
/// so a student with no memory base gets a blocked recall intro first (SPOV 3
/// boundary / worked-example effect). Mirrors the desktop TypeScript `choosePhase`
/// in `ts/routes/(ankountant)/ankountant-home/lib.ts`.
public enum StudyPhase: String, Sendable, Equatable, CaseIterable {
    case foundation
    case discrimination
    case consolidation
}

/// Cross-view signal that the FAR demo profile was reseeded. The Debug screen's
/// "demo phases" actions bump this `@Shared(.appStorage)` counter after they
/// reseed; `HomeView` observes it via `.task(id:)` and reloads, so a phase
/// change is reflected even though Home lives in a different tab and stays alive
/// in the background (its one-shot `.task` would otherwise never re-run).
public enum DemoSeed {
    public static let versionKey = "ankountant.demoSeedVersion"
}

/// Final-stretch window (days). Sits below the backend's 60-day ramp horizon
/// (rslib `RAMP_HORIZON_DAYS`, where desired retention climbs toward its peak);
/// tunable.
public let consolidationWindowDays = 14

/// Pick the study phase from days-to-exam plus whether the student has any
/// memory base yet. No base → foundation (blocked recall), regardless of date;
/// inside the final stretch → consolidation; otherwise the core primitive,
/// discrimination (confusion set).
public func choosePhase(daysUntilExam days: Int?, memoryReady: Bool) -> StudyPhase {
    if !memoryReady {
        return .foundation
    }
    if let days, days >= 0, days <= consolidationWindowDays {
        return .consolidation
    }
    return .discrimination
}

/// View-model for the phase-aware primary button (dynamic label + subtitle).
public struct PhaseCta: Sendable, Equatable {
    /// Which study surface the button opens.
    public enum Target: Sendable, Equatable {
        case recall
        case confusion
    }

    public let phase: StudyPhase
    public let label: String
    public let subtitle: String
    public let target: Target

    public init(phase: StudyPhase, label: String, subtitle: String, target: Target) {
        self.phase = phase
        self.label = label
        self.subtitle = subtitle
        self.target = target
    }
}

public func buildPhaseCta(_ phase: StudyPhase) -> PhaseCta {
    switch phase {
    case .foundation:
        PhaseCta(
            phase: .foundation,
            label: "Build foundation",
            subtitle: "Blocked recall — learn the material first",
            target: .recall
        )
    case .consolidation:
        PhaseCta(
            phase: .consolidation,
            label: "Consolidate",
            subtitle: "Lock in recall to peak on exam day",
            target: .recall
        )
    case .discrimination:
        PhaseCta(
            phase: .discrimination,
            label: "Discrimination drill",
            subtitle: "Interleaved which-treatment practice",
            target: .confusion
        )
    }
}
