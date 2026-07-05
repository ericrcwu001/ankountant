import SwiftUI
import AnkountantTheme
import AnkiKit
import AnkiClients
import Dependencies

struct SimulationsHubView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Dependency(\.performanceClient) var performanceClient

    @State private var tasks: [TbsTaskSummary] = []
    @State private var confusionCounts: [CPASection: Int] = [:]
    @State private var allConfusionCount = 0
    @State private var selectedShape: TbsShape = .journalEntry
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var showImportAlert = false

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

    private var availableSectionsWithConfusion: [CPASection] {
        availableConfusionSections(confusionCounts, order: CPASection.practiceOrder)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn't Load Simulations", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await loadTasks() }
                    }
                }
            } else if !simulationsHubHasContent(tasks: tasks, allConfusionCount: allConfusionCount) {
                ContentUnavailableView {
                    Label("No Simulations", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("No sealed simulations or confusion drills were found in this profile.")
                } actions: {
                    Button("Import package", systemImage: "square.and.arrow.down") {
                        showImport = true
                    }
                    Button("Retry") {
                        Task { await loadTasks() }
                    }
                }
            } else {
                loadedContent
            }
        }
        .navigationTitle("Simulations")
        .task {
            await loadTasks()
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
        .alert("Import", isPresented: $showImportAlert) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
        .navigationDestination(for: SimulationRoute.self) { route in
            switch route {
            case .tbs(let noteId):
                TbsTaskView(noteId: noteId)
            case .confusion(let section):
                ConfusionDrillView(section: section)
            }
        }
        .navigationDestination(for: CPASection.self) { section in
            SectionDetailView(section: section)
        }
    }

    // MARK: - Loaded content

    private var loadedContent: some View {
        VStack(spacing: 0) {
            shapeChooser

            List {
                Section(tbsShapeDisplayLabel(selectedShape)) {
                    if filteredTasks.isEmpty {
                        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
                            Text("No \(tbsShapeDisplayLabel(selectedShape).lowercased()) simulations in this profile.")
                                .ankountantFont(.body)
                                .foregroundStyle(palette.textSecondary)
                            Button("Import package", systemImage: "square.and.arrow.down") {
                                showImport = true
                            }
                        }
                        .padding(.vertical, 2)
                    } else {
                        ForEach(filteredTasks) { task in
                            NavigationLink(value: SimulationRoute.tbs(task.noteId)) {
                                taskRow(task)
                            }
                        }
                    }
                }

                Section("Confusion") {
                    if allConfusionCount > 0 {
                        NavigationLink(value: SimulationRoute.confusion(nil)) {
                            allConfusionRow(enabled: true)
                        }
                    } else {
                        allConfusionRow(enabled: false)
                        Button("Import package", systemImage: "square.and.arrow.down") {
                            showImport = true
                        }
                    }
                    ForEach(CPASection.practiceOrder) { section in
                        confusionSectionRow(section)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .ankountantSectionBackground()
        }
        .background(palette.background)
    }

    @ViewBuilder
    private var shapeChooser: some View {
        VStack(alignment: .leading, spacing: AnkountantSpacing.sm) {
            Text("Simulation type")
                .ankountantFont(.micro)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            if dynamicTypeSize.isAccessibilitySize {
                shapeMenu
            } else {
                Picker("Simulation type", selection: $selectedShape) {
                    ForEach(shapeOrder, id: \.self) { shape in
                        Text(tbsShapeSegmentLabel(shape))
                            .accessibilityLabel(tbsShapeDisplayLabel(shape))
                            .tag(shape)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.top, AnkountantSpacing.sm)
        .padding(.bottom, AnkountantSpacing.xs)
    }

    private var shapeMenu: some View {
        Menu {
            ForEach(shapeOrder, id: \.self) { shape in
                Button {
                    selectedShape = shape
                } label: {
                    if shape == selectedShape {
                        Label(shapeMenuLabel(shape), systemImage: "checkmark")
                    } else {
                        Text(shapeMenuLabel(shape))
                    }
                }
            }
        } label: {
            HStack(spacing: AnkountantSpacing.md) {
                Text(shapeMenuLabel(selectedShape))
                    .ankountantFont(.body)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: AnkountantSpacing.sm)
                Image(systemName: "chevron.up.chevron.down")
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, AnkountantSpacing.md)
            .padding(.vertical, AnkountantSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                    .fill(palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AnkountantRadius.control, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
        .accessibilityLabel("Simulation type")
        .accessibilityValue(tbsShapeDisplayLabel(selectedShape))
    }

    private func shapeMenuLabel(_ shape: TbsShape) -> String {
        tbsShapeMenuLabel(shape, taskCount: tbsTaskCount(for: shape, in: tasks))
    }

    private func allConfusionRow(enabled: Bool) -> some View {
        HStack(spacing: AnkountantSpacing.md) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(enabled ? palette.accent : palette.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("All available sections")
                    .ankountantFont(.body)
                    .foregroundStyle(enabled ? palette.textPrimary : palette.textSecondary)
                Text(allConfusionSubtitle)
                    .ankountantFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var allConfusionSubtitle: String {
        if allConfusionCount == 0 {
            return "No confusion items available yet"
        }
        let sectionCount = availableSectionsWithConfusion.count
        let sectionText = sectionCount == 1 ? "1 section" : "\(sectionCount) sections"
        return "\(confusionCountLabel(allConfusionCount)) across \(sectionText)"
    }

    @ViewBuilder
    private func confusionSectionRow(_ section: CPASection) -> some View {
        let count = confusionCounts[section, default: 0]
        if count > 0 {
            NavigationLink(value: SimulationRoute.confusion(section)) {
                sectionRow(section, count: count, enabled: true)
            }
        } else {
            sectionRow(section, count: count, enabled: false)
        }
    }

    private func sectionRow(_ section: CPASection, count: Int, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(section.code) confusion drill")
                .ankountantFont(.body)
                .foregroundStyle(enabled ? palette.textPrimary : palette.textSecondary)
            Text("\(section.displayName) · \(confusionCountLabel(count))")
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
            Text("\(task.section) · \(tbsShapeDisplayLabel(task.shape))")
                .ankountantFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func loadTasks() async {
        isLoading = true
        do {
            let loaded = try performanceClient.listTbsTasks()
            let loadedConfusionCounts = try loadConfusionCounts()
            tasks = loaded
            confusionCounts = loadedConfusionCounts
            allConfusionCount = loadedConfusionCounts.values.reduce(0, +)
            selectedShape = simulationShapeAfterLoad(
                current: selectedShape,
                tasks: loaded,
                order: shapeOrder
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            tasks = []
            confusionCounts = [:]
            allConfusionCount = 0
        }
        isLoading = false
    }

    private func loadConfusionCounts() throws -> [CPASection: Int] {
        var counts: [CPASection: Int] = [:]
        for section in CPASection.practiceOrder {
            counts[section] = try performanceClient.confusionQueue(section.code, 0).count
        }
        return counts
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
                Task { await loadTasks() }
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
            showImportAlert = true
        case .failure(let error):
            importMessage = "Could not select file: \(error.localizedDescription)"
            showImportAlert = true
        }
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

func availableConfusionSections(
    _ counts: [CPASection: Int],
    order: [CPASection]
) -> [CPASection] {
    order.filter { counts[$0, default: 0] > 0 }
}

func confusionCountLabel(_ count: Int) -> String {
    count == 1 ? "1 item" : "\(count) items"
}

func tbsShapeDisplayLabel(_ shape: TbsShape) -> String {
    switch shape {
    case .journalEntry: "Journal entry"
    case .numeric: "Numeric"
    case .research: "Research"
    case .docReview: "Document review"
    }
}

func tbsShapeSegmentLabel(_ shape: TbsShape) -> String {
    switch shape {
    case .journalEntry: "Journal"
    case .numeric: "Numeric"
    case .research: "Research"
    case .docReview: "Review"
    }
}

func tbsTaskCount(for shape: TbsShape, in tasks: [TbsTaskSummary]) -> Int {
    tasks.filter { $0.shape == shape }.count
}

func tbsShapeCountLabel(_ count: Int) -> String {
    count == 1 ? "1 simulation" : "\(count) simulations"
}

func tbsShapeMenuLabel(_ shape: TbsShape, taskCount: Int) -> String {
    "\(tbsShapeDisplayLabel(shape)) · \(tbsShapeCountLabel(taskCount))"
}

func simulationsHubHasContent(tasks: [TbsTaskSummary], allConfusionCount: Int) -> Bool {
    !tasks.isEmpty || allConfusionCount > 0
}
