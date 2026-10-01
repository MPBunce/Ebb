//
//  Insights.swift
//  Ebb
//
//  Summaries of launch history. Only launches made through Ebb are counted.
//

import Foundation

struct Insights {
    struct Day: Identifiable, Hashable {
        var date: Date
        var opened: Int
        var resisted: Int
        var id: Date { date }
    }

    struct AppCount: Identifiable, Hashable {
        var name: String
        var count: Int
        var id: String { name }
    }

    var today: Day
    var week: [Day]
    var topApps: [AppCount]
    /// Consecutive days, ending today, where at least one open was resisted.
    var resistStreak: Int
    var recentIntentions: [LaunchEvent]

    init(events: [LaunchEvent], now: Date = .now, calendar: Calendar = .current) {
        let startOfToday = calendar.startOfDay(for: now)
        let days: [Date] = (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: startOfToday)
        }

        let byDay = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        func summary(for day: Date) -> Day {
            let dayEvents = byDay[day] ?? []
            return Day(
                date: day,
                opened: dayEvents.count { $0.outcome == .opened },
                resisted: dayEvents.count { $0.outcome == .resisted }
            )
        }

        week = days.map(summary(for:))
        today = summary(for: startOfToday)

        let weekStart = days.first ?? startOfToday
        let weekOpens = events.filter { $0.outcome == .opened && $0.date >= weekStart }
        topApps = Dictionary(grouping: weekOpens, by: \.name)
            .map { AppCount(name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(5)
            .map { $0 }

        var streak = 0
        var day = startOfToday
        while summary(for: day).resisted > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        resistStreak = streak

        recentIntentions = events
            .filter { $0.intention != nil }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }
}
