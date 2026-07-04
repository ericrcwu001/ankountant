import SwiftUI
import AnkiKit
import AnkiClients
import AnkiServices
import Dependencies
import AnkountantTheme

enum BrowseSortOrder: String, CaseIterable, Sendable {
    case dateDesc = "Date (newest)"
    case titleAsc = "Title (A→Z)"
    case templateAsc = "Type (A→Z)"
}

struct BrowseView: View {
    @Dependency(\.noteClient) var noteClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.tagClient) var tagClient
    @Dependency(\.notetypesService) var notetypesService

    @State private var searchText = ""
    @State private var allNotes: [NoteRecord] = []
    @State private var notes: [NoteRecord] = []
    @State private var allDecks: [DeckInfo] = []
    /// The top-level parent deck selected (stays set even when drilling into subdecks)
    @State private var parentDeck: DeckInfo?
    /// The actual deck filter applied (could be parent or a subdeck)
    @State private var activeDeck: DeckInfo?
    @State private var isLoading = false
    @State private var hasMorePages = true
    @State private var showAddNote = false
    @State private var showAddImageOcclusion = false
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var selectionState = BrowseSelectionState()
    @State private var showTagSheet = false
    @State private var showDeleteConfirm = false
    @State private var pendingSwipeDelete: NoteRecord?
    @State private var allTags: [String] = []
    @State private var activeTag: String?
    @State private var sortOrder: BrowseSortOrder = .dateDesc
    @State private var notetypeNames: [Int64: String] = [:]
    @State private var actionErrorMessage: String?
    @State private var searchGeneration = 0

    private let pageSize = 50

    private var deleteSelectionTitle: String {
        let count = selectionState.count
        let suffix = count == 1 ? "" : "s"
        return "Delete \(count) note\(suffix)?"
    }

    private var hasActiveFilter: Bool {
        activeDeck != nil || activeTag != nil
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var activeFilterDescription: String {
        switch (activeDeck?.name, activeTag) {
        case (.some(let deck), .some(let tag)):
            return "No notes match deck \"\(deck)\" and tag \"\(tag)\"."
        case (.some(let deck), .none):
            return "No notes are in \"\(deck)\" yet."
        case (.none, .some(let tag)):
            return "No notes are tagged \"\(tag)\" yet."
        case (.none, .none):
            return "No notes match the current filters."
        }
    }

    var body: some View {
        content
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.inline)
        .ankountantTabBarClearance()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Add Note") { showAddNote = true }
                    Button("Add Image Occlusion") { showAddImageOcclusion = true }
                } label: {
                    Label("Add note", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(BrowseSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            if sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort notes", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .disabled(notes.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if selectionState.isSelectMode {
                    Button("Done") {
                        selectionState.exitSelectMode()
                    }
                } else if !notes.isEmpty {
                    Button("Edit") {
                        selectionState.enterSelectMode()
                    }
                }
            }
            if selectionState.isSelectMode {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        suspendSelected()
                    } label: {
                        Label("Suspend", systemImage: "pause.circle")
                    }
                    .disabled(selectionState.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button { flagSelected(1) } label: { Label("Red flag",       systemImage: "flag.fill") }
                        Button { flagSelected(2) } label: { Label("Orange flag",    systemImage: "flag.fill") }
                        Button { flagSelected(3) } label: { Label("Green flag",     systemImage: "flag.fill") }
                        Button { flagSelected(4) } label: { Label("Blue flag",      systemImage: "flag.fill") }
                        Button { flagSelected(5) } label: { Label("Pink flag",      systemImage: "flag.fill") }
                        Button { flagSelected(6) } label: { Label("Turquoise flag", systemImage: "flag.fill") }
                        Button { flagSelected(7) } label: { Label("Purple flag",    systemImage: "flag.fill") }
                        Divider()
                        Button { flagSelected(0) } label: { Label("Clear flag",     systemImage: "flag.slash") }
                    } label: {
                        Label("Flag", systemImage: "flag")
                    }
                    .disabled(selectionState.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showTagSheet = true
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }
                    .disabled(selectionState.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectionState.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteView {
                Task { await performSearch() }
            }
        }
        .sheet(isPresented: $showAddImageOcclusion) {
            AddImageOcclusionNoteView { Task { await performSearch() } }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
        .sheet(isPresented: $showTagSheet) {
            BatchTagSheet(noteIDs: selectionState.selectedNoteIDs) {
                Task {
                    await MainActor.run {
                        selectionState.exitSelectMode()
                    }
                    await performSearch()
                }
            }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { pendingSwipeDelete != nil },
                set: { if !$0 { pendingSwipeDelete = nil } }
            ),
            presenting: pendingSwipeDelete
        ) { note in
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    do {
                        try noteClient.delete(note.id)
                    } catch {
                        actionErrorMessage = "Failed to delete note: \(error.localizedDescription)"
                        return
                    }
                    pendingSwipeDelete = nil
                    await performSearch()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSwipeDelete = nil
            }
        } message: { _ in
            Text("This action cannot be undone.")
        }
        .confirmationDialog(
            deleteSelectionTitle,
            isPresented: $showDeleteConfirm
        ) {
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Browse action failed",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            ),
            presenting: actionErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .safeAreaInset(edge: .top) {
            if !allDecks.isEmpty || !allTags.isEmpty {
                filterBar
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes...")
        .onChange(of: searchText) {
            Task { await performSearch() }
        }
        .onChange(of: activeDeck) {
            Task { await performSearch() }
        }
        .onChange(of: activeTag) {
            Task { await performSearch() }
        }
        .task {
            await loadDecks()
            await performSearch()
            loadTags()
            loadNotetypeNames()
        }
    }

    @ViewBuilder
    private var content: some View {
        if notes.isEmpty && !isLoading && trimmedSearchText.isEmpty && !hasActiveFilter {
            emptyCollectionState
        } else if notes.isEmpty && !isLoading && trimmedSearchText.isEmpty && hasActiveFilter {
            filteredEmptyState
        } else if notes.isEmpty && !isLoading {
            ContentUnavailableView.search(text: searchText)
        } else {
            notesList
        }
    }

    private var emptyCollectionState: some View {
        ContentUnavailableView {
            Label("No notes yet", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Add a note or import an Anki package to start browsing your collection.")
        } actions: {
            Button("Add Note", systemImage: "plus") {
                showAddNote = true
            }
            .buttonStyle(.borderedProminent)

            Button("Import package", systemImage: "square.and.arrow.down") {
                showImport = true
            }
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No notes in this filter", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(activeFilterDescription)
        } actions: {
            Button("Clear Filters") {
                parentDeck = nil
                activeDeck = nil
                activeTag = nil
            }
            .buttonStyle(.borderedProminent)

            Button("Add Note", systemImage: "plus") {
                showAddNote = true
            }

            Button("Import package", systemImage: "square.and.arrow.down") {
                showImport = true
            }
        }
    }

    private var notesList: some View {
        List {
            ForEach(sortedNotes(notes), id: \.id) { note in
                noteRow(note)
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationDestination(for: NoteRecord.self) { note in
            BrowseNoteDestinationView(note: note) {
                Task { await performSearch() }
            }
        }
    }

    private func noteRow(_ note: NoteRecord) -> some View {
        BrowseNoteListRow(
            note: note,
            notetypeName: notetypeNames[note.mid],
            selectionState: $selectionState,
            onRowAppear: noteAppeared,
            onRefresh: {
                Task { await performSearch() }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingSwipeDelete = note
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Sort

    private func sortedNotes(_ notes: [NoteRecord]) -> [NoteRecord] {
        switch sortOrder {
        case .dateDesc:
            return notes.sorted { $0.mod > $1.mod }
        case .titleAsc:
            return notes.sorted { $0.sfld.localizedCaseInsensitiveCompare($1.sfld) == .orderedAscending }
        case .templateAsc:
            return notes.sorted { (notetypeNames[$0.mid] ?? "") < (notetypeNames[$1.mid] ?? "") }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            if !allDecks.isEmpty {
                deckFilterBar
            }
            if !allTags.isEmpty {
                tagChipRow
            }
        }
    }

    private var tagChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", isSelected: activeTag == nil) {
                    activeTag = nil
                }
                ForEach(allTags, id: \.self) { tag in
                    chipButton(label: tag, isSelected: activeTag == tag) {
                        activeTag = (activeTag == tag) ? nil : tag
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Deck Filter

    private var topLevelDecks: [DeckInfo] {
        allDecks.filter { !$0.name.contains("::") }
    }

    /// Direct children of the parent deck (shown as second row)
    private var childDecks: [DeckInfo] {
        guard let parent = parentDeck else { return [] }
        let prefix = parent.name + "::"
        return allDecks.filter { deck in
            guard deck.name.hasPrefix(prefix) else { return false }
            let remainder = deck.name.dropFirst(prefix.count)
            return !remainder.contains("::")
        }
    }

    private var deckFilterBar: some View {
        VStack(spacing: 0) {
            // Top-level deck chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipButton(label: "All", isSelected: activeDeck == nil) {
                        parentDeck = nil
                        activeDeck = nil
                    }
                    ForEach(topLevelDecks) { deck in
                        chipButton(
                            label: deck.name,
                            isSelected: parentDeck?.id == deck.id && activeDeck?.id == deck.id
                        ) {
                            parentDeck = deck
                            activeDeck = deck
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Subdeck row — stays visible as long as a parent with children is selected
            if !childDecks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "All" chip = parent deck (includes subdecks)
                        chipButton(
                            label: "All",
                            isSelected: activeDeck?.id == parentDeck?.id,
                            small: true
                        ) {
                            activeDeck = parentDeck
                        }
                        ForEach(childDecks) { child in
                            chipButton(
                                label: shortName(child.name),
                                isSelected: activeDeck?.id == child.id,
                                small: true
                            ) {
                                activeDeck = child
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(.bar)
    }

    private func chipButton(
        label: String,
        isSelected: Bool,
        small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(small ? .caption : .subheadline)
                .padding(.horizontal, small ? 10 : 12)
                .padding(.vertical, small ? 4 : 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func shortName(_ fullName: String) -> String {
        String(fullName.split(separator: "::").last ?? Substring(fullName))
    }

    // MARK: - Data Loading

    private func loadDecks() async {
        do {
            allDecks = try deckClient.fetchAll()
        } catch {
            allDecks = []
            actionErrorMessage = "Failed to load deck filters: \(error.localizedDescription)"
        }
    }

    private func loadTags() {
        do {
            allTags = try tagClient.getAllTags().sorted()
        } catch {
            allTags = []
            actionErrorMessage = "Failed to load tags: \(error.localizedDescription)"
        }
    }

    private func loadNotetypeNames() {
        do {
            let pairs = try notetypesService.getNotetypeNames()
            notetypeNames = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0.name) })
        } catch {
            notetypeNames = [:]
            actionErrorMessage = "Failed to load note type names: \(error.localizedDescription)"
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
                    await loadDecks()
                    await performSearch()
                    loadTags()
                    loadNotetypeNames()
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

    private func noteAppeared(_ note: NoteRecord) {
        if note.sfld == "Loading..." {
            Task { @MainActor in
                await fetchNoteDetails(id: note.id)
            }
        }

        if note.id == notes.last?.id {
            Task { @MainActor in
                await loadNextPage()
            }
        }
    }

    private func performSearch() async {
        searchGeneration += 1
        let generation = searchGeneration
        isLoading = true
        defer {
            if generation == searchGeneration {
                isLoading = false
            }
        }

        let query = buildQuery()
        do {
            let results = try noteClient.search(query, nil)
            guard generation == searchGeneration else { return }
            allNotes = results
            notes = Array(results.prefix(pageSize))
            hasMorePages = results.count > pageSize
        } catch {
            guard generation == searchGeneration else { return }
            allNotes = []
            notes = []
            hasMorePages = false
            actionErrorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    private func collectCardIDs(for noteIDs: Set<Int64>) throws -> [Int64] {
        var result: [Int64] = []
        for nid in noteIDs {
            let cards = try cardClient.fetchByNote(nid)
            result.append(contentsOf: cards.map(\.id))
        }
        return result
    }

    private func suspendSelected() {
        let ids = selectionState.selectedNoteIDs
        Task { @MainActor in
            do {
                let cardIDs = try collectCardIDs(for: ids)
                for id in cardIDs {
                    try cardClient.suspend(id)
                }
                selectionState.exitSelectMode()
                await performSearch()
            } catch {
                actionErrorMessage = "Suspend failed: \(error.localizedDescription)"
            }
        }
    }

    private func flagSelected(_ value: UInt32) {
        let ids = selectionState.selectedNoteIDs
        Task { @MainActor in
            do {
                let cardIDs = try collectCardIDs(for: ids)
                for id in cardIDs {
                    try cardClient.flag(id, value)
                }
                selectionState.exitSelectMode()
                await performSearch()
            } catch {
                actionErrorMessage = "Flag failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteSelected() {
        let ids = selectionState.selectedNoteIDs
        Task { @MainActor in
            do {
                for id in ids {
                    try noteClient.delete(id)
                }
                selectionState.exitSelectMode()
                await performSearch()
            } catch {
                actionErrorMessage = "Delete failed: \(error.localizedDescription)"
                await performSearch()
            }
        }
    }

    private func loadNextPage() async {
        guard hasMorePages, !isLoading else { return }
        let loaded = notes.count
        let nextBatch = Array(allNotes.dropFirst(loaded).prefix(pageSize))
        notes.append(contentsOf: nextBatch)
        hasMorePages = notes.count < allNotes.count
    }

    /// Lazy-fetch full note details for a stub and update the arrays in place.
    private func fetchNoteDetails(id: Int64) async {
        do {
            guard let fullNote = try noteClient.fetch(id) else {
                actionErrorMessage = "Could not load note details."
                return
            }
            if let idx = notes.firstIndex(where: { $0.id == id }) {
                notes[idx] = fullNote
            }
            if let idx = allNotes.firstIndex(where: { $0.id == id }) {
                allNotes[idx] = fullNote
            }
        } catch {
            actionErrorMessage = "Failed to load note details: \(error.localizedDescription)"
        }
    }

    private func buildQuery() -> String {
        var parts: [String] = []
        if let deck = activeDeck {
            parts.append("deck:\"\(deck.name)\"")
        }
        if let tag = activeTag {
            parts.append("tag:\"\(tag)\"")
        }
        if !trimmedSearchText.isEmpty {
            parts.append(trimmedSearchText)
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - NoteContextMenuButton

/// Resolves the first cardId for a note lazily on first appear, then shows CardContextMenu.
@MainActor
struct NoteContextMenuButton: View {
    let noteId: Int64
    var onSuccess: (() -> Void)?

    @Dependency(\.cardClient) var cardClient
    @State private var firstCardId: Int64?
    @State private var cardActionError: String?
    @State private var showCardActionError = false

    var body: some View {
        Group {
            if let cardId = firstCardId {
                CardContextMenu(
                    cardId: cardId,
                    noteId: noteId,
                    onSuccess: onSuccess
                )
            } else if cardActionError != nil {
                Button {
                    showCardActionError = true
                } label: {
                    Image(systemName: "exclamationmark.circle")
                        .ankountantFont(.bodyEmphasis)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Card actions unavailable")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading card actions")
            }
        }
        .alert("Card actions unavailable", isPresented: $showCardActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cardActionError ?? "Unable to load card actions for this note.")
        }
        .task(id: noteId) {
            firstCardId = nil
            cardActionError = nil
            showCardActionError = false
            do {
                let cards = try cardClient.fetchByNote(noteId)
                guard let firstCard = cards.first else {
                    cardActionError = "This note has no cards."
                    return
                }
                firstCardId = firstCard.id
            } catch {
                cardActionError = "Failed to load card actions: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - NoteRowView

struct NoteRowView: View {
    let note: NoteRecord
    let notetypeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.sfld)
                .font(.body)
                .lineLimit(1)
            if let subtitle = composeNoteSubtitle(notetypeName: notetypeName, tags: note.tags) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
    }
}
