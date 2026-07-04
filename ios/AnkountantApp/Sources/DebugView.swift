import SwiftUI
import AnkiBackend
import AnkiClients
import AnkiKit
import AnkiServices
import AnkiSync
import Dependencies
import Foundation
import Sharing

struct DebugView: View {
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.collectionService) var collectionService
    @Dependency(\.decksService) var decksService
    @Dependency(\.schedulerService) var schedulerService
    @Dependency(\.examConfigClient) var examConfigClient
    @State private var statusMessage = ""
    @State private var showResetConfirm = false
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false

    // Signals Home (in another tab) to reload after a demo reseed.
    @Shared(.appStorage(DemoSeed.versionKey)) private var demoSeedVersion = 0

    private let section = "FAR"

    var body: some View {
        List {
            Section("Account") {
                HStack {
                    Text("Username")
                    Spacer()
                    Text(KeychainHelper.loadUsername() ?? "Not logged in")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Host Key")
                    Spacer()
                    Text(KeychainHelper.loadHostKey() != nil ? "Stored ✓" : "None")
                        .foregroundStyle(.secondary)
                }
                Button("Logout (clear credentials)", role: .destructive) {
                    KeychainHelper.deleteHostKey()
                    statusMessage = "Logged out. Tap sync to re-login."
                }
            }

            Section("Ankountant demo phases") {
                Button("Foundation — beginner (no history)") { loadPhase(.foundation) }
                Button("Discrimination — mid-prep (exam later)") { loadPhase(.discrimination) }
                Button("Consolidation — exam soon") { loadPhase(.consolidation) }
            }

            Section("Import / Export") {
                Button("Export Collection (.colpkg)") {
                    do {
                        let url = try ImportHelper.exportCollection()
                        exportedFileURL = url
                        showShareSheet = true
                        statusMessage = "Export ready: \(url.lastPathComponent)"
                    } catch {
                        statusMessage = "Export error: \(error.localizedDescription)"
                    }
                }
            }

            Section("Database") {
                Button("Check Database") {
                    do {
                        try collectionService.checkDatabase()
                        statusMessage = "CheckDatabase OK"
                    } catch {
                        statusMessage = "CheckDatabase error: \(error)"
                    }
                }

                Button("Reset Everything", role: .destructive) {
                    showResetConfirm = true
                }
                .confirmationDialog("This will delete your local collection and credentials. You'll need to sync again.", isPresented: $showResetConfirm, titleVisibility: .visible) {
                    Button("Reset", role: .destructive) {
                        resetEverything()
                    }
                }
            }

            if !statusMessage.isEmpty {
                Section("Status") {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Collection Info") {
                Button("Dump Deck Tree") {
                    dumpDeckTree()
                }
            }
        }
        .navigationTitle("Debug")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    /// Load the FAR demo seed tuned so the Home phase-aware CTA lands in a given
    /// phase, to demo/QA the dynamic study recommendation. Foundation loads
    /// content with no history + no exam date (no memory base => "Build
    /// foundation"); discrimination adds history + the seed's ~45-day exam date
    /// (far => "Discrimination drill"); consolidation adds history + a 7-day exam
    /// date (final stretch => "Consolidate"). Best on a fresh profile.
    private func loadPhase(_ phase: StudyPhase) {
        do {
            switch phase {
            case .foundation:
                try schedulerService.loadFarSeed(false)
                try examConfigClient.saveExamDate(section, "")
            case .discrimination:
                try schedulerService.loadFarSeed(true)
            case .consolidation:
                try schedulerService.loadFarSeed(true)
                try examConfigClient.saveExamDate(section, Self.iso(daysFromNow: 7))
            }
            // Tell Home to reload so the new phase (CTA, countdown, readiness)
            // shows immediately instead of Home's stale one-shot load.
            $demoSeedVersion.withLock { $0 += 1 }
            statusMessage = "Loaded \(phaseLabel(phase)) phase. Open Home to see the recommended action."
        } catch {
            statusMessage = "Load phase error: \(error)"
        }
    }

    private func phaseLabel(_ phase: StudyPhase) -> String {
        switch phase {
        case .foundation: "Foundation"
        case .discrimination: "Discrimination"
        case .consolidation: "Consolidation"
        }
    }

    private static func iso(daysFromNow days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dumpDeckTree() {
        do {
            let tree = try decksService.fetchTree()
            var info = "\(tree.count) top-level decks\n"
            for node in tree {
                info += "  [\(node.id)] \(node.name) — new:\(node.counts.newCount) learn:\(node.counts.learnCount) review:\(node.counts.reviewCount)\n"
                for sub in node.children {
                    info += "    [\(sub.id)] \(sub.name)\n"
                }
            }
            statusMessage = info
            print("[Debug] DeckTree:\n\(info)")
        } catch {
            statusMessage = "DeckTree error: \(error)"
            print("[Debug] DeckTree error: \(error)")
        }
    }

    private func resetEverything() {
        KeychainHelper.deleteHostKey()
        try? backend.closeCollection()
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let ankiDir = appSupport.appendingPathComponent("AnkiCollection", isDirectory: true)
        try? FileManager.default.removeItem(at: ankiDir)
        statusMessage = "Reset complete. Please restart the app."
    }
}
