//
//  Routines.swift
//  Shared between Ebb and its widgets.
//
//  Ebb Plus habits and to-dos. Both live in the App Group so the widgets can check things
//  off and Ebb can edit them. Checked-off to-dos disappear once the day they were checked
//  is over, so each morning starts with only what's left.
//

import Foundation

/// A calendar day as "yyyy-MM-dd", so completions don't shift with time zones or DST.
nonisolated enum DayKey {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The start of the day a key names.
    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The `count` days ending with `date`, oldest first.
    static func days(endingOn date: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

// MARK: - Habits

nonisolated struct Habit: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Days it was done, as `DayKey`s.
    var completions: Set<String> = []

    func isDone(on date: Date, calendar: Calendar = .current) -> Bool {
        completions.contains(DayKey.key(for: date, calendar: calendar))
    }

    mutating func toggle(on date: Date, calendar: Calendar = .current) {
        let key = DayKey.key(for: date, calendar: calendar)
        if completions.contains(key) { completions.remove(key) } else { completions.insert(key) }
    }

    /// Days in a row it's been done, ending today, or yesterday if today isn't done yet
    /// (so a streak doesn't look broken first thing in the morning).
    func streak(asOf date: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: date)
        if !isDone(on: day, calendar: calendar) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while isDone(on: day, calendar: calendar) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

nonisolated extension Habit {
    /// The longest run of consecutive days it's ever been done.
    func longestStreak(calendar: Calendar = .current) -> Int {
        let days = completions.compactMap { DayKey.date(from: $0, calendar: calendar) }.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// How many of the `days` days ending with `date` it was done.
    func doneCount(lastDays days: Int, endingOn date: Date, calendar: Calendar = .current) -> Int {
        DayKey.days(endingOn: date, count: days, calendar: calendar).filter { isDone(on: $0, calendar: calendar) }.count
    }
}

nonisolated enum HabitStore {
    private static let key = "habits"
    /// Completions older than this are dropped to keep the shared store small.
    private static let historyDays = 400

    static func load() -> [Habit] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Habit].self, from: data)) ?? []
    }

    static func save(_ habits: [Habit], now: Date = .now) {
        let cutoff = DayKey.key(for: Calendar.current.date(byAdding: .day, value: -historyDays, to: now) ?? now)
        let trimmed = habits.map { habit in
            var habit = habit
            habit.completions = habit.completions.filter { $0 >= cutoff }
            return habit
        }
        if let data = try? JSONEncoder().encode(trimmed) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    static func toggle(id: UUID, on date: Date = .now) {
        var habits = load()
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[index].toggle(on: date)
        save(habits, now: date)
    }
}

// MARK: - To-dos

nonisolated struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    /// When it was checked off; nil while it's still to do.
    var completedAt: Date?

    var isDone: Bool { completedAt != nil }
}

nonisolated enum TodoStore {
    private static let key = "todos"

    /// The list as it should look at `date`: anything checked off before that day is gone.
    /// This never changes what's saved, because widgets draw their future entries ahead of
    /// time (like the one for after midnight) and that mustn't clear today's checked items.
    static func load(asOf date: Date = .now, calendar: Calendar = .current) -> [TodoItem] {
        clearingFinished(stored(), now: date, calendar: calendar)
    }

    /// Everything saved, including items finished on earlier days.
    private static func stored() -> [TodoItem] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([TodoItem].self, from: data) else { return [] }
        return items
    }

    /// Drops items checked off on an earlier day.
    static func clearingFinished(_ items: [TodoItem], now: Date, calendar: Calendar = .current) -> [TodoItem] {
        let today = calendar.startOfDay(for: now)
        return items.filter { item in
            guard let done = item.completedAt else { return true }
            return done >= today
        }
    }

    static func save(_ items: [TodoItem]) {
        if let data = try? JSONEncoder().encode(items) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    static func toggle(id: UUID, now: Date = .now) {
        // Clearing old finished items here is safe: `now` is the real time of the tap.
        var items = load(asOf: now)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].completedAt = items[index].isDone ? nil : now
        save(items)
    }

    /// Still to do first (in the order added), then today's finished ones.
    static func ordered(_ items: [TodoItem]) -> [TodoItem] {
        items.filter { !$0.isDone } + items.filter(\.isDone)
    }

    /// What a widget with room for `limit` rows shows. Checked items stay crossed out where
    /// they are, for the satisfaction of seeing them, as long as everything fits; when it
    /// doesn't, unfinished items get the room first.
    static func shown(_ items: [TodoItem], limit: Int) -> [TodoItem] {
        if items.count <= limit { return items }
        return Array(ordered(items).prefix(limit))
    }
}

/// When the to-do list next clears and habit checkmarks reset.
nonisolated enum Midnight {
    static func next(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
    }
}
