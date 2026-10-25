//
//  HabitReminders.swift
//  Shared between Ebb and its widgets.
//
//  A nudge at a habit's reminder time, only on days it's scheduled and not done yet.
//  iOS can't skip one day of a repeating notification, so each of the next few days gets
//  its own; ticking a habit off (in Ebb or on the widget) reschedules and drops today's.
//

import Foundation
import UserNotifications

nonisolated enum HabitReminders {
    private static let prefix = "habit-reminder-"
    /// Days ahead to schedule; Ebb tops them up whenever habits change or it opens.
    private static let daysAhead = 7
    /// iOS keeps 64 pending notifications per app; leave room for focus reminders.
    private static let maxPending = 48

    static func schedule(_ habits: [Habit], now: Date = .now, calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        var requests: [UNNotificationRequest] = []
        let withReminders = habits.filter { !$0.isArchived && $0.reminderMinutes != nil }
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            for habit in withReminders {
                guard let minutes = habit.reminderMinutes,
                      habit.schedule.isScheduled(day, calendar: calendar),
                      !habit.isDone(on: day, calendar: calendar),
                      let fire = calendar.date(byAdding: .minute, value: minutes, to: day), fire > now
                else { continue }
                // Weekly habits stop nudging once the week's target is met.
                if case .weekly(let times) = habit.schedule, habit.doneThisWeek(day, calendar: calendar) >= times { continue }

                let content = UNMutableNotificationContent()
                content.title = habit.name
                content.body = habit.isCounted
                    ? "\(habit.count(on: day, calendar: calendar)) of \(habit.target) so far today."
                    : "Still to do today."
                content.sound = .default
                content.threadIdentifier = "habits"
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                requests.append(UNNotificationRequest(identifier: "\(prefix)\(habit.id.uuidString)-\(DayKey.key(for: day, calendar: calendar))",
                                                      content: content, trigger: trigger))
            }
        }
        requests = Array(requests.prefix(maxPending))

        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for request in requests { center.add(request) }
        }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
