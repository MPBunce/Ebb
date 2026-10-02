//
//  WorkPeriod.swift
//  Shared between Ebb and its Screen Time extensions.
//
//  A scheduled focus: on chosen days and hours, block the apps the user picked for it
//  (or, in "allow only" mode, everything except them).
//

import DeviceActivity
import FamilyControls
import Foundation

/// What a focus does with its apps.
nonisolated enum FocusBlockMode: String, Codable, CaseIterable, Identifiable {
    /// Block the chosen apps; everything else stays open.
    case blockSelected
    /// Block everything except the chosen apps.
    case allowOnly

    var id: Self { self }

    var label: String {
        switch self {
        case .blockSelected: "Block these apps"
        case .allowOnly: "Allow only these"
        }
    }
}

nonisolated struct WorkPeriod: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Work"
    /// Minutes after midnight.
    var start = 9 * 60
    var end = 17 * 60
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var isEnabled = true
    var mode = FocusBlockMode.blockSelected
    /// The apps, categories, and sites this focus blocks (or allows, in allow-only mode).
    var selection = FamilyActivitySelection()

    var hasApps: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    /// "3 apps blocked", "Only 2 apps allowed", or a prompt to choose.
    var appsSummary: String {
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let sites = selection.webDomainTokens.count
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        guard !parts.isEmpty else { return mode == .allowOnly ? "Blocks everything" : "No apps chosen" }
        let list = parts.joined(separator: ", ")
        return mode == .allowOnly ? "Only \(list) allowed" : "\(list) blocked"
    }

    static let activityPrefix = "ebb.work."

    var activityName: DeviceActivityName { DeviceActivityName(Self.activityPrefix + id.uuidString) }

    /// Whether the period applies on the day containing `date`. Periods that cross midnight
    /// belong to the day they start.
    func applies(on date: Date, calendar: Calendar = .current) -> Bool {
        weekdays.contains(calendar.component(.weekday, from: date))
    }

    /// Whether `date` is inside this period right now.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start < end {
            return minute >= start && minute < end && applies(on: date, calendar: calendar)
        }
        // Crosses midnight: the evening part belongs to today, the morning part to yesterday.
        if minute >= start { return applies(on: date, calendar: calendar) }
        if minute < end, let yesterday = calendar.date(byAdding: .day, value: -1, to: date) {
            return applies(on: yesterday, calendar: calendar)
        }
        return false
    }

    var timeRange: String {
        "\(Self.format(start))–\(Self.format(end))"
    }

    var daysDescription: String {
        let sorted = weekdays.sorted()
        if sorted == [2, 3, 4, 5, 6] { return "Weekdays" }
        if sorted == [1, 7] { return "Weekends" }
        if sorted.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return sorted.map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    static func format(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case id, name, start, end, weekdays, isEnabled, mode, selection
    }

    // MARK: Storage

    private static let key = "workPeriods"

    static func loadAll() -> [WorkPeriod] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WorkPeriod].self, from: data)) ?? []
    }

    static func saveAll(_ periods: [WorkPeriod]) {
        guard let data = try? JSONEncoder().encode(periods) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }

    static func period(for activity: DeviceActivityName) -> WorkPeriod? {
        guard activity.rawValue.hasPrefix(activityPrefix) else { return nil }
        let id = String(activity.rawValue.dropFirst(activityPrefix.count))
        return loadAll().first { $0.id.uuidString == id }
    }
}


nonisolated extension WorkPeriod {
    /// Periods saved before focuses had their own apps decode with defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        start = try c.decode(Int.self, forKey: .start)
        end = try c.decode(Int.self, forKey: .end)
        weekdays = try c.decode(Set<Int>.self, forKey: .weekdays)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        mode = try c.decodeIfPresent(FocusBlockMode.self, forKey: .mode) ?? .blockSelected
        selection = try c.decodeIfPresent(FamilyActivitySelection.self, forKey: .selection) ?? FamilyActivitySelection()
    }
}
