import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import Dependencies

struct SimulationsHubView: View {
    @Environment(\.palette) private var palette
    @Dependency(\.performanceClient) var performanceClient

    @State private var tasks: [TbsTaskSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                List {
                    Section("Task-Based Simulations") {
                        ForEach(tasks) { task in
                            NavigationLink {
                                TbsTaskView(noteId: task.noteId)
                            } label: {
                                taskRow(task)
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
        }
        .navigationTitle("Simulations")
        .task {
            await loadTasks()
        }
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

    private func loadTasks() async {
        isLoading = true
        do {
            tasks = try performanceClient.listTbsTasks()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            tasks = []
        }
        isLoading = false
    }
}
