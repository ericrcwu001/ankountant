import SwiftUI
import AnkountantTheme
import AnkiClients
import AnkiProto
import Dependencies

enum NotetypeFieldValidationIssue: Equatable {
    case noFields
    case blankName
    case duplicateName(String)

    var message: String {
        switch self {
        case .noFields:
            "A notetype needs at least one field."
        case .blankName:
            "Field names cannot be blank."
        case let .duplicateName(name):
            "Field names must be unique. \"\(name)\" is already used."
        }
    }
}

func normalizedNotetypeFieldName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
}

func notetypeFieldValidationIssue(
    for fields: [Anki_Notetypes_Notetype.Field]
) -> NotetypeFieldValidationIssue? {
    guard !fields.isEmpty else { return .noFields }

    var seen = Set<String>()
    for field in fields {
        let name = normalizedNotetypeFieldName(field.name)
        guard !name.isEmpty else { return .blankName }
        let key = name.lowercased()
        guard seen.insert(key).inserted else { return .duplicateName(name) }
    }
    return nil
}

func makeNotetypeField(
    named name: String,
    matching fields: [Anki_Notetypes_Notetype.Field]
) -> Anki_Notetypes_Notetype.Field {
    var field = Anki_Notetypes_Notetype.Field()
    field.name = normalizedNotetypeFieldName(name)

    var config = Anki_Notetypes_Notetype.Field.Config()
    if let source = fields.first?.config {
        config.fontName = source.fontName.isEmpty ? "Arial" : source.fontName
        config.fontSize = source.fontSize == 0 ? 20 : source.fontSize
        config.rtl = source.rtl
        config.sticky = source.sticky
        config.plainText = source.plainText
    } else {
        config.fontName = "Arial"
        config.fontSize = 20
    }
    field.config = config
    return field
}

struct NotetypeFieldManagerView: View {
    @Dependency(\.notetypesClient) private var notetypesClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    let notetypeId: Int64
    let preferredName: String
    var onSaved: (@Sendable () async -> Void)? = nil

    @State private var notetype: Anki_Notetypes_Notetype = .init()
    @State private var originalFields: [Anki_Notetypes_Notetype.Field] = []
    @State private var newFieldName = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadErrorMessage: String?
    @State private var actionErrorMessage: String?
    @State private var showActionError = false
    @State private var showDiscardChangesConfirmation = false

    private var validationIssue: NotetypeFieldValidationIssue? {
        notetypeFieldValidationIssue(for: notetype.fields)
    }

    private var hasUnsavedChanges: Bool {
        !isLoading && originalFields != notetype.fields
    }

    private var canSave: Bool {
        hasUnsavedChanges && validationIssue == nil && !isSaving
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let loadErrorMessage {
                VStack(spacing: AnkountantSpacing.md) {
                    AnkountantStatusMessageView(
                        title: "Could not load fields",
                        message: loadErrorMessage,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )

                    Button("Retry") {
                        Task { await loadFields() }
                    }
                    .buttonStyle(AnkountantPrimaryButtonStyle())
                }
                .padding()
            } else {
                fieldEditor
            }
        }
        .background(palette.background)
        .navigationTitle(preferredName)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { attemptDismiss() }
                    .ankountantToolbarTextButton(tone: .neutral)
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .disabled(isLoading || notetype.fields.count < 2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await saveFields() }
                    }
                    .ankountantToolbarTextButton()
                    .disabled(!canSave)
                }
            }
        }
        .alert("Field edit failed", isPresented: $showActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog(
            "Unsaved changes",
            isPresented: $showDiscardChangesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved field changes. Discard them?")
        }
        .task {
            await loadFields()
        }
    }

    private var fieldEditor: some View {
        List {
            if let validationIssue {
                Section {
                    AnkountantStatusMessageView(
                        title: "Field issue",
                        message: validationIssue.message,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
            }

            Section {
                ForEach(Array(notetype.fields.indices), id: \.self) { index in
                    fieldRow(index)
                }
                .onMove(perform: moveFields)
                .onDelete(perform: deleteFields)
            } header: {
                Text("Fields")
            }

            Section {
                HStack(spacing: AnkountantSpacing.sm) {
                    TextField("New field name", text: $newFieldName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Button("Add") { addField() }
                        .disabled(normalizedNotetypeFieldName(newFieldName).isEmpty)
                }
            } header: {
                Text("Add field")
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }

    private func fieldRow(_ index: Int) -> some View {
        HStack(spacing: AnkountantSpacing.sm) {
            TextField("Field name", text: fieldNameBinding(for: index))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if notetype.fields[index].config.preventDeletion {
                Image(systemName: "lock.fill")
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityLabel("Deletion prevented")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteField(at: index)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!canDeleteField(at: index))
        }
    }

    private func fieldNameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard notetype.fields.indices.contains(index) else { return "" }
                return notetype.fields[index].name
            },
            set: { value in
                guard notetype.fields.indices.contains(index) else { return }
                notetype.fields[index].name = value
            }
        )
    }

    @MainActor
    private func loadFields() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }

        do {
            let getRaw = notetypesClient.getRaw
            notetype = try await Task.detached(priority: .userInitiated) {
                try getRaw(notetypeId)
            }.value
            originalFields = notetype.fields
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func addField() {
        let name = normalizedNotetypeFieldName(newFieldName)
        guard !name.isEmpty else { return }
        if notetype.fields.contains(where: { normalizedNotetypeFieldName($0.name).lowercased() == name.lowercased() }) {
            showError("Field names must be unique. \"\(name)\" is already used.")
            return
        }
        notetype.fields.append(makeNotetypeField(named: name, matching: notetype.fields))
        newFieldName = ""
    }

    private func moveFields(from source: IndexSet, to destination: Int) {
        notetype.fields.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteFields(_ offsets: IndexSet) {
        let indices = offsets.sorted(by: >)
        guard notetype.fields.count - indices.count >= 1 else {
            showError(NotetypeFieldValidationIssue.noFields.message)
            return
        }
        for index in indices {
            guard canDeleteField(at: index) else {
                showError("This field cannot be deleted.")
                return
            }
        }
        for index in indices {
            notetype.fields.remove(at: index)
        }
    }

    private func deleteField(at index: Int) {
        deleteFields(IndexSet(integer: index))
    }

    private func canDeleteField(at index: Int) -> Bool {
        notetype.fields.indices.contains(index)
            && notetype.fields.count > 1
            && !notetype.fields[index].config.preventDeletion
    }

    private func attemptDismiss() {
        if hasUnsavedChanges {
            showDiscardChangesConfirmation = true
        } else {
            dismiss()
        }
    }

    @MainActor
    private func saveFields() async {
        guard validationIssue == nil else {
            showError(validationIssue?.message ?? "Field names are invalid.")
            return
        }
        isSaving = true
        defer { isSaving = false }

        do {
            let updateNotetype = notetypesClient.update
            let updatedNotetype = notetype
            try await Task.detached(priority: .userInitiated) {
                try updateNotetype(updatedNotetype)
            }.value
            originalFields = notetype.fields
            if let onSaved {
                await onSaved()
            }
            dismiss()
        } catch {
            showError("Save failed: \(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        actionErrorMessage = message
        showActionError = true
    }
}
