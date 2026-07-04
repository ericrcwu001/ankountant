// AnkountantApp/Sources/AnkountantAppApp.swift
import BackgroundTasks
import SwiftUI
import AnkountantReader
import AnkountantReaderDictionary
import AnkountantTheme
import AnkiBackend
import AnkiSync
import Dependencies
import Foundation
import Sharing

@main
struct AnkiAppApp: App {
    @Shared(.onboardingCompleted) private var onboardingCompleted
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingReviewDeckId: Int64? = nil

    private var destination: Destination {
        onboardingCompleted ? .main : .onboarding
    }

    init() {
        // Sharing namespaces @Shared(.appStorage:) keys per profile with a "."
        // separator (e.g. "sync_pref_needs_full_sync.default"). KVO can't observe
        // dotted keys, so Sharing logs a format warning and silently falls back to
        // NotificationCenter. Cross-process observation of these keys isn't needed
        // (they're SyncCoordinator-internal), so silence the warning. This must run
        // before any dotted @Shared key is created, hence its own prepare call.
        prepareDependencies {
            $0.appStorageKeyFormatWarningEnabled = false
        }

        #if DEBUG
//        if KeychainHelper.loadEndpoint() == nil {
//            try? KeychainHelper.saveEndpoint("https://sync.ankiweb.net")
//            @Shared(.syncMode) var syncMode
//            $syncMode.withLock { $0 = .custom }
//            $onboardingCompleted.withLock { $0 = true }
//        }
        #endif

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.ankountantapp.AnkountantApp.widget-refresh",
            using: nil
        ) { @Sendable task in
            handleWidgetRefreshTask(task)
        }
        scheduleWidgetRefreshTask()

        // Multi-profile bootstrap: migrate legacy single-collection
        // layout into the default profile, then resolve the active
        // profile (consuming a pending switch from the previous session
        // if one was queued in Settings → Profiles).
        try! AccountStore.migrateLegacyCollectionIfNeeded()
        let activeProfile = MainActor.assumeIsolated {
            AccountStore.shared.consumePendingSwitch()
        }

        try! prepareDependencies {
            let backend = try AnkiBackend(preferredLangs: ["en"])

            let ankiDir = AccountStore.profileDirectory(for: activeProfile.id)
            try FileManager.default.createDirectory(at: ankiDir, withIntermediateDirectories: true)

            let collectionPath = ankiDir.appendingPathComponent("collection.anki2").path
            let mediaPath = ankiDir.appendingPathComponent("media").path
            let mediaDbPath = ankiDir.appendingPathComponent("media.db").path
            try FileManager.default.createDirectory(
                atPath: mediaPath, withIntermediateDirectories: true
            )

            try backend.openCollection(
                collectionPath: collectionPath,
                mediaFolderPath: mediaPath,
                mediaDbPath: mediaDbPath
            )
            try? backend.checkDatabase()
            $0.ankiBackend = backend
            $0.syncCoordinator = SyncCoordinator()
            // Wire the Anki-backed concrete realization of the dictionary
            // engine's abstract config store. Keeps the engine package
            // (AnkountantReaderDictionary) free of Anki imports.
            $0.dictionaryConfigStore = AnkiBackedDictionaryConfigStore.makeStore()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch destination {
                case .onboarding:
                    OnboardingView()
                case .main:
                    ContentView(pendingReviewDeckId: $pendingReviewDeckId)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await writeWidgetSnapshot() }
                }
            }
            .onOpenURL { url in
                guard url.scheme == "ankountant",
                      url.host == "review",
                      let deckIdStr = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "deckId" })?.value,
                      let deckId = Int64(deckIdStr)
                else { return }
                pendingReviewDeckId = deckId
            }
            .themedRoot()
        }
    }
}

private extension AnkiAppApp {
    enum Destination {
        case onboarding
        case main
    }
}

private struct UncheckedSendableBox<T>: @unchecked Sendable { let value: T }

private func handleWidgetRefreshTask(_ task: BGTask) {
    let box = UncheckedSendableBox(value: task)
    let work = Task {
        await writeWidgetSnapshot()
        box.value.setTaskCompleted(success: true)
        scheduleWidgetRefreshTask()
    }
    task.expirationHandler = {
        work.cancel()
        box.value.setTaskCompleted(success: false)
    }
}

/// Schedules a BGAppRefreshTask to fire shortly after the next midnight.
/// The task writes a fresh widget snapshot so the widget shows today's counts
/// even if the user hasn't opened the app yet.
private func scheduleWidgetRefreshTask() {
    let request = BGAppRefreshTaskRequest(identifier: "com.ankountantapp.AnkountantApp.widget-refresh")
    let cal = Calendar.current
    let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date())
    // Fire 5 minutes after midnight so Anki's day rollover has settled.
    request.earliestBeginDate = cal.date(byAdding: .minute, value: 5, to: tomorrow) ?? tomorrow
    try? BGTaskScheduler.shared.submit(request)
}
