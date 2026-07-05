import SwiftUI
import PhotosUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import Dependencies

struct AddImageOcclusionNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Dependency(\.deckClient) private var deckClient
    @Dependency(\.imageOcclusionClient) private var client

    @State private var decks: [DeckInfo] = []
    @State private var selectedDeckId: Int64
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var masks: [IOMask] = []
    @State private var header: String = ""
    @State private var backExtra: String = ""
    @State private var tagsText: String = ""
    @State private var isSaving = false
    @State private var loadErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var imageURL: URL?
    @State private var showOcclusionEditor = false
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false
    @State private var showCreateDeck = false

    let onSave: () -> Void
    let preselectedDeckId: Int64?

    private static let noDecksMessage = "No decks are available."

    init(onSave: @escaping () -> Void, preselectedDeckId: Int64? = nil) {
        self.onSave = onSave
        self.preselectedDeckId = preselectedDeckId
        _selectedDeckId = State(initialValue: preselectedDeckId ?? 0)
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

                Section {
                    Text("Add Image Occlusion")
                        .foregroundStyle(palette.textPrimary)
                } header: {
                    Text("Note Type")
                } footer: {
                    Text("Pick an image, draw occlusions over the regions you want to test, then save.")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Section {
                    let pickImageSystemName = selectedImage == nil ? "photo.on.rectangle.angled" : "photo.badge.plus"
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            "Pick image",
                            systemImage: pickImageSystemName
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task { await loadImage(from: newItem) }
                    }
                } header: {
                    Text("Image")
                }

                if let uiImage = selectedImage {
                    Section {
                        ImageOcclusionMaskSummaryCard(image: uiImage, masks: masks) {
                            showOcclusionEditor = true
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Masks")
                    } footer: {
                        Text("Tap and drag to draw a mask. Drag handles to resize.")
                            .ankountantFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                Section("Content") {
                    TextField("Header", text: $header)
                    TextField("Extra info shown on the back", text: $backExtra)
                }

                Section {
                    TextField("Tags", text: $tagsText)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Space-separated")
                        .ankountantFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                if let loadErrorMessage {
                    Section {
                        if localContentMissing {
                            ContentUnavailableView {
                                Label("Could Not Load Decks", systemImage: "exclamationmark.triangle")
                            } description: {
                                Text(loadErrorMessage)
                            } actions: {
                                Button("Retry") {
                                    Task { await loadDecks() }
                                }
                                Button("Create deck", systemImage: "plus") {
                                    showCreateDeck = true
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Import package", systemImage: "square.and.arrow.down") {
                                    showImport = true
                                }
                            }
                        } else {
                            Text(loadErrorMessage)
                                .ankountantStatusText(.danger, font: .caption)
                        }
                    }
                }

                if let saveErrorMessage {
                    Section {
                        Text(saveErrorMessage)
                            .ankountantStatusText(.danger, font: .caption)
                    }
                }

                if !isSaving, let saveRequirementMessage {
                    Section {
                        Text(saveRequirementMessage)
                            .ankountantFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .toolbar(.hidden, for: .tabBar)
            .navigationTitle("Image Occlusion")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadDecks()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .ankountantToolbarTextButton(tone: .neutral)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .ankountantToolbarTextButton()
                    .disabled(!canSave || isSaving)
                    .accessibilityHint(saveRequirementMessage ?? "")
                    .overlay {
                        if isSaving { ProgressView().scaleEffect(0.7) }
                    }
                }
            }
            .fullScreenCover(isPresented: $showOcclusionEditor) {
                if let selectedImage {
                    NavigationStack {
                        ImageOcclusionWorkspaceView(
                            title: "Edit",
                            image: selectedImage,
                            initialMasks: masks
                        ) { updatedMasks in
                            masks = updatedMasks
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showCreateDeck) {
                CreateDeckSheet {
                    showCreateDeck = false
                    Task {
                        await loadDecks()
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

    private var canSave: Bool {
        loadErrorMessage == nil
            && decks.contains { $0.id == selectedDeckId }
            && selectedImage != nil
            && imageURL != nil
            && !masks.isEmpty
    }

    private var saveRequirementMessage: String? {
        guard loadErrorMessage == nil else {
            return nil
        }
        guard !decks.isEmpty else {
            return nil
        }
        guard decks.contains(where: { $0.id == selectedDeckId }) else {
            return "Choose a deck before saving."
        }
        guard selectedImage != nil else {
            return "Pick an image before saving."
        }
        guard imageURL != nil else {
            return "The selected image is still being prepared."
        }
        guard !masks.isEmpty else {
            return "Draw at least one mask before saving."
        }
        return nil
    }

    private var localContentMissing: Bool {
        loadErrorMessage == Self.noDecksMessage
    }

    @MainActor
    private func loadDecks() async {
        loadErrorMessage = nil
        saveErrorMessage = nil

        do {
            decks = try deckClient.fetchAll()
        } catch {
            decks = []
            selectedDeckId = 0
            loadErrorMessage = "Failed to load decks: \(error.localizedDescription)"
            return
        }

        guard !decks.isEmpty else {
            selectedDeckId = 0
            loadErrorMessage = Self.noDecksMessage
            return
        }

        if let preselectedDeckId, decks.contains(where: { $0.id == preselectedDeckId }) {
            selectedDeckId = preselectedDeckId
            return
        }

        selectedDeckId = decks[0].id
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
                    await loadDecks()
                    onSave()
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

    @MainActor
    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        masks = []
        selectedImage = nil
        imageURL = nil
        loadErrorMessage = nil
        saveErrorMessage = nil

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                loadErrorMessage = "The selected image could not be loaded."
                return
            }

            guard let img = UIImage(data: data) else {
                loadErrorMessage = "The selected file is not a readable image."
                return
            }

            guard let jpegData = img.jpegData(compressionQuality: 0.92) else {
                loadErrorMessage = "The selected image could not be prepared for saving."
                return
            }

            let filename = "io_pick_\(Int(Date.now.timeIntervalSince1970)).jpg"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try jpegData.write(to: url, options: .atomic)
            selectedImage = img
            imageURL = url
        } catch {
            loadErrorMessage = "Failed to load image: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func save() async {
        guard decks.contains(where: { $0.id == selectedDeckId }) else {
            saveErrorMessage = "Choose a deck before saving."
            return
        }
        guard selectedImage != nil else {
            saveErrorMessage = "Pick an image before saving."
            return
        }
        guard let url = imageURL else {
            saveErrorMessage = "Image is missing."
            return
        }
        guard !masks.isEmpty else {
            saveErrorMessage = "Add at least one mask before saving."
            return
        }

        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        let occlusions = masks.enumerated().map { idx, mask in
            mask.occlusionText(index: idx)
        }.joined(separator: "\n")
        let tags = NoteFormRules.normalizedTags(from: tagsText)

        do {
            try client.addNote(url, occlusions, header, backExtra, tags, selectedDeckId, 0)
            onSave()
            dismiss()
        } catch {
            saveErrorMessage = "Failed to save image occlusion: \(error.localizedDescription)"
        }
    }
}
