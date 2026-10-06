//
//  RoutineWidgets.swift
//  EbbWidget
//
//  Ebb Plus: a habit tracker and a to-do list you check off right on the Home Screen.
//  Habits and to-dos are added in Ebb; checked to-dos clear at midnight.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intents

struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Off Habit"
    static let isDiscoverable = false

    @Parameter(title: "Habit") var habitID: String

    init() {}
    init(id: UUID) { habitID = id.uuidString }

    func perform() async throws -> some IntentResult {
        if EbbPlus.isActive, let id = UUID(uuidString: habitID) {
            HabitStore.toggle(id: id)
        }
        return .result()
    }
}

struct ToggleTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Off To-Do"
    static let isDiscoverable = false

    @Parameter(title: "To-Do") var itemID: String

    init() {}
    init(id: UUID) { itemID = id.uuidString }

    func perform() async throws -> some IntentResult {
        if EbbPlus.isActive, let id = UUID(uuidString: itemID) {
            TodoStore.toggle(id: id)
        }
        return .result()
    }
}

// MARK: - Timeline

/// Refreshes now and again at midnight, when habits reset and checked to-dos clear.
struct DailyEntry: TimelineEntry {
    let date: Date
    var spot: WidgetSpot? = nil
}

struct DailyProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DailyEntry { DailyEntry(date: .now) }

    func snapshot(for configuration: PositionIntent, in context: Context) async -> DailyEntry {
        DailyEntry(date: .now, spot: configuration.spot)
    }

    func timeline(for configuration: PositionIntent, in context: Context) async -> Timeline<DailyEntry> {
        let now = Date.now
        let midnight = Midnight.next(after: now)
        // A second after midnight, so the new day's date is safely past the boundary.
        let entries = [DailyEntry(date: now, spot: configuration.spot),
                       DailyEntry(date: midnight.addingTimeInterval(1), spot: configuration.spot)]
        return Timeline(entries: entries, policy: .after(Midnight.next(after: midnight)))
    }
}

/// A round checkbox that matches Ebb's quiet style.
private struct Check: View {
    let isOn: Bool
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size, weight: .light))
            .opacity(isOn ? 1 : 0.55)
            .contentTransition(.symbolEffect(.replace))
    }
}

private struct EmptyRoutine: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Habits

struct HabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyEntry

    private var limit: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 4
        default: 8
        }
    }

    private var showsWeek: Bool { family != .systemSmall }

    var body: some View {
        Group {
            if !EbbPlus.isActive {
                PlusLocked(name: "Habits")
            } else {
                content(HabitStore.load())
            }
        }
        .padding(16)
        .ebbWidgetStyle(spot: entry.spot, identity: "habits")
        .widgetURL(DeepLink.home.url)
    }

    @ViewBuilder
    private func content(_ habits: [Habit]) -> some View {
        if habits.isEmpty {
            EmptyRoutine(icon: "checklist", text: "Add habits in Ebb › Habits")
        } else {
            let shown = Array(habits.prefix(limit))
            let doneToday = habits.filter { $0.isDone(on: entry.date) }.count
            VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Habits").font(.caption).opacity(0.6)
                    Spacer()
                    Text("\(doneToday)/\(habits.count) today")
                        .font(.caption)
                        .monospacedDigit()
                        .opacity(0.6)
                }
                ForEach(shown) { habit in
                    row(habit)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ habit: Habit) -> some View {
        let done = habit.isDone(on: entry.date)
        return Button(intent: ToggleHabitIntent(id: habit.id)) {
            HStack(spacing: 10) {
                Check(isOn: done, size: family == .systemLarge ? 22 : 18)
                Text(habit.name)
                    .font(family == .systemLarge ? .body : .subheadline)
                    .lineLimit(1)
                    .opacity(done ? 0.6 : 1)
                Spacer(minLength: 4)
                if showsWeek {
                    week(habit)
                }
                let streak = habit.streak(asOf: entry.date)
                if streak > 1 && family != .systemSmall {
                    Text("\(streak)d")
                        .font(.caption)
                        .monospacedDigit()
                        .opacity(0.6)
                        .frame(minWidth: 26, alignment: .trailing)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The last six days as dots, so you can see the pattern at a glance.
    private func week(_ habit: Habit) -> some View {
        let days = DayKey.days(endingOn: entry.date, count: 7).dropLast()
        return HStack(spacing: 4) {
            ForEach(Array(days), id: \.self) { day in
                Circle()
                    .fill(.primary.opacity(habit.isDone(on: day) ? 0.85 : 0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbHabits", intent: PositionIntent.self, provider: DailyProvider()) { entry in
            HabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Habits")
        .description("Tap a habit to mark it done today. Add habits in Ebb. Ebb Plus.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - To-dos

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyEntry

    private var limit: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 4
        default: 10
        }
    }

    var body: some View {
        Group {
            if !EbbPlus.isActive {
                PlusLocked(name: "To-Do")
            } else {
                content(TodoStore.load(asOf: entry.date))
            }
        }
        .padding(16)
        .ebbWidgetStyle(spot: entry.spot, identity: "todo")
        .widgetURL(DeepLink.home.url)
    }

    @ViewBuilder
    private func content(_ items: [TodoItem]) -> some View {
        let left = items.filter { !$0.isDone }.count
        let shown = TodoStore.shown(items, limit: limit)
        VStack(alignment: .leading, spacing: family == .systemLarge ? 11 : 7) {
            HStack(alignment: .center) {
                Text("To-do").font(.caption).opacity(0.6)
                Spacer()
                // Widgets can't take typing, so + opens Ebb ready to add one.
                Link(destination: DeepLink.addTodo.url) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.primary.opacity(0.1)))
                }
                .accessibilityLabel("Add a to-do")
            }
            if items.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing to do")
                    .font(family == .systemLarge ? .title3 : .subheadline)
                    .opacity(0.6)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(shown) { item in
                    Button(intent: ToggleTodoIntent(id: item.id)) {
                        HStack(spacing: 10) {
                            Check(isOn: item.isDone, size: family == .systemLarge ? 20 : 17)
                            Text(item.title)
                                .font(family == .systemLarge ? .body : .subheadline)
                                .strikethrough(item.isDone)
                                .opacity(item.isDone ? 0.45 : 1)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // Only unfinished items count as "more"; hidden finished ones don't need a mention.
                let hiddenOpen = left - shown.filter { !$0.isDone }.count
                if hiddenOpen > 0 {
                    Text("+\(hiddenOpen) more")
                        .font(.caption)
                        .opacity(0.5)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbTodo", intent: PositionIntent.self, provider: DailyProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("To-Do")
        .description("Check things off right on your Home Screen. Checked items clear at midnight. Ebb Plus.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
