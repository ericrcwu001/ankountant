// AnkountantApp/Sources/Widgets/AnkountantWidget.swift
import WidgetKit
import SwiftUI
import AnkountantTheme

struct AnkountantWidget: Widget {
    let kind = "AnkountantWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: AnkountantWidgetIntent.self,
            provider: WidgetTimelineProvider()
        ) { entry in
            AnkountantWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ankountant")
        .description("See your cards due today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AnkountantWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: WidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(snapshot: entry.snapshot)
            case .systemMedium:
                MediumWidgetView(snapshot: entry.snapshot)
            case .systemLarge:
                LargeWidgetView(snapshot: entry.snapshot)
            default:
                SmallWidgetView(snapshot: entry.snapshot)
            }
        }
        .environment(\.palette, ThemeManager.shared.palette(for: colorScheme))
    }
}
