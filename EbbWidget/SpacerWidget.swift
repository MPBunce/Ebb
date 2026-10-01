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

struct SpacerProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpacerEntry { SpacerEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (SpacerEntry) -> Void) {
        completion(SpacerEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpacerEntry>) -> Void) {
        // Ebb reloads widgets when the color changes, so nothing to schedule.
        completion(Timeline(entries: [SpacerEntry(date: .now)], policy: .never))
    }
}

struct SpacerEntry: TimelineEntry {
    let date: Date
}

struct SpacerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EbbSpacer", provider: SpacerProvider()) { _ in
            Button(intent: SpacerTapIntent()) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .ebbWidgetStyle()
        }
        .configurationDisplayName("Spacer")
        .description("An empty block in your widget color, to space out your Home Screen.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
