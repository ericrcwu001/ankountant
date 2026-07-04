import SwiftUI
import AnkiKit
import AnkiClients
import AnkiServices
import Dependencies

struct NoteEditorView: View {
    let note: NoteRecord
    let onSave: () -> Void

    @Dependency(\.noteClient) var noteClient
    @Dependency(\.notetypesService) var notetypesService

    @State private var fieldValues: [String] = []
    @State private var fieldNames: [String] = []
    @State private var tags: String = ""
    @State private var isSaving = false
    @State private var showSavedConfirmation = false
    @State private var loadErrorMessage: String?
    @State private var saveErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
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
                    Text(loadErrorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if let saveErrorMessage {
                Section {
                    Text(saveErrorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!canSaveNote)
            }
        }
        .overlay {
            if showSavedConfirmation {
                VStack {
                    Spacer()
                    Text("Saved")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { loadNote() }
    }

    private func fieldBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < fieldValues.count ? fieldValues[index] : "" },
            set: { newValue in
                if index < fieldValues.count { fieldValues[index] = newValue }
            }
        )
    }

    private var canSaveNote: Bool {
        NoteFormRules.canSaveEditedNote(
            isSaving: isSaving,
            fieldNames: fieldNames,
            fieldValues: fieldValues,
            loadErrorMessage: loadErrorMessage
        )
    }

    private func loadNote() {
        loadErrorMessage = nil
        saveErrorMessage = nil

        do {
            let notetype = try notetypesService.getNotetype(note.mid)
            fieldNames = notetype.fieldNames
            fieldValues = NoteFormRules.splitFields(note.flds, minimumCount: fieldNames.count)
            tags = note.tags.trimmingCharacters(in: .whitespaces)
        } catch {
            fieldNames = []
            fieldValues = []
            loadErrorMessage = "Failed to load note fields: \(error.localizedDescription)"
        }
    }

    private func save() async {
        guard canSaveNote else {
            saveErrorMessage = loadErrorMessage ?? "Note fields are still loading."
            return
        }

        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }

        let newFlds = fieldValues.joined(separator: "\u{1f}")
        let newSfld = fieldValues.first ?? ""
        let newCsum = Int64(newSfld.hashValue & 0xFFFFFFFF)

        var updatedNote = note
        updatedNote.flds = newFlds
        updatedNote.sfld = newSfld
        updatedNote.csum = newCsum
        updatedNote.tags = NoteFormRules.spacedTags(from: tags)

        do {
            try noteClient.save(updatedNote)
        } catch {
            saveErrorMessage = "Failed to save note: \(error.localizedDescription)"
            return
        }

        withAnimation { showSavedConfirmation = true }
        do {
            try await Task.sleep(for: .seconds(1.5))
        } catch {
            return
        }
        withAnimation { showSavedConfirmation = false }
        onSave()
    }
}
