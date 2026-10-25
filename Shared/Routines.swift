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

/// Which days a habit is meant for.
nonisolated enum HabitSchedule: Codable, Equatable, Hashable {
    case daily
    /// Calendar weekday numbers (1 is Sunday).
    case days(Set<Int>)
    /// Any days, this many times a week.
    case weekly(Int)

    static let weekdays: HabitSchedule = .days([2, 3, 4, 5, 6])

    func isScheduled(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily, .weekly: true
        case .days(let days): days.contains(calendar.component(.weekday, from: date))
        }
    }

    var isWeekly: Bool {
        if case .weekly = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .daily: return "Every day"
        case .weekly(let n): return "\(n)× a week"
        case .days(let days):
            if days == [2, 3, 4, 5, 6] { return "Weekdays" }
            if days == [1, 7] { return "Weekends" }
            if days.count == 7 { return "Every day" }
            let symbols = Calendar.current.shortWeekdaySymbols
            // Monday first, the way most people read a week.
            return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
        }
    }
}

/// Habits Ebb can tick off by itself, from what it already sees.
nonisolated enum HabitAuto: String, Codable, CaseIterable, Identifiable {
    /// A focus session ran to its end.
    case focusSession
    /// You backed out of an app at a mindful pause, a breather, or the block screen.
    case letGo
    /// Your daily limit wasn't reached. Only known once the day is over.
    case underLimit

    var id: Self { self }

    var defaultName: String {
        switch self {
        case .focusSession: "Finish a focus session"
        case .letGo: "Resist an app"
        case .underLimit: "Stay under my daily limit"
        }
    }

    var detail: String {
        switch self {
        case .focusSession: "Ticks itself when a focus session runs to the end."
        case .letGo: "Ticks itself when you back out of an app at a pause or the block screen."
        case .underLimit: "Ticks itself the day after, if you didn't hit your daily limit."
        }
    }

    /// Where the days it happened are kept, shared with the Screen Time extensions.
    var logKey: String {
        switch self {
        case .focusSession: DayLog.focusFinished
        case .letGo: DayLog.letGo
        case .underLimit: DayLog.limitReached
        }
    }
}

/// Days something happened, kept in the App Group by whichever part of Ebb saw it.
nonisolated enum DayLog {
    static let focusFinished = "dayLogFocusFinished"
    static let letGo = "dayLogLetGo"
    static let limitReached = "dayLogLimitReached"

    static func days(_ key: String) -> Set<String> {
        Set(AppGroup.defaults.stringArray(forKey: key) ?? [])
    }

    static func add(_ key: String, on date: Date = .now) {
        var days = days(key)
        days.insert(DayKey.key(for: date))
        // A year is plenty for streaks and the history map.
        let cutoff = DayKey.key(for: Calendar.current.date(byAdding: .day, value: -400, to: date) ?? date)
        AppGroup.defaults.set(days.filter { $0 >= cutoff }.sorted(), forKey: key)
    }
}

nonisolated struct Habit: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Days it was done, as `DayKey`s.
    var completions: Set<String> = []
    /// Nil for habits made before Ebb kept it; their first completion stands in.
    var createdAt: Date? = nil
    var schedule: HabitSchedule = .daily
    /// How many a day counts as done: 1 is a plain tick, more counts up (8 glasses).
    var target = 1
    /// Counts so far on days that haven't reached the target, by `DayKey`.
    var progress: [String: Int] = [:]
    /// One missed day a week doesn't break the streak.
    var allowsSkip = false
    /// Minutes after midnight for a reminder on days it isn't done yet.
    var reminderMinutes: Int? = nil
    var auto: HabitAuto? = nil
    var isArchived = false
    /// Habit stacking: the thing it follows, like "I pour my morning coffee".
    var cue: String? = nil
    /// The two-minute version for hard days, like "put on my running shoes".
    var tinyVersion: String? = nil

    var isCounted: Bool { target > 1 }

    /// "After I pour my morning coffee", ready to show under the name.
    var cueText: String? {
        guard let cue = cue?.trimmingCharacters(in: .whitespaces), !cue.isEmpty else { return nil }
        let lower = cue.lowercased()
        if lower.hasPrefix("after") || lower.hasPrefix("when") || lower.hasPrefix("before") || lower.hasPrefix("at ") { return cue }
        return "After " + cue
    }

    func isDone(on date: Date, calendar: Calendar = .current) -> Bool {
        completions.contains(DayKey.key(for: date, calendar: calendar))
    }

    /// How many it's at on a day: the target once done.
    func count(on date: Date, calendar: Calendar = .current) -> Int {
        isDone(on: date, calendar: calendar) ? target : progress[DayKey.key(for: date, calendar: calendar)] ?? 0
    }

    /// A tap: ticks a plain habit on or off, or counts one more (back to zero once done).
    mutating func toggle(on date: Date, calendar: Calendar = .current) {
        let key = DayKey.key(for: date, calendar: calendar)
        if completions.contains(key) {
            completions.remove(key)
            progress[key] = nil
            return
        }
        let next = (progress[key] ?? 0) + 1
        if next >= target {
            completions.insert(key)
            progress[key] = nil
        } else {
            progress[key] = next
        }
    }

    /// One fewer, for counted habits.
    mutating func decrement(on date: Date, calendar: Calendar = .current) {
        let key = DayKey.key(for: date, calendar: calendar)
        let current = count(on: date, calendar: calendar)
        guard current > 0 else { return }
        completions.remove(key)
        progress[key] = current - 1 == 0 ? nil : current - 1
    }

    /// The first day it could have been done.
    func startDay(calendar: Calendar = .current) -> Date? {
        let first = completions.compactMap { DayKey.date(from: $0, calendar: calendar) }.min()
        let created = createdAt.map { calendar.startOfDay(for: $0) }
        switch (first, created) {
        case let (f?, c?): return min(f, c)
        case let (f?, nil): return f
        case let (nil, c?): return c
        default: return nil
        }
    }

    private func weekID(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (parts.yearForWeekOfYear ?? 0) * 100 + (parts.weekOfYear ?? 0)
    }

    /// Scheduled days in a row it's been done, ending today, or yesterday if today isn't
    /// done yet (so a streak doesn't look broken first thing in the morning). Days off don't
    /// count against it, and with skips allowed, one miss a week is forgiven. Weekly habits
    /// count weeks in a row that reached their target.
    func streak(asOf date: Date, calendar: Calendar = .current) -> Int {
        if case .weekly(let times) = schedule { return weekStreak(times: times, asOf: date, calendar: calendar) }
        let today = calendar.startOfDay(for: date)
        guard let start = startDay(calendar: calendar) else { return 0 }
        var day = today
        var count = 0
        var skipped: Set<Int> = []
        var steps = 0
        while day >= start, steps < 1500 {
            steps += 1
            defer { day = calendar.date(byAdding: .day, value: -1, to: day) ?? start.addingTimeInterval(-1) }
            guard schedule.isScheduled(day, calendar: calendar) else { continue }
            if isDone(on: day, calendar: calendar) {
                count += 1
            } else if day == today {
                continue
            } else if allowsSkip, !skipped.contains(weekID(day, calendar: calendar)) {
                skipped.insert(weekID(day, calendar: calendar))
            } else {
                break
            }
        }
        return count
    }

    /// Times done in the week containing `date`.
    func doneThisWeek(_ date: Date, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return completions.compactMap { DayKey.date(from: $0, calendar: calendar) }
            .filter { week.contains($0) }.count
    }

    private func weekStreak(times: Int, asOf date: Date, calendar: Calendar) -> Int {
        guard let start = startDay(calendar: calendar) else { return 0 }
        var week = date
        var count = 0
        var isCurrent = true
        while week >= (calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start) {
            if doneThisWeek(week, calendar: calendar) >= times {
                count += 1
            } else if !isCurrent {
                break
            }
            isCurrent = false
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return count
    }

    /// "5 days" or, for weekly habits, "3 weeks".
    func streakText(asOf date: Date = .now, short: Bool = false, calendar: Calendar = .current) -> String {
        let n = streak(asOf: date, calendar: calendar)
        if schedule.isWeekly { return short ? "\(n)w" : "\(n) week\(n == 1 ? "" : "s")" }
        return short ? "\(n)d" : "\(n) day\(n == 1 ? "" : "s")"
    }
}

nonisolated extension Habit {
    enum CodingKeys: String, CodingKey {
        case id, name, completions, createdAt, schedule, target, progress, allowsSkip, reminderMinutes, auto, isArchived
        case cue, tinyVersion
    }

    /// Habits saved by earlier versions only had a name and completions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        completions = try c.decodeIfPresent(Set<String>.self, forKey: .completions) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        schedule = try c.decodeIfPresent(HabitSchedule.self, forKey: .schedule) ?? .daily
        target = max(try c.decodeIfPresent(Int.self, forKey: .target) ?? 1, 1)
        progress = try c.decodeIfPresent([String: Int].self, forKey: .progress) ?? [:]
        allowsSkip = try c.decodeIfPresent(Bool.self, forKey: .allowsSkip) ?? false
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
        auto = try c.decodeIfPresent(HabitAuto.self, forKey: .auto)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        cue = try c.decodeIfPresent(String.self, forKey: .cue)
        tinyVersion = try c.decodeIfPresent(String.self, forKey: .tinyVersion)
    }

    /// The longest run it's ever had, by the same rules as `streak`.
    func longestStreak(asOf date: Date = .now, calendar: Calendar = .current) -> Int {
        guard let start = startDay(calendar: calendar) else { return 0 }
        let today = calendar.startOfDay(for: date)
        var best = 0
        var run = 0
        if case .weekly(let times) = schedule {
            var week = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            while week <= today {
                let isCurrent = calendar.isDate(week, equalTo: today, toGranularity: .weekOfYear)
                if doneThisWeek(week, calendar: calendar) >= times { run += 1 } else if !isCurrent { run = 0 }
                best = max(best, run)
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
                week = next
            }
            return best
        }
        var day = start
        var skipped: Set<Int> = []
        while day <= today {
            if schedule.isScheduled(day, calendar: calendar) {
                if isDone(on: day, calendar: calendar) {
                    run += 1
                    best = max(best, run)
                } else if day != today {
                    let week = weekID(day, calendar: calendar)
                    if allowsSkip, !skipped.contains(week) { skipped.insert(week) } else { run = 0 }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return best
    }

    /// How many of the `days` days ending with `date` it was done.
    func doneCount(lastDays days: Int, endingOn date: Date, calendar: Calendar = .current) -> Int {
        DayKey.days(endingOn: date, count: days, calendar: calendar).filter { isDone(on: $0, calendar: calendar) }.count
    }

    /// Share of scheduled days done this month, so far (today counts once it's done).
    /// Weekly habits: share of the month's elapsed weeks that reached the target.
    func monthRate(asOf date: Date = .now, calendar: Calendar = .current) -> Double? {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return nil }
        let today = calendar.startOfDay(for: date)
        let from = max(month.start, startDay(calendar: calendar) ?? today)
        var scheduled = 0
        var done = 0
        var day = from
        while day <= today {
            if schedule.isScheduled(day, calendar: calendar) {
                let isDoneDay = isDone(on: day, calendar: calendar)
                if day != today || isDoneDay {
                    scheduled += 1
                    if isDoneDay { done += 1 }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        if case .weekly(let times) = schedule {
            // Expected so far: the target for each elapsed week, prorated.
            let expected = Double(times) * Double(max(scheduled, 1)) / 7
            return expected > 0 ? min(Double(done) / expected, 1) : nil
        }
        return scheduled > 0 ? Double(done) / Double(scheduled) : nil
    }

    /// The weekday missed most over the last 12 weeks, if any stands out.
    func mostMissedWeekday(asOf date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard !schedule.isWeekly else { return nil }
        let start = startDay(calendar: calendar) ?? date
        var misses: [Int: Int] = [:]
        for day in DayKey.days(endingOn: date, count: 84, calendar: calendar).dropLast() where day >= start {
            if schedule.isScheduled(day, calendar: calendar), !isDone(on: day, calendar: calendar) {
                misses[calendar.component(.weekday, from: day), default: 0] += 1
            }
        }
        guard let worst = misses.max(by: { $0.value < $1.value }), worst.value >= 2 else { return nil }
        return worst.key
    }

    /// Fills in the days an automatic habit happened, from what Ebb logged.
    mutating func syncAuto(now: Date = .now, calendar: Calendar = .current) {
        guard let auto else { return }
        let logged = DayLog.days(auto.logKey)
        let start = calendar.startOfDay(for: createdAt ?? now)
        switch auto {
        case .focusSession, .letGo:
            completions = logged.filter { (DayKey.date(from: $0, calendar: calendar) ?? .distantPast) >= start }
        case .underLimit:
            // Each finished day since it was added that didn't reach the limit.
            var days: Set<String> = []
            var day = start
            let today = calendar.startOfDay(for: now)
            while day < today {
                let key = DayKey.key(for: day, calendar: calendar)
                if !logged.contains(key) { days.insert(key) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            completions = days
        }
    }
}

/// Small, actionable starters in the spirit of Atomic Habits: tiny, tied to something
/// you already do, and easy enough to never skip.
nonisolated enum HabitStarters {
    struct Starter: Identifiable {
        let name: String
        let cue: String
        let tiny: String
        var id: String { name }
    }

    static let all: [Starter] = [
        Starter(name: "Read 10 pages", cue: "I get into bed", tiny: "Read one page"),
        Starter(name: "Walk 20 minutes", cue: "I finish lunch", tiny: "Put on my shoes and step outside"),
        Starter(name: "Stretch", cue: "I brush my teeth in the morning", tiny: "One forward fold"),
        Starter(name: "Drink a glass of water", cue: "I pour my morning coffee", tiny: "Fill the glass"),
        Starter(name: "Write in a journal", cue: "I sit down after dinner", tiny: "Write one sentence"),
        Starter(name: "Phone in another room", cue: "I start working", tiny: "Turn it face down"),
    ]
}

nonisolated enum HabitStore {
    private static let key = "habits"
    /// Completions older than this are dropped to keep the shared store small.
    private static let historyDays = 400

    /// Every habit, archived ones included, with automatic ones brought up to date.
    static func loadAll(now: Date = .now) -> [Habit] {
        guard let data = AppGroup.defaults.data(forKey: key),
              var habits = try? JSONDecoder().decode([Habit].self, from: data) else { return [] }
        for i in habits.indices { habits[i].syncAuto(now: now) }
        return habits
    }

    /// The habits in use (not archived).
    static func load(now: Date = .now) -> [Habit] {
        loadAll(now: now).filter { !$0.isArchived }
    }

    static func save(_ habits: [Habit], now: Date = .now) {
        let cutoff = DayKey.key(for: Calendar.current.date(byAdding: .day, value: -historyDays, to: now) ?? now)
        let trimmed = habits.map { habit in
            var habit = habit
            habit.completions = habit.completions.filter { $0 >= cutoff }
            habit.progress = habit.progress.filter { $0.key >= cutoff }
            return habit
        }
        if let data = try? JSONEncoder().encode(trimmed) {
            AppGroup.defaults.set(data, forKey: key)
        }
        HabitReminders.schedule(trimmed, now: now)
    }

    static func toggle(id: UUID, on date: Date = .now) {
        var habits = loadAll(now: date)
        guard let index = habits.firstIndex(where: { $0.id == id }), habits[index].auto == nil else { return }
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
    /// Parked for later: kept in Ebb, left off the widget.
    var isSomeday = false

    var isDone: Bool { completedAt != nil }
}

nonisolated extension TodoItem {
    enum CodingKeys: String, CodingKey { case id, title, completedAt, isSomeday }

    /// To-dos saved by earlier versions had no Someday flag.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        isSomeday = try c.decodeIfPresent(Bool.self, forKey: .isSomeday) ?? false
    }
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
