// Domain types for the Ankountant "performance" surfaces (TBS + Confusion).
//
// These mirror the desktop Svelte model in
// ts/routes/(ankountant)/ankountant-tbs/lib.ts. Answer keys are NEVER carried
// here — grading is authoritative on the Rust side via SubmitPerformanceAttempt.
// Kept dependency-free (pure value types) so they are unit-testable via
// `swift test` and reusable across AnkiServices, AnkiClients, and the app.

/// The shape of a Task-Based Simulation, from the `tbs_type` note field.
/// Raw values match the strings stored in the "Ankountant TBS" note type.
public enum TbsShape: String, Sendable, Equatable {
    case journalEntry = "journal_entry"
    case numeric = "numeric"
    case research = "research"
    case docReview = "doc_review"
}

/// A single reference exhibit shown alongside the task.
public struct Exhibit: Sendable, Identifiable, Equatable {
    public let id: Int
    public let title: String
    public let body: String

    public init(id: Int, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// A gradable step, WITHOUT its answer key (the key stays server-side and is
/// never rendered). For a journal-entry step the client edits account/side/
/// amount cells; for a numeric step, a single value cell.
public struct RenderStep: Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let weight: Double

    public init(id: String, label: String, weight: Double) {
        self.id = id
        self.label = label
        self.weight = weight
    }
}

/// The full client render model for a TBS note.
public struct TbsModel: Sendable, Equatable {
    public let shape: TbsShape
    public let prompt: String
    public let exhibits: [Exhibit]
    public let steps: [RenderStep]

    public init(shape: TbsShape, prompt: String, exhibits: [Exhibit], steps: [RenderStep]) {
        self.shape = shape
        self.prompt = prompt
        self.exhibits = exhibits
        self.steps = steps
    }
}

/// One journal-entry line as edited in the grid (mutable for SwiftUI binding).
public struct JeLineInput: Sendable, Identifiable, Equatable {
    public let id: String
    public var account: String
    public var side: String
    public var amount: String

    public init(id: String, account: String = "", side: String = "", amount: String = "") {
        self.id = id
        self.account = account
        self.side = side
        self.amount = amount
    }
}

/// One numeric cell as edited (mutable for SwiftUI binding).
public struct NumericCellInput: Sendable, Identifiable, Equatable {
    public let id: String
    public var value: String

    public init(id: String, value: String = "") {
        self.id = id
        self.value = value
    }
}

/// The graded outcome of a single step, returned by SubmitPerformanceAttempt.
public struct PerformanceStepResult: Sendable, Identifiable, Equatable {
    public let id: String
    public let correct: Bool
    public let weight: Double

    public init(id: String, correct: Bool, weight: Double) {
        self.id = id
        self.correct = correct
        self.weight = weight
    }
}

/// The graded outcome of an attempt: per-step results plus the total credit
/// fraction (0.0...1.0) and the id of the persisted Attempt Log note.
public struct PerformanceAttemptResult: Sendable, Equatable {
    public let steps: [PerformanceStepResult]
    public let totalCredit: Double
    public let attemptNoteId: Int64

    public init(steps: [PerformanceStepResult], totalCredit: Double, attemptNoteId: Int64) {
        self.steps = steps
        self.totalCredit = totalCredit
        self.attemptNoteId = attemptNoteId
    }
}

/// A single confusion-set discrimination item. Deliberately label-stripped: no
/// topic/category/deck label, so the learner discriminates on content.
public struct ConfusionItemModel: Sendable, Identifiable, Equatable {
    public let noteId: Int64
    public let prompt: String
    public let treatments: [String]
    public let setId: String

    public var id: Int64 { noteId }

    public init(noteId: Int64, prompt: String, treatments: [String], setId: String) {
        self.noteId = noteId
        self.prompt = prompt
        self.treatments = treatments
        self.setId = setId
    }
}

/// The three discrete pre-reveal confidence levels (B1 confidence gate).
public enum ConfidenceLevel: String, Sendable, CaseIterable, Equatable {
    case guess = "Guess"
    case unsure = "Unsure"
    case confident = "Confident"
}

/// A lightweight summary of a sealed TBS note, used to populate the task list
/// without loading the full render model up front.
public struct TbsTaskSummary: Sendable, Identifiable, Equatable {
    public let noteId: Int64
    public let shape: TbsShape
    public let prompt: String

    public var id: Int64 { noteId }

    public init(noteId: Int64, shape: TbsShape, prompt: String) {
        self.noteId = noteId
        self.shape = shape
        self.prompt = prompt
    }
}
