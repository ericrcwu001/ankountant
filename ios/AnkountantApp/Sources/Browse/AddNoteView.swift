import SwiftUI
import AnkiKit
import AnkiClients
import AnkiServices
import Dependencies

struct AddNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.notetypesService) var notetypesService
    @Dependency(\.notesService) var notesService

    @State private var decks: [DeckInfo] = []
    @State private var notetypeNames: [(id: Int64, name: String)] = []
    @State private var selectedDeckId: Int64 = 1
    @State private var selectedNotetypeId: Int64 = 0
    @State private var fieldNames: [String] = []
    @State private var fieldValues: [String] = []
    @State private var tags: String = ""
    @State private var isSaving = false
    @State private var loadErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showCreateDeck = false

    let preselectedDeckId: Int64?
    let initialDraft: AddNoteDraft?
    let onSave: () -> Void

    private static let noDecksMessage = "No decks are available."
    private static let noNotetypesMessage = "No note types are available."

    init(
        preselectedDeckId: Int64? = nil,
        initialDraft: AddNoteDraft? = nil,
        onSave: @escaping () -> Void
    ) {
        self.preselectedDeckId = preselectedDeckId ?? initialDraft?.deckID
        self.initialDraft = initialDraft
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deck") {
                    Picker("Deck", selection: $selectedDeckId) {
                        ForEach(decks) { deck in
                            Text(deck.name).tag(deck.id)
                        }
                    }
                }

                Section("Note Type") {
                    Picker("Type", selection: $selectedNotetypeId) {
                        ForEach(notetypeNames, id: \.id) { entry in
                            Text(entry.name).tag(entry.id)
                        }
                    }
                    .onChange(of: selectedNotetypeId) {
                        loadFields()
                    }
                }

                Section("Fields") {
                    ForEach(Array(fieldNames.enumerated()), id: \.offset) { index, name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            RichNoteFieldEditor(htmlText: fieldBinding(for: index))
                        }
                    }
                }

                Section("Tags") {
                    TextField("Tags (space-separated)", text: $tags)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let loadErrorMessage {
                    Section {
                        ContentUnavailableView {
                            Label("Could Not Load Note Form", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(loadErrorMessage)
                        } actions: {
                            Button("Retry") {
                                Task { await loadData() }
                            }
                            if loadErrorMessage == Self.noDecksMessage {
                                Button("Create deck", systemImage: "plus") {
                                    showCreateDeck = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            if localContentMissing {
                                Button("Import package", systemImage: "square.and.arrow.down") {
                                    showImport = true
                                }
                            }
                        }
                    }
                }

                if let saveErrorMessage {
                    Section {
                        Text(saveErrorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if let addRequirementMessage {
                    Section {
                        Text(addRequirementMessage)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(!canAddNote)
                    .accessibilityHint(addRequirementMessage ?? "")
                }
            }
            .task {
                await loadData()
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showCreateDeck) {
                CreateDeckSheet {
                    showCreateDeck = false
                    Task {
                        await loadData()
                        onSave()
                    }
                }
            }
            .alert("Import", isPresented: $showImportAlert) {
                Button("OK") {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private func fieldBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < fieldValues.count ? fieldValues[index] : "" },
            set: { newValue in
                if index < fieldValues.count { fieldValues[index] = newValue }
            }
        )
    }

    private var canAddNote: Bool {
        NoteFormRules.canAddNote(
            isSaving: isSaving,
            decks: decks,
            selectedDeckId: selectedDeckId,
            selectedNotetypeId: selectedNotetypeId,
            fieldValues: fieldValues,
            loadErrorMessage: loadErrorMessage
        )
    }

    private var addRequirementMessage: String? {
        NoteFormRules.addNoteRequirementMessage(
            isSaving: isSaving,
            decks: decks,
            selectedDeckId: selectedDeckId,
            selectedNotetypeId: selectedNotetypeId,
            fieldValues: fieldValues,
            loadErrorMessage: loadErrorMessage
        )
    }

    private var localContentMissing: Bool {
        loadErrorMessage == Self.noDecksMessage || loadErrorMessage == Self.noNotetypesMessage
    }

    private func loadData() async {
        loadErrorMessage = nil
        saveErrorMessage = nil

        if let initialDraft, !initialDraft.tags.isEmpty {
            tags = initialDraft.tags.joined(separator: " ")
        }

        do {
            decks = try deckClient.fetchAll()
            guard !decks.isEmpty else {
                loadErrorMessage = Self.noDecksMessage
                return
            }

            if let preselectedDeckId, decks.contains(where: { $0.id == preselectedDeckId }) {
                selectedDeckId = preselectedDeckId
            } else if let first = decks.first {
                selectedDeckId = first.id
            }

            notetypeNames = try notetypesService.getNotetypeNames()

            let chosen = initialDraft?.notetypeID
                .flatMap { id in notetypeNames.first(where: { $0.id == id }) }
                ?? notetypeNames.first

            guard let chosen else {
                loadErrorMessage = Self.noNotetypesMessage
                return
            }

            selectedNotetypeId = chosen.id
            try loadFields(for: chosen.id)
        } catch {
            fieldNames = []
            fieldValues = []
            loadErrorMessage = "Failed to load note form: \(error.localizedDescription)"
        }
    }

    private func loadFields() {
        guard selectedNotetypeId != 0 else { return }
        do {
            try loadFields(for: selectedNotetypeId)
            loadErrorMessage = nil
        } catch {
            fieldNames = []
            fieldValues = []
            loadErrorMessage = "Failed to load note fields: \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let ext = url.pathExtension.lowercased()
            guard ext == "apkg" || ext == "colpkg" else {
                importMessage = "Unsupported file type. Please select an .apkg or .colpkg file."
                showImportAlert = true
                return
            }
            do {
                importMessage = try ImportHelper.importPackage(from: url)
                Task {
                    await loadData()
                    onSave()
                }
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
            showImportAlert = true
        case .failure(let error):
            importMessage = "Could not select file: \(error.localizedDescription)"
            showImportAlert = true
        }
    }

    private func loadFields(for notetypeId: Int64) throws {
        let notetype = try notetypesService.getNotetype(notetypeId)
        fieldNames = notetype.fieldNames
        fieldValues = NoteFormRules.fieldValues(for: fieldNames, draft: initialDraft)
    }

    private func save() async {
        guard canAddNote else {
            saveErrorMessage = loadErrorMessage ?? addRequirementMessage ?? "Enter at least one field before adding."
            return
        }

        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        do {
            var template = try notesService.newNote(selectedNotetypeId)
            template.fields = fieldValues
            template.tags = NoteFormRules.normalizedTags(from: tags)
            try notesService.addNote(template, selectedDeckId)
            onSave()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to add note: \(error.localizedDescription)"
        }
    }
}
