import SwiftUI
import AnkountantTheme

struct SettingsView: View {
    private enum SettingsRoute: Hashable {
        case appearance
        case profiles
        case syncServer
        case review
        case readerDisplay
        case dictionaries
        case tags
        case database
        case emptyCards
        case mediaCheck
        case templates
        case about
        #if DEBUG
        case debug
        #endif
    }

    var body: some View {
        Form {
            Section("Appearance") {
                NavigationLink("Theme & Appearance", value: SettingsRoute.appearance)
            }

            Section("Account") {
                NavigationLink("Profiles", value: SettingsRoute.profiles)
                NavigationLink("Sync Server", value: SettingsRoute.syncServer)
            }

            Section("Review") {
                NavigationLink("Review Behavior", value: SettingsRoute.review)
            }

            Section("Reader") {
                NavigationLink("Reader Display", value: SettingsRoute.readerDisplay)
                NavigationLink("Dictionaries", value: SettingsRoute.dictionaries)
            }

            Section("Tags") {
                NavigationLink("Manage Tags", value: SettingsRoute.tags)
            }

            Section("Maintenance") {
                NavigationLink("Database", value: SettingsRoute.database)
                NavigationLink("Empty Cards", value: SettingsRoute.emptyCards)
                NavigationLink("Media Check", value: SettingsRoute.mediaCheck)
            }

            Section("Card Templates") {
                NavigationLink("Manage Templates", value: SettingsRoute.templates)
            }

            Section {
                NavigationLink("About", value: SettingsRoute.about)
            }

            #if DEBUG
            Section("Developer") {
                NavigationLink("Debug", value: SettingsRoute.debug)
            }
            #endif
        }
        .ankountantTabBarClearance()
        .navigationTitle("Settings")
        .navigationDestination(for: SettingsRoute.self) { route in
            destination(for: route)
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .appearance:
            AppearanceSettingsView(manager: .shared)
        case .profiles:
            AccountsSettingsView()
        case .syncServer:
            SyncSettingsView()
        case .review:
            ReviewSettingsView()
        case .readerDisplay:
            ReaderSettingsView()
        case .dictionaries:
            ReaderDictionarySettingsView()
        case .tags:
            TagsView()
        case .database:
            MaintenanceView()
        case .emptyCards:
            EmptyCardsView()
        case .mediaCheck:
            MediaCheckResultView()
        case .templates:
            DeckTemplateListView()
        case .about:
            AboutView()
        #if DEBUG
        case .debug:
            DebugView()
        #endif
        }
    }
}
