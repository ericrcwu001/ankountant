import SwiftUI
import AnkiClients
import Dependencies

struct BatchTagSheet: View {
    let noteIDs: Set<Int64>
    let onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Dependency(\.tagClient) private var tagClient

    @State private var allTags: [String] = []
    @State private var checkedTags: Set<String> = []
    @State private var newTagName: String = ""
    @State private var isApplying = false
    @State private var loadErrorMessage: String?
    @State private var applyErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("New tag") {
                    HStack {
                        TextField("Add new tag", text: $newTagName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(isApplying)
                        Button("Add") {
                            let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            checkedTags.insert(trimmed)
                            if !allTags.contains(trimmed) {
                                allTags.append(trimmed)
                                allTags.sort()
                            }
                            newTagName = ""
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isApplying)
                    }
                }

                Section("Existing tags") {
                    if allTags.isEmpty {
                        Text("No tags yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                if checkedTags.contains(tag) {
                                    checkedTags.remove(tag)
                                } else {
                                    checkedTags.insert(tag)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: checkedTags.contains(tag) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(checkedTags.contains(tag) ? Color.accentColor : Color.secondary)
                                        .accessibilityHidden(true)
                                    Text(tag).foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .disabled(isApplying)
                            .accessibilityLabel(tag)
                            .accessibilityValue(checkedTags.contains(tag) ? "Selected" : "Not selected")
                        }
                    }
                }

                if let loadErrorMessage {
                    Section {
                        ContentUnavailableView {
                            Label("Could Not Load Tags", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(loadErrorMessage)
                        } actions: {
                            Button("Retry") {
                                Task { await loadTags() }
                            }
                        }
                    }
                }

                if let applyErrorMessage {
                    Section {
                        Text(applyErrorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add tags to \(noteIDs.count) note\(noteIDs.count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isApplying)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Applying tags")
                    } else {
                        Button("Apply") {
                            startApply()
                        }
                        .disabled(checkedTags.isEmpty)
                    }
                }
            }
            .task {
                await loadTags()
            }
        }
    }

    private func loadTags() async {
        loadErrorMessage = nil
        do {
            let tags = try tagClient.getAllTags()
            allTags = tags.sorted()
        } catch {
            allTags = []
            loadErrorMessage = "Failed to load tags: \(error.localizedDescription)"
        }
    }

    private func startApply() {
        guard !checkedTags.isEmpty, !isApplying else { return }
        isApplying = true
        applyErrorMessage = nil
        let tags = checkedTags
        Task { await apply(tags) }
    }

    private func apply(_ tags: Set<String>) async {
        defer { isApplying = false }

        let ids = Array(noteIDs)

        do {
            for tag in tags {
                try tagClient.addTagToNotes(tag, ids)
            }
            onApplied()
            dismiss()
        } catch {
            applyErrorMessage = "Failed to apply tags: \(error.localizedDescription)"
        }
    }
}
