//
//  WhatsNew.swift
//  Ebb
//
//  A one-time card on the main screen after an update, and the optional weekly recap.
//

import SwiftUI
import UserNotifications

enum WhatsNew {
    /// Bump with each release that has something worth telling people about.
    static let version = "1.6"

    /// The card shows for two weeks after the update, then goes away even if not dismissed.
    static var isFresh: Bool {
        let key = "whatsNewFirstShown-\(version)"
        let defaults = UserDefaults.standard
        guard let first = defaults.object(forKey: key) as? Date else {
            defaults.set(Date.now, forKey: key)
            return true
        }
        return Date.now.timeIntervalSince(first) < 14 * 86_400
    }

    static let items: [(icon: String, text: String)] = [
        ("calendar", "Focus days: one tap for weekdays, weekends, or every day"),
        ("list.bullet", "Shorter, clearer focus rows on the main screen"),
        ("hourglass", "Help getting started counting time saved"),
    ]
}

struct WhatsNewCard: View {
    let onDismiss: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("New in Ebb \(WhatsNew.version)").font(.headline)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                ForEach(WhatsNew.items, id: \.text) { item in
                    Label(item.text, systemImage: item.icon)
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// A Sunday-evening summary of the week. Its numbers are worked out whenever Ebb opens,
/// so they cover the week up to the last time you used it.
enum WeeklyRecap {
    private static let id = "weekly-recap"

    static func schedule(events: [LaunchEvent], now: Date = .now, calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return }

        let resisted = events.filter { $0.outcome == .resisted && week.contains($0.date) }
        let minutes = resisted.map { TimeSaved.minutes(for: $0.name) }.reduce(0, +)
        let saved = minutes < 60 ? "\(minutes) min" : (Double(minutes) / 60).formatted(.number.precision(.fractionLength(1))) + " hours"

        var habitText = ""
        let habits = HabitStore.load(now: now)
        if EbbPlus.isActive, !habits.isEmpty {
            var due = 0, done = 0
            for day in DayKey.days(endingOn: now, count: 7) where week.contains(day) {
                for habit in habits where habit.schedule.isScheduled(day) {
                    due += 1
                    if habit.isDone(on: day) { done += 1 }
                }
            }
            if due > 0 { habitText = " Habits \(Int((Double(done) / Double(due) * 100).rounded()))%." }
        }

        let content = UNMutableNotificationContent()
        content.title = "Your week in Ebb"
        // Worked out now, but delivered Sunday evening. If that's days away, the numbers
        // would be out of date by then; ask the user to open Ebb instead.
        let sunday = calendar.nextDate(after: now, matching: DateComponents(hour: 18, minute: 0, weekday: 1), matchingPolicy: .nextTime) ?? now
        let stale = sunday.timeIntervalSince(now) > 2 * 86_400
        content.body = stale ? "Open Ebb to see how your week went." : resisted.isEmpty
            ? "A fresh week starts tomorrow.\(habitText)"
            : "\(saved) saved and \(resisted.count) app\(resisted.count == 1 ? "" : "s") resisted.\(habitText)"
        // Sunday at 6 PM.
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 18, minute: 0, weekday: 1), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

struct WeeklyRecapToggle: View {
    @Environment(LauncherStore.self) private var store
    @AppStorage(PrefKey.weeklyRecap) private var isOn = false

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRow(icon: "calendar.badge.clock", tint: .teal, title: "Weekly recap",
                        subtitle: "Sunday evening: time saved, apps resisted, habits")
        }
        .onChange(of: isOn) { _, on in
            if on {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    WeeklyRecap.schedule(events: store.events)
                }
            } else {
                WeeklyRecap.cancel()
            }
        }
    }
}
