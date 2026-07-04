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

    private enum SimulationRoute: Hashable {
        case tbs(Int64)
        case confusion(CPASection?)
    }

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
                    description: Text("No sealed Task-Based Simulations were found in this profile.")
                )
            } else {
                loadedContent
            }
        }
        .navigationTitle("Simulations")
        .task {
            await loadTasks()
        }
        .navigationDestination(for: SimulationRoute.self) { route in
            switch route {
            case .tbs(let noteId):
                TbsTaskView(noteId: noteId)
            case .confusion(let section):
                ConfusionDrillView(section: section)
            }
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
                        Text("No \(shapeLabel(selectedShape).lowercased()) simulations in this profile.")
                            .ankountantFont(.body)
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        ForEach(filteredTasks) { task in
                            NavigationLink(value: SimulationRoute.tbs(task.noteId)) {
                                taskRow(task)
                            }
                        }
                    }
                }

                Section("Confusion") {
                    NavigationLink(value: SimulationRoute.confusion(nil)) {
                        Label("All sections", systemImage: "arrow.triangle.branch")
                    }
                    ForEach(CPASection.practiceOrder) { section in
                        NavigationLink(value: SimulationRoute.confusion(section)) {
                            sectionRow(section)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ankountantSectionBackground()
        }
        .background(palette.background)
    }

    private func sectionRow(_ section: CPASection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(section.code) confusion drill")
                .ankountantFont(.body)
                .foregroundStyle(palette.textPrimary)
            Text(section.displayName)
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func taskRow(_ task: TbsTaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.prompt)
                .ankountantFont(.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Text("\(task.section) · \(shapeLabel(task.shape))")
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
            selectedShape = simulationShapeAfterLoad(
                current: selectedShape,
                tasks: loaded,
                order: shapeOrder
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            tasks = []
        }
        isLoading = false
    }
}

func simulationShapeAfterLoad(
    current: TbsShape,
    tasks: [TbsTaskSummary],
    order: [TbsShape]
) -> TbsShape {
    if tasks.contains(where: { $0.shape == current }) {
        return current
    }
    return order.first(where: { shape in tasks.contains { $0.shape == shape } }) ?? current
}
