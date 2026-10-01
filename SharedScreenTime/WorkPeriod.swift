//
//  WorkPeriod.swift
//  Shared between Ebb and its Screen Time extensions.
//
//  Scheduled stretches of time when everything is blocked except the apps the user allows.
//

import DeviceActivity
import Foundation

nonisolated struct WorkPeriod: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = "Work"
    /// Minutes after midnight.
    var start = 9 * 60
    var end = 17 * 60
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var isEnabled = true

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
