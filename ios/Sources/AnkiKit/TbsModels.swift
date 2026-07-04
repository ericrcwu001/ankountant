// Domain types for the Ankountant "performance" surfaces (TBS + Confusion).
//
// These mirror the desktop Svelte model in
// ts/routes/(ankountant)/ankountant-tbs/lib.ts. Answer keys are NEVER carried
// here — grading is authoritative on the Rust side via SubmitPerformanceAttempt.
// Kept dependency-free (pure value types) so they are unit-testable via
// `swift test` and reusable across AnkiServices, AnkiClients, and the app.

/// The shape of a Task-Based Simulation, from the `tbs_type` note field.
/// Raw values match the strings stored in the "Ankountant TBS" note type.
public enum TbsShape: String, Sendable, Equatable, CaseIterable {
    case journalEntry = "journal_entry"
    case numeric = "numeric"
    case research = "research"
    case docReview = "doc_review"
}

/// A single typed reference exhibit shown alongside the task (mirrors the
/// desktop `Exhibit` in lib.ts and the Rust `SeedExhibit`). `role:"document"`
/// marks the doc-review primary document (its `body` carries `<blank step="id">`
/// markers); `kind:"table"` carries `columns`/`rows`.
public struct Exhibit: Sendable, Identifiable, Equatable {
    /// Positional identity for a stable SwiftUI `ForEach` (the JSON id is
    /// optional, so it can't be the identity).
    public let id: Int
    /// The exhibit's JSON id (e.g. "ex1", "doc"), used for role/ref matching.
    public let exhibitId: String?
    public let title: String
    /// Typed kind: text|email|invoice|table|statement|memo|document|stamp.
    public let kind: String
    /// `"document"` marks the doc-review primary document.
    public let role: String?
    public let body: String
    /// Column headers for `kind:"table"`.
    public let columns: [String]?
    /// Rows for `kind:"table"`.
    public let rows: [[String]]?

    public init(
        id: Int,
        title: String,
        body: String,
        exhibitId: String? = nil,
        kind: String = "text",
        role: String? = nil,
        columns: [String]? = nil,
        rows: [[String]]? = nil
    ) {
        self.id = id
        self.exhibitId = exhibitId
        self.title = title
        self.kind = kind
        self.role = role
        self.body = body
        self.columns = columns
        self.rows = rows
    }
}

/// A candidate option for a doc-review blank — label-stripped: nothing here
/// marks which option is correct (the key stays server-side, revealed only
/// post-submit).
public struct RenderOption: Sendable, Identifiable, Equatable {
    public let id: String
    public let text: String
    /// keep | delete | replace — drives the "Retain"/"Delete" labelling.
    public let kind: String

    public init(id: String, text: String, kind: String) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

/// A gradable step, WITHOUT its answer key (the key stays server-side and is
/// never rendered pre-submit). For a journal-entry step the client edits
/// account/side/amount cells; for numeric a single value cell; for a doc-review
/// blank a `Picker` of `options`; for research a citation input.
public struct RenderStep: Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let weight: Double
    /// Step kind (citation | blank | je | numeric); nil for legacy steps.
    public let kind: String?
    /// doc-review blank candidates (label-stripped; no option marks the key).
    public let options: [RenderOption]
    /// doc-review blank's original document text (safe to show pre-submit).
    public let originalText: String?
    /// research hint: which bundled corpus passages back the answer.
    public let corpusRefs: [String]
    /// research citation input hint (e.g. "ASC ###-##-##-#").
    public let placeholder: String?

    public init(
        id: String,
        label: String,
        weight: Double,
        kind: String? = nil,
        options: [RenderOption] = [],
        originalText: String? = nil,
        corpusRefs: [String] = [],
        placeholder: String? = nil
    ) {
        self.id = id
        self.label = label
        self.weight = weight
        self.kind = kind
        self.options = options
        self.originalText = originalText
        self.corpusRefs = corpusRefs
        self.placeholder = placeholder
    }
}

/// The full client render model for a TBS note (section-agnostic, ADR 0008).
public struct TbsModel: Sendable, Equatable {
    public let shape: TbsShape
    /// CPA section (AUD/FAR/REG/BAR/ISC/TCP), from the note's `sec::` tag.
    public let section: String
    public let prompt: String
    public let exhibits: [Exhibit]
    public let steps: [RenderStep]
    /// doc-review only: the primary document body (with `<blank>` markers).
    public let document: String?

    public init(
        shape: TbsShape,
        prompt: String,
        exhibits: [Exhibit],
        steps: [RenderStep],
        section: String = "FAR",
        document: String? = nil
    ) {
        self.shape = shape
        self.section = section
        self.prompt = prompt
        self.exhibits = exhibits
        self.steps = steps
        self.document = document
    }
}

/// A parsed segment of a doc-review primary document: literal `text`, or a
/// `blank` referencing a step id (the `<blank step="id">original</blank>`
/// marker). Mirrors the desktop `DocSegment` union in lib.ts.
public enum DocSegment: Sendable, Equatable, Identifiable {
    case text(key: String, text: String)
    case blank(key: String, blankId: String, original: String)

    public var id: String {
        switch self {
        case let .text(key, _): key
        case let .blank(key, _, _): key
        }
    }
}

/// One journal-entry line as edited in the grid (mutable for SwiftUI binding).
public struct JeLineInput: Sendable, Identifiable, Equatable {
    public let id: String
    public var label: String?
    public var account: String
    public var side: String
    public var amount: String
    public var noEntry: Bool

    public init(id: String, label: String? = nil, account: String = "", side: String = "", amount: String = "", noEntry: Bool = false) {
        self.id = id
        self.label = label
        self.account = account
        self.side = side
        self.amount = amount
        self.noEntry = noEntry
    }
}

public let journalEntryAccounts: [String] = [
    "Cash",
    "Accounts Receivable",
    "Allowance for Doubtful Accounts",
    "Inventory",
    "Prepaid Expenses",
    "Land",
    "Building",
    "Equipment",
    "ROU Asset",
    "Right-of-Use Asset",
    "Accumulated Depreciation",
    "Patent",
    "Accounts Payable",
    "Lease Liability",
    "Bonds Payable",
    "Discount on Bonds Payable",
    "Deferred Tax Liability",
    "Income Tax Payable",
    "Common Stock",
    "Common Stock Dividend Distributable",
    "Additional Paid-in Capital",
    "Retained Earnings",
    "Treasury Stock",
    "Unrealized Holding Gain - Income",
    "Unrealized Holding Gain - OCI",
    "Fair Value Adjustment - Trading",
    "Fair Value Adjustment (AFS)",
    "Interest Expense",
    "Income Tax Expense",
    "Repairs and Maintenance Expense",
    "Research and Development Expense",
    "Loss on Sale of A/R",
    "COGS",
]

/// One numeric cell as edited (mutable for SwiftUI binding).
public struct NumericCellInput: Sendable, Identifiable, Equatable {
    public let id: String
    public var value: String

    public init(id: String, value: String = "") {
        self.id = id
        self.value = value
    }
}

/// One doc-review blank as edited (mutable for SwiftUI binding). `selection` is
/// the chosen option id; `""` means unselected (submitted as empty → graded
/// incorrect, matching the exam rule that a blank must be answered).
public struct DocReviewBlankInput: Sendable, Identifiable, Equatable {
    public let id: String
    public var selection: String

    public init(id: String, selection: String = "") {
        self.id = id
        self.selection = selection
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

public struct StepReveal: Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let correctText: String

    public init(id: String, label: String, correctText: String) {
        self.id = id
        self.label = label
        self.correctText = correctText
    }
}

public struct TbsRevealModel: Sendable, Equatable {
    public let steps: [StepReveal]
    public let source: String
    public let section: String
    public let schemaTag: String

    public init(steps: [StepReveal], source: String, section: String, schemaTag: String) {
        self.steps = steps
        self.source = source
        self.section = section
        self.schemaTag = schemaTag
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

public struct ConfusionRevealModel: Sendable, Equatable {
    public let correctText: String
    public let source: String
    public let schemaTag: String
    public let setId: String

    public init(correctText: String, source: String, schemaTag: String, setId: String) {
        self.correctText = correctText
        self.source = source
        self.schemaTag = schemaTag
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
    public let section: String
    public let prompt: String

    public var id: Int64 { noteId }

    public init(noteId: Int64, shape: TbsShape, prompt: String, section: String = "FAR") {
        self.noteId = noteId
        self.shape = shape
        self.section = section
        self.prompt = prompt
    }
}
