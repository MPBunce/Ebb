//
//  Plan.swift
//  Shared between Ebb and its widgets.
//
//  What's free and what's part of Ebb Plus. Purchases aren't wired up yet; when they are,
//  they only need to set `EbbPlus.isActive`.
//

import Foundation

nonisolated enum EbbPlus {
    private static let key = "ebbPlusActive"

    /// Whether Plus features are unlocked. Set by purchases later, or the debug switch for now.
    static var isActive: Bool {
        get { AppGroup.defaults.bool(forKey: key) }
        set { AppGroup.defaults.set(newValue, forKey: key) }
    }

    static let freeAppWidgets = 2
    /// Plus adds six more app widgets.
    static let plusAppWidgets = freeAppWidgets + 6

    static var maxAppWidgets: Int { isActive ? plusAppWidgets : freeAppWidgets }
}

/// One Apps widget's worth of apps: up to six, in order.
nonisolated struct AppWidgetList: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var appIDs: [UUID] = []

    static let capacity = 6

    var isFull: Bool { appIDs.count >= Self.capacity }

    // MARK: Shared copy for the widget

    private static let key = "appWidgetLists"

    static func loadAll() -> [AppWidgetList] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AppWidgetList].self, from: data)) ?? []
    }

    static func saveAll(_ lists: [AppWidgetList]) {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }
}

/// Looks for the Clock widget. Plus styles show an upgrade message for free users.
nonisolated enum ClockStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case digital, analog, stacked, words, dayRing

    var id: Self { self }

    var name: String {
        switch self {
        case .digital: "Digital"
        case .analog: "Analog"
        case .stacked: "Stacked"
        case .words: "Words"
        case .dayRing: "Day ring"
        }
    }

    var summary: String {
        switch self {
        case .digital: "The time in thin numerals, with the date."
        case .analog: "Two quiet hands, no numbers."
        case .stacked: "Big hour over minutes."
        case .words: "The time written out, like “twenty to eleven”."
        case .dayRing: "The time inside a ring of how much of the day has passed."
        }
    }

    var isPlus: Bool {
        switch self {
        case .digital, .analog: false
        case .stacked, .words, .dayRing: true
        }
    }

    var isUnlocked: Bool { !isPlus || EbbPlus.isActive }
}

/// Writes the time out in words, e.g. "quarter past nine" or "twenty to eleven".
nonisolated enum TimeInWords {
    private static let numbers = [
        "twelve", "one", "two", "three", "four", "five", "six",
        "seven", "eight", "nine", "ten", "eleven", "twelve",
    ]

    static func phrase(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        // Round to the nearest five minutes, the way people say the time.
        let rounded = Int((Double(parts.minute ?? 0) / 5).rounded()) * 5
        let minute = rounded % 60
        let displayHour = rounded == 60 ? hour + 1 : hour

        let current = numbers[displayHour % 12]
        let next = numbers[(displayHour + 1) % 12]

        switch minute {
        case 0:
            if displayHour % 24 == 0 { return "midnight" }
            if displayHour % 24 == 12 { return "noon" }
            return "\(current) o’clock"
        case 15: return "quarter past \(current)"
        case 30: return "half past \(current)"
        case 45: return "quarter to \(next)"
        case 5, 10, 20: return "\(words(minute)) past \(current)"
        case 25: return "twenty-five past \(current)"
        case 35: return "twenty-five to \(next)"
        default: return "\(words(60 - minute)) to \(next)"
        }
    }

    private static func words(_ minutes: Int) -> String {
        switch minutes {
        case 5: "five"
        case 10: "ten"
        case 20: "twenty"
        case 25: "twenty-five"
        default: "\(minutes)"
        }
    }
}
