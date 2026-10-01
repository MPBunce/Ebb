//
//  AppGroup.swift
//  Shared between Ebb and its extensions.
//

import Foundation

/// Identifiers and storage shared by the app, the widget, and the Screen Time extensions.
nonisolated enum AppGroup {
    static let identifier = "group.mpbunce.Ebb"

    /// Shared defaults. Falls back to `.standard` when the app group is unavailable
    /// (e.g. unsigned simulator builds) so the app still works on its own.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Directory for shared JSON files.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        return URL.applicationSupportDirectory
    }

    enum Key {
        static let widgetApps = "widgetApps"
        static let backgroundHex = "backgroundHex"
        static let textHex = "textHex"
        static let shieldTitle = "shieldTitle"
        static let shieldSubtitle = "shieldSubtitle"
        static let birthDate = "birthDate"
        static let sex = "sex"
        static let installDate = "installDate"
        static let lifetimeResisted = "lifetimeResisted"
        static let lifetimeFocusMinutes = "lifetimeFocusMinutes"
        static let minutesPerResist = "minutesPerResist"
        static let listAlignment = "listAlignment"
        static let listTextSize = "listTextSize"
        static let typeface = "typeface"
        static let wallpaperSaved = "wallpaperSaved"
        static let wallpaperSet = "wallpaperSet"
    }
}

/// A copy of each app the user added, written by Ebb and read by the widgets.
nonisolated struct WidgetApp: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    /// Where the app opens: its URL scheme, Shortcut, or website.
    var url: URL?
    var isMindful: Bool

    /// Widgets open apps directly, so there's no stop in Ebb on the way. Mindful apps
    /// (or ones without a working link) go through Ebb for the pause instead.
    var widgetURL: URL {
        if isMindful { return DeepLink.launch(id).url }
        return url ?? DeepLink.launch(id).url
    }

    static func loadAll() -> [WidgetApp] {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.Key.widgetApps) else { return [] }
        return (try? JSONDecoder().decode([WidgetApp].self, from: data)) ?? []
    }

    static func save(_ apps: [WidgetApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        AppGroup.defaults.set(data, forKey: AppGroup.Key.widgetApps)
    }
}

/// Deep links into Ebb (`ebb://home`, `ebb://launch/<id>`, `ebb://focus`).
nonisolated enum DeepLink: Equatable {
    case home
    case launch(UUID)
    case focus

    static let scheme = "ebb"

    var url: URL {
        switch self {
        case .home: URL(string: "ebb://home")!
        case .launch(let id): URL(string: "ebb://launch/\(id.uuidString)")!
        case .focus: URL(string: "ebb://focus")!
        }
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host() {
        case "home":
            self = .home
        case "focus":
            self = .focus
        case "launch":
            guard let raw = url.pathComponents.dropFirst().first, let id = UUID(uuidString: raw) else { return nil }
            self = .launch(id)
        default:
            return nil
        }
    }
}

/// The notification the block screen sends to start a breather in Ebb.
nonisolated enum BreatherNotification {
    static let kind = "ebb.breather"
    static let kindKey = "kind"
}
