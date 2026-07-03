import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import Dependencies

struct SimulationsHubView: View {
    @Environment(\.palette) private var palette
    @Dependency(\.performanceClient) var performanceClient

    @State private var tasks: [TbsTaskSummary] = []
    @State private var selectedShape: TbsShape = .journalEntry
    @State private var isLoading = true
    @State private var errorMessage: String?

    // The four TBS shapes, in the order shown by the chooser. Mirrors the
    // desktop TBS-tab chooser (TBS_SHAPES in ankountant-tbs/lib.ts).
    private let shapeOrder: [TbsShape] = [.journalEntry, .numeric, .research, .docReview]

    private var filteredTasks: [TbsTaskSummary] {
        tasks.filter { $0.shape == selectedShape }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't Load Simulations",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if tasks.isEmpty {
                ContentUnavailableView(
                    "No Simulations",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Load the FAR demo profile from Settings ▸ Developer ▸ Debug to get Task-Based Simulations.")
                )
            } else {
                loadedContent
            }
        }
        .navigationTitle("Simulations")
        .task {
            await loadTasks()
        }
    }

    // MARK: - Loaded content

    private var loadedContent: some View {
        VStack(spacing: 0) {
            // Type chooser: the learner picks which kind of simulation to
            // practise, and the list below filters to that shape.
            Picker("Simulation type", selection: $selectedShape) {
                ForEach(shapeOrder, id: \.self) { shape in
                    Text(segmentLabel(shape)).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List {
                Section(shapeLabel(selectedShape)) {
                    if filteredTasks.isEmpty {
                        Text("No \(shapeLabel(selectedShape).lowercased()) simulations yet.")
                            .ankountantFont(.body)
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        ForEach(filteredTasks) { task in
                            NavigationLink {
                                TbsTaskView(noteId: task.noteId)
                            } label: {
                                taskRow(task)
                            }
                        }
                    }
                }

                Section("Confusion") {
                    NavigationLink {
                        ConfusionDrillView()
                    } label: {
                        Label("Confusion drill", systemImage: "arrow.triangle.branch")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ankountantSectionBackground()
        }
        .background(palette.background)
    }

    private func taskRow(_ task: TbsTaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.prompt)
                .ankountantFont(.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Text(shapeLabel(task.shape))
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func shapeLabel(_ shape: TbsShape) -> String {
        switch shape {
        case .journalEntry: "Journal entry"
        case .numeric: "Numeric"
        case .research: "Research"
        case .docReview: "Document review"
        }
    }

    // Concise labels for the segmented control (the full label rides in each
    // row's caption), so four segments fit without truncation.
    private func segmentLabel(_ shape: TbsShape) -> String {
        switch shape {
        case .journalEntry: "Journal"
        case .numeric: "Numeric"
        case .research: "Research"
        case .docReview: "Review"
        }
    }

    private func loadTasks() async {
        isLoading = true
        do {
            let loaded = try performanceClient.listTbsTasks()
            tasks = loaded
            // Open on the first shape that actually has tasks so the chooser
            // never starts on an empty type.
            if let first = shapeOrder.first(where: { shape in loaded.contains { $0.shape == shape } }) {
                selectedShape = first
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            tasks = []
        }
        isLoading = false
    }
}
