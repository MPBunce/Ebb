//
//  SpacerWidget.swift
//  EbbWidget
//
//  An empty block in the widget color, for spacing out the Home Screen. On a matching
//  wallpaper it disappears completely. Taps do nothing instead of opening Ebb.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Swallows taps so the spacer doesn't launch Ebb.
struct SpacerTapIntent: AppIntent {
    static let title: LocalizedStringResource = "Spacer"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult { .result() }
}

struct SpacerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SpacerEntry { SpacerEntry(date: .now, spot: nil) }

    func snapshot(for configuration: PositionIntent, in context: Context) async -> SpacerEntry {
        SpacerEntry(date: .now, spot: configuration.spot)
    }

    func timeline(for configuration: PositionIntent, in context: Context) async -> Timeline<SpacerEntry> {
        // Ebb reloads widgets when the color or wallpaper changes, so nothing to schedule.
        Timeline(entries: [SpacerEntry(date: .now, spot: configuration.spot)], policy: .never)
    }
}

struct SpacerEntry: TimelineEntry {
    let date: Date
    let spot: WidgetSpot?
}

struct SpacerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbSpacer", intent: PositionIntent.self, provider: SpacerProvider()) { entry in
            Button(intent: SpacerTapIntent()) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .ebbWidgetStyle(spot: entry.spot)
        }
        .configurationDisplayName("Spacer")
        .description("An empty block in your widget color, to space out your Home Screen.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
