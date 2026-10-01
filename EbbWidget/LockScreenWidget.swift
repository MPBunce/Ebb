//
//  LockScreenWidget.swift
//  EbbWidget
//
//  A quiet Lock Screen / Home Screen entry point back into Ebb.
//

import SwiftUI
import WidgetKit

struct LockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack {
                Image(systemName: "water.waves")
                Text("Ebb")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall, .systemMedium, .systemLarge:
            let saved = TimeSaved.load()
            VStack(spacing: family == .systemLarge ? 14 : 6) {
                Image(systemName: "water.waves")
                    .font(.system(size: family == .systemLarge ? 64 : 34, weight: .light))
                Text("ebb")
                    .font(.system(size: family == .systemLarge ? 40 : 22, weight: .thin))
                if family != .systemSmall {
                    Text("\(saved.formattedHours) hours given back")
                        .font(.caption)
                        .opacity(0.6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "water.waves")
                    .font(.title2)
            }
        }
    }
}

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EbbOpen", provider: LockScreenProvider()) { _ in
            LockScreenWidgetView()
                .ebbWidgetStyle()
                .widgetURL(DeepLink.home.url)
        }
        .configurationDisplayName("Open Ebb")
        .description("One tap back to your calm home screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium, .systemLarge])
    }
}
