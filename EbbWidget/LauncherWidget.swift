//
//  LauncherWidget.swift
//  EbbWidget
//
//  The main Home Screen widget: up to six apps as plain text. Each app widget set up in
//  Ebb is its own list, and each placed widget picks one, so several widgets can stack
//  into a full Home Screen or spread across pages. Taps open apps directly; apps with a
//  mindful pause go through Ebb.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

struct AppListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App Widget"
    static let defaultQuery = AppListQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AppListQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AppListEntity] {
        let lists = AppWidgetList.loadAll()
        return identifiers.compactMap { id in
            lists.first { $0.id == id }.map { AppListEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [AppListEntity] {
        AppWidgetList.loadAll().map { AppListEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> AppListEntity? {
        AppWidgetList.loadAll().first.map { AppListEntity(id: $0.id, name: $0.name) }
    }
}

enum LauncherAlignment: String, AppEnum {
    case automatic, leading, center, trailing

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Alignment"
    static let caseDisplayRepresentations: [LauncherAlignment: DisplayRepresentation] = [
        .automatic: "Match Ebb", .leading: "Left", .center: "Center", .trailing: "Right",
    ]

    /// The alignment to draw with, resolving "Match Ebb" to the app's Widget style setting.
    var resolved: ListAlignment {
        switch self {
        case .automatic: WidgetStyle.alignment
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

enum LauncherTextSize: String, AppEnum {
    case automatic, small, medium, large

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Text Size"
    static let caseDisplayRepresentations: [LauncherTextSize: DisplayRepresentation] = [
        .automatic: "Match Ebb", .small: "Small", .medium: "Medium", .large: "Large",
    ]

    var resolved: ListTextSize {
        switch self {
        case .automatic: WidgetStyle.textSize
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }
}

struct LauncherConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Apps"
    static let description = IntentDescription("Choose which of your Ebb app widgets this shows. Set up app widgets in Ebb › Widgets.")

    @Parameter(title: "App Widget")
    var list: AppListEntity?

    @Parameter(title: "Alignment", default: .automatic)
    var alignment: LauncherAlignment

    @Parameter(title: "Text Size", default: .automatic)
    var textSize: LauncherTextSize

    @Parameter(title: "Show Clock", default: false)
    var showClock: Bool
}

/// Opens an app straight from the widget. Running as an intent lets iOS open the URL
/// itself, instead of launching Ebb first the way a plain widget link does.
struct OpenLaunchURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Open App"
    static let isDiscoverable = false

    @Parameter(title: "URL")
    var url: URL

    init() {}

    init(url: URL) {
        self.url = url
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Timeline

struct LauncherEntry: TimelineEntry {
    enum Content {
        case apps([WidgetApp])
        /// The chosen app widget is past the free limit.
        case locked
    }

    let date: Date
    let content: Content
    let configuration: LauncherConfigurationIntent
}

struct LauncherProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: .now, content: .apps(Self.sampleApps), configuration: LauncherConfigurationIntent())
    }

    func snapshot(for configuration: LauncherConfigurationIntent, in context: Context) async -> LauncherEntry {
        let content = resolve(configuration)
        if case .apps(let apps) = content, apps.isEmpty {
            return LauncherEntry(date: .now, content: .apps(Self.sampleApps), configuration: configuration)
        }
        return LauncherEntry(date: .now, content: content, configuration: configuration)
    }

    func timeline(for configuration: LauncherConfigurationIntent, in context: Context) async -> Timeline<LauncherEntry> {
        // Ebb reloads widgets whenever apps or colors change; the clock text ticks by itself.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(24 * 60 * 60))
        return Timeline(
            entries: [LauncherEntry(date: .now, content: resolve(configuration), configuration: configuration)],
            policy: .after(midnight)
        )
    }

    /// The chosen app widget's apps in order, falling back to the first app widget.
    private func resolve(_ configuration: LauncherConfigurationIntent) -> LauncherEntry.Content {
        let lists = AppWidgetList.loadAll()
        let index = configuration.list.flatMap { chosen in lists.firstIndex { $0.id == chosen.id } } ?? 0
        guard lists.indices.contains(index) else { return .apps([]) }
        if index >= EbbPlus.maxAppWidgets { return .locked }
        let apps = WidgetApp.loadAll()
        return .apps(lists[index].appIDs.compactMap { id in apps.first { $0.id == id } })
    }

    static let sampleApps = ["Phone", "Messages", "Calendar", "Maps", "Music", "Notes"].map {
        WidgetApp(id: UUID(), name: $0, url: nil, isMindful: false)
    }
}

// MARK: - View

struct LauncherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LauncherEntry

    var body: some View {
        Group {
            switch entry.content {
            case .apps(let apps):
                appsView(apps)
            case .locked:
                VStack(spacing: 6) {
                    Image(systemName: "lock")
                    Text("Ebb Plus")
                        .font(.headline)
                    Text("This app widget needs Plus.")
                        .font(.caption)
                        .opacity(0.7)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .ebbWidgetStyle()
    }

    @ViewBuilder
    private func appsView(_ apps: [WidgetApp]) -> some View {
        let config = entry.configuration
        let alignment = config.alignment.resolved
        let showClock = config.showClock && family == .systemLarge
        let apps = Array(apps.prefix(AppWidgetList.capacity))

        VStack(alignment: alignment.horizontal, spacing: 6) {
            if showClock {
                Text(entry.date, style: .time)
                    .font(.system(size: textSize * 1.8, weight: .thin))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 6)
            }
            if apps.isEmpty {
                Text("Open Ebb to add apps")
                    .font(.footnote)
                    .opacity(0.6)
            } else if family == .systemMedium {
                // Two columns of three.
                HStack(alignment: .top, spacing: 12) {
                    column(Array(apps.prefix(3)), alignment: alignment)
                    column(Array(apps.dropFirst(3)), alignment: alignment)
                }
            } else {
                column(apps, alignment: alignment)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: Alignment(horizontal: alignment.horizontal, vertical: .center))
    }

    private func column(_ apps: [WidgetApp], alignment: ListAlignment) -> some View {
        VStack(alignment: alignment.horizontal, spacing: rowSpacing) {
            ForEach(apps) { app in
                Button(intent: OpenLaunchURLIntent(url: app.widgetURL)) {
                    Text(app.name)
                        .font(.system(size: textSize, weight: .light))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: alignment.frame)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment.frame)
    }

    /// Six rows have to fit every size, so small widgets use tighter text.
    private var textSize: CGFloat {
        let preferred = entry.configuration.textSize.resolved.points
        switch family {
        case .systemSmall: return min(preferred, 15)
        case .systemMedium: return min(preferred, 20)
        default: return preferred
        }
    }

    private var rowSpacing: CGFloat {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 6
        default: textSize * 0.55
        }
    }
}

struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbLauncher.apps", intent: LauncherConfigurationIntent.self, provider: LauncherProvider()) { entry in
            LauncherWidgetView(entry: entry)
        }
        .configurationDisplayName("Apps")
        .description("Six apps as plain text. Add one for each app widget you set up in Ebb, then long-press › Edit Widget to choose which.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Shared style

extension View {
    /// Ebb's colors from shared settings, so widgets blend into a matching wallpaper.
    func ebbWidgetStyle() -> some View {
        modifier(EbbWidgetStyle())
    }
}

private struct EbbWidgetStyle: ViewModifier {
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        let isAccessory = [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
        if isAccessory {
            // Lock Screen widgets are tinted by the system.
            content.containerBackground(.clear, for: .widget)
        } else {
            content
                .fontDesign(WidgetStyle.typeface.design)
                .foregroundStyle(Appearance.text.color)
                .containerBackground(Appearance.background.color, for: .widget)
        }
    }
}

#Preview(as: .systemMedium) {
    LauncherWidget()
} timeline: {
    LauncherEntry(date: .now, content: .apps(LauncherProvider.sampleApps), configuration: LauncherConfigurationIntent())
}
