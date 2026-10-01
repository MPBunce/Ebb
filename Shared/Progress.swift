//
//  Progress.swift
//  Shared between Ebb and its widgets.
//
//  Year and life progress, and an estimate of time Ebb has given back.
//

import Foundation

nonisolated enum TimeProgress {
    /// Fraction of the calendar period containing `date` that has passed (0...1).
    static func fraction(of component: Calendar.Component, at date: Date = .now, calendar: Calendar = .current) -> Double {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return 0 }
        return min(max(date.timeIntervalSince(interval.start) / interval.duration, 0), 1)
    }
}

/// Sex used to pick an average life expectancy.
nonisolated enum Sex: String, CaseIterable, Identifiable {
    case female, male, unspecified

    var id: Self { self }

    var label: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .unspecified: "Prefer not to say"
        }
    }

    /// US life expectancy at birth, CDC NCHS Data Brief 521 (2023 data).
    var lifeExpectancy: Double {
        switch self {
        case .female: 81.1
        case .male: 75.8
        case .unspecified: 78.4
        }
    }
}

/// Life progress from the user's age and the average life expectancy for their sex.
nonisolated struct LifeProgress {
    var birthDate: Date
    var expectancyYears: Double

    private static let secondsPerYear = 365.2425 * 24 * 60 * 60

    /// Nil until the user has entered their age in Ebb.
    static func load() -> LifeProgress? {
        let defaults = AppGroup.defaults
        guard let birth = defaults.object(forKey: AppGroup.Key.birthDate) as? Date else { return nil }
        let sex = defaults.string(forKey: AppGroup.Key.sex).flatMap(Sex.init(rawValue:)) ?? .unspecified
        return LifeProgress(birthDate: birth, expectancyYears: sex.lifeExpectancy)
    }

    /// Ebb only asks for age, so assume the user is halfway between birthdays.
    static func estimatedBirthDate(age: Int, now: Date = .now) -> Date {
        now.addingTimeInterval(-(Double(age) + 0.5) * secondsPerYear)
    }

    /// The age implied by a stored birth date.
    static func age(birthDate: Date, now: Date = .now) -> Int {
        Int(now.timeIntervalSince(birthDate) / secondsPerYear)
    }

    func endDate(calendar: Calendar = .current) -> Date {
        birthDate.addingTimeInterval(expectancyYears * Self.secondsPerYear)
    }

    func fraction(at date: Date = .now, calendar: Calendar = .current) -> Double {
        let total = endDate(calendar: calendar).timeIntervalSince(birthDate)
        guard total > 0 else { return 0 }
        return min(max(date.timeIntervalSince(birthDate) / total, 0), 1)
    }

    func weeksRemaining(at date: Date = .now, calendar: Calendar = .current) -> Int {
        max(calendar.dateComponents([.weekOfYear], from: date, to: endDate(calendar: calendar)).weekOfYear ?? 0, 0)
    }
}

/// An honest estimate of time saved: each app you let go during a mindful pause counts
/// a few minutes (user-adjustable), plus the time spent in focus sessions.
/// iOS doesn't let apps read real Screen Time totals, so this is clearly an estimate.
nonisolated struct TimeSaved {
    var since: Date
    var resistedCount: Int
    var focusMinutes: Int
    var minutesPerResist: Int

    static let defaultMinutesPerResist = 10

    var totalMinutes: Int { resistedCount * minutesPerResist + focusMinutes }
    var hours: Double { Double(totalMinutes) / 60 }

    static func load() -> TimeSaved {
        let defaults = AppGroup.defaults
        return TimeSaved(
            since: defaults.object(forKey: AppGroup.Key.installDate) as? Date ?? .now,
            resistedCount: defaults.integer(forKey: AppGroup.Key.lifetimeResisted),
            focusMinutes: defaults.integer(forKey: AppGroup.Key.lifetimeFocusMinutes),
            minutesPerResist: defaults.object(forKey: AppGroup.Key.minutesPerResist) as? Int ?? defaultMinutesPerResist
        )
    }

    /// Records the first launch so "since" has a start date.
    static func markInstallIfNeeded() {
        let defaults = AppGroup.defaults
        if defaults.object(forKey: AppGroup.Key.installDate) == nil {
            defaults.set(Date.now, forKey: AppGroup.Key.installDate)
        }
    }

    static func recordResist() {
        let defaults = AppGroup.defaults
        defaults.set(defaults.integer(forKey: AppGroup.Key.lifetimeResisted) + 1, forKey: AppGroup.Key.lifetimeResisted)
    }

    /// Adds (or with a negative value, refunds) focus minutes.
    static func recordFocus(minutes: Int) {
        let defaults = AppGroup.defaults
        let current = defaults.integer(forKey: AppGroup.Key.lifetimeFocusMinutes)
        defaults.set(max(current + minutes, 0), forKey: AppGroup.Key.lifetimeFocusMinutes)
    }

    var formattedHours: String {
        hours < 10 ? hours.formatted(.number.precision(.fractionLength(1))) : "\(Int(hours))"
    }
}
