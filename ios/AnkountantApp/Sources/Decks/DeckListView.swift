import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import Dependencies

struct DeckListView: View {
    /// Optional hero rendered as the first list section (the Ankountant Home
    /// hub injects its countdown/readiness widgets here so they scroll with the
    /// deck list). `nil` renders the plain deck list.
    var header: AnyView? = nil
    /// Extra work run before the deck reload on pull-to-refresh (the Home hub
    /// chains its readiness reload here so both refresh together).
    var onAdditionalRefresh: (() async -> Void)? = nil
    /// Reload identity: bump to force a deck-tree reload (e.g. after a demo
    /// reseed, so the deck list doesn't go stale while the hero updates).
    var reloadID: Int = 0
    var navigationTitle: String = "Decks"

    @Dependency(\.deckClient) var deckClient
    @State private var tree: [DeckTreeNode] = []
    @State private var isLoading = true
    @State private var showCreateSheet = false

    var body: some View {
        List {
            if let header {
                Section {
                    header
                }
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if tree.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Decks",
                        systemImage: "rectangle.stack",
                        description: Text("Sync with your server to get your decks.")
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    DecksReviewsChart()
                        .listRowInsets(.init(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    NavigationLink {
                        SimulationsHubView()
                    } label: {
                        Label("Simulations", systemImage: "list.bullet.clipboard")
                    }
                }
                ForEach(tree) { node in
                    DeckRowView(node: node, onMutated: {
                        await loadDecks()
                    })
                }
            }
        }
        .navigationDestination(for: DeckInfo.self) { deck in
            DeckDetailView(deck: deck)
        }
        .scrollContentBackground(.hidden)
        .ankountantSectionBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(navigationTitle.isEmpty ? .inline : .automatic)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateDeckSheet {
                showCreateSheet = false
                Task { await loadDecks() }
            }
        }
        .task(id: reloadID) {
            await loadDecks()
        }
        .refreshable {
            await onAdditionalRefresh?()
            await loadDecks()
        }
    }

    private func loadDecks() async {
        do {
            tree = try deckClient.fetchTree()
        } catch {
            print("[DeckListView] Error loading decks: \(error)")
            tree = []
        }
        isLoading = false
    }
}

// MARK: - DeckRowView

private struct DeckRowView: View {
    let node: DeckTreeNode
    let onMutated: () async -> Void

    @Environment(\.palette) private var palette
    @Dependency(\.deckClient) var deckClient
    @State private var showRenameSheet = false
    @State private var showDeleteAlert = false

    var body: some View {
        rowContent
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)

                Button {
                    showRenameSheet = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.orange)
            }
            .alert("Delete \"\(node.name)\"?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try deckClient.delete(node.id)
                        } catch {
                            print("[DeckRowView] Delete failed: \(error)")
                        }
                        await onMutated()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the deck and all its cards.")
            }
            .sheet(isPresented: $showRenameSheet) {
                RenameDeckSheet(deckId: node.id, currentName: node.fullName) {
                    showRenameSheet = false
                    Task { await onMutated() }
                }
            }
    }

    @ViewBuilder
    private var rowContent: some View {
        if node.children.isEmpty {
            NavigationLink(value: deckInfo) {
                rowLabel
            }
        } else {
            DisclosureGroup {
                ForEach(node.children) { child in
                    DeckRowView(node: child, onMutated: onMutated)
                }
            } label: {
                NavigationLink(value: deckInfo) {
                    rowLabel
                }
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 10) {
            if node.isFiltered {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        palette.customStudyBadge,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
                    .accessibilityLabel("Custom study deck")
            }
            Text(node.name)
                .ankountantFont(.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            DeckCountsView(counts: node.counts)
        }
    }

    private var deckInfo: DeckInfo {
        DeckInfo(id: node.id, name: node.fullName, counts: node.counts, isFiltered: node.isFiltered)
    }
}

// MARK: - CreateDeckSheet

private struct CreateDeckSheet: View {
    let onDone: () -> Void

    @Dependency(\.deckClient) var deckClient
    @State private var name = ""
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck name, use :: for subdecks", text: $name)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        do {
            _ = try deckClient.create(name.trimmingCharacters(in: .whitespaces))
            onDone()
        } catch {
            print("[CreateDeckSheet] Create failed: \(error)")
        }
        isSaving = false
    }
}

// MARK: - RenameDeckSheet

private struct RenameDeckSheet: View {
    let deckId: Int64
    let currentName: String
    let onDone: () -> Void

    @Dependency(\.deckClient) var deckClient
    @State private var name = ""
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck name", text: $name)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Rename Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await rename() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { name = currentName }
        }
    }

    private func rename() async {
        isSaving = true
        do {
            try deckClient.rename(deckId, name.trimmingCharacters(in: .whitespaces))
            onDone()
        } catch {
            print("[RenameDeckSheet] Rename failed: \(error)")
        }
        isSaving = false
    }
}
