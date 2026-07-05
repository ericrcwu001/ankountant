import AnkiClients
import AnkiKit
import AnkiServices
import Dependencies
import Sharing
import SwiftUI

private struct ReaderNotetypeOption: Identifiable, Equatable {
    let id: Int64
    let name: String
    let fieldNames: [String]
}

/// Picks the deck that holds books and maps notetype field names onto the
/// book/chapter shape the reader expects. Persists each value via
/// `@Shared(.appStorage)` so the library view sees changes immediately.
struct ReaderConfigurationView: View {
    let onDismiss: () -> Void

    @Dependency(\.deckClient) var deckClient
    @Dependency(\.notetypesService) var notetypesService

    @Shared(.appStorage(ReaderPreferenceKey.deckName)) private var deckName: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.notetypeID)) private var selectedNotetypeID: Int64 = 0
    @Shared(.appStorage(ReaderPreferenceKey.bookIDField)) private var bookIDField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.bookTitleField)) private var bookTitleField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.bookCoverField)) private var bookCoverField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.chapterTitleField)) private var chapterTitleField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.chapterOrderField)) private var chapterOrderField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.contentField)) private var contentField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.languageField)) private var languageField: String = ""

    @State private var decks: [DeckInfo] = []
    @State private var notetypeOptions: [ReaderNotetypeOption] = []
    @State private var isLoadingDecks = true
    @State private var isLoadingNotetypes = true
    @State private var loadError: String?
    @State private var notetypeLoadError: String?
    @State private var showCreateDeck = false
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

    var body: some View {
        Form {
            Section("Deck") {
                if isLoadingDecks {
                    HStack {
                        Spacer()
                        ProgressView("Loading decks…")
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Could Not Load Decks", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry") {
                            Task { await loadDecks() }
                        }
                    }
                } else if decks.isEmpty {
                    ContentUnavailableView {
                        Label("No Decks", systemImage: "rectangle.stack")
                    } description: {
                        Text("Create or import a deck before mapping reader fields.")
                    } actions: {
                        Button("Create deck", systemImage: "plus") {
                            showCreateDeck = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Import package", systemImage: "square.and.arrow.down") {
                            showImport = true
                        }
                    }
                } else {
                    Picker("Deck", selection: Binding($deckName)) {
                        Text("Select a deck").tag("")
                        ForEach(decks, id: \.id) { deck in
                            Text(deck.name).tag(deck.name)
                        }
                    }
                }
            }

            Section {
                if isLoadingNotetypes {
                    HStack {
                        Spacer()
                        ProgressView("Loading note types…")
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                } else if let notetypeLoadError {
                    ContentUnavailableView {
                        Label("Could Not Load Note Types", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(notetypeLoadError)
                    } actions: {
                        Button("Retry") {
                            Task { await loadNotetypes() }
                        }
                    }
                } else if notetypeOptions.isEmpty {
                    ContentUnavailableView {
                        Label("No Note Types", systemImage: "rectangle.stack")
                    } description: {
                        Text("Create or import a notetype before mapping reader fields.")
                    } actions: {
                        Button("Import package", systemImage: "square.and.arrow.down") {
                            showImport = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Picker("Note type", selection: Binding($selectedNotetypeID)) {
                        ForEach(notetypeOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                }
            } header: {
                Text("Note Type")
            } footer: {
                Text("Reader uses this note type when loading chapters, so field mappings stay unambiguous.")
            }

            Section {
                fieldPicker("Book ID", selection: Binding($bookIDField))
                fieldPicker("Book title", selection: Binding($bookTitleField))
                fieldPicker("Book cover", selection: Binding($bookCoverField), optional: true)
                fieldPicker("Chapter title", selection: Binding($chapterTitleField))
                fieldPicker("Chapter order", selection: Binding($chapterOrderField))
                fieldPicker("Content", selection: Binding($contentField))
                fieldPicker("Language", selection: Binding($languageField), optional: true)
            } header: {
                Text("Field mapping")
            } footer: {
                Text("Field names from the notetype that holds your book chapters. Each note becomes a chapter; chapters with the same Book ID collapse into one book.")
            }

        }
        .navigationTitle("Reader Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDismiss() }
            }
        }
        .sheet(isPresented: $showCreateDeck) {
            CreateDeckSheet {
                showCreateDeck = false
                Task { await loadDecks() }
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
        .task { await loadData() }
    }

    private var selectedFieldNames: [String] {
        notetypeOptions.first { $0.id == selectedNotetypeID }?.fieldNames ?? []
    }

    private func fieldPicker(_ title: String, selection: Binding<String>, optional: Bool = false) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection) {
                Text(optional ? "None" : "Select field").tag("")
                if !selection.wrappedValue.isEmpty,
                   !selectedFieldNames.contains(selection.wrappedValue) {
                    Text("Current: \(selection.wrappedValue)").tag(selection.wrappedValue)
                }
                ForEach(selectedFieldNames, id: \.self) { fieldName in
                    Text(fieldName).tag(fieldName)
                }
            }
            .labelsHidden()
            .disabled(selectedFieldNames.isEmpty)
        }
    }

    private func loadData() async {
        await loadDecks()
        await loadNotetypes()
    }

    private func loadDecks() async {
        isLoadingDecks = true
        loadError = nil
        defer { isLoadingDecks = false }

        do {
            decks = try deckClient.fetchAll().sorted { $0.name < $1.name }
        } catch {
            decks = []
            loadError = "Failed to load decks: \(error.localizedDescription)"
        }
    }

    private func loadNotetypes() async {
        isLoadingNotetypes = true
        notetypeLoadError = nil
        defer { isLoadingNotetypes = false }

        do {
            let entries = try notetypesService.getNotetypeNames()
            var options: [ReaderNotetypeOption] = []
            options.reserveCapacity(entries.count)
            for entry in entries {
                let notetype = try notetypesService.getNotetype(entry.id)
                options.append(
                    ReaderNotetypeOption(
                        id: entry.id,
                        name: entry.name,
                        fieldNames: notetype.fieldNames
                    )
                )
            }

            notetypeOptions = options.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            $selectedNotetypeID.withLock {
                $0 = resolvedSelectedNotetypeID(from: notetypeOptions) ?? 0
            }
        } catch {
            notetypeOptions = []
            $selectedNotetypeID.withLock { $0 = 0 }
            notetypeLoadError = "Failed to load note types: \(error.localizedDescription)"
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
            Task { @MainActor in
                do {
                    importMessage = try await ImportHelper.importPackageInBackground(from: url)
                    await loadData()
                } catch {
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
                showImportAlert = true
            }
        case .failure(let error):
            importMessage = "Could not select file: \(error.localizedDescription)"
            showImportAlert = true
        }
    }

    private func resolvedSelectedNotetypeID(from options: [ReaderNotetypeOption]) -> Int64? {
        if selectedNotetypeID != 0,
           options.contains(where: { $0.id == selectedNotetypeID }) {
            return selectedNotetypeID
        }

        let configuredRequiredFields = [
            bookIDField,
            bookTitleField,
            chapterTitleField,
            chapterOrderField,
            contentField,
        ].filter { !$0.isEmpty }

        if !configuredRequiredFields.isEmpty,
           let matchingOption = options.first(where: { option in
               Set(option.fieldNames).isSuperset(of: configuredRequiredFields)
           }) {
            return matchingOption.id
        }

        return options.first?.id
    }
}
