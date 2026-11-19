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
            WidgetCenter.shared.reloadTimelines(ofKind: "EbbHabitsRing")
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

    private var isLarge: Bool { family == .systemLarge }

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
        let day = entry.date
        let due = habits.filter { $0.isExpected(on: day) }
        // Still to do, in the order the day runs (by reminder time), then done, then days off.
        let pending = due.filter { !$0.isDone(on: day) }
            .enumerated()
            .sorted { ($0.element.reminderMinutes ?? Int.max, $0.offset) < ($1.element.reminderMinutes ?? Int.max, $1.offset) }
            .map(\.element)
        let done = due.filter { $0.isDone(on: day) }
        let resting = habits.filter { !$0.isExpected(on: day) }

        if habits.isEmpty {
            EmptyRoutine(icon: "checklist", text: "Add habits in Ebb › Habits")
        } else if !due.isEmpty && pending.isEmpty {
            allDone(count: due.count)
        } else if family == .systemSmall, let next = pending.first {
            nextUp(next, remaining: pending.count, total: due.count)
        } else {
            let limit = isLarge ? 7 : 3
            VStack(alignment: .leading, spacing: isLarge ? 12 : 7) {
                header(done: done.count, total: due.count)
                ForEach(Array((pending + done + resting).prefix(limit))) { habit in
                    row(habit, isPending: !habit.isDone(on: day) && habit.isExpected(on: day))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func header(done: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Habits").font(.caption).opacity(0.6)
            Spacer()
            Text("\(done)/\(total) today")
                .font(.caption)
                .monospacedDigit()
                .opacity(0.6)
        }
    }

    /// A finished day: a quiet reward instead of a list of ticks.
    private func allDone(count: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: family == .systemSmall ? 34 : 40, weight: .ultraLight))
            Text("All done today")
                .font(family == .systemSmall ? .subheadline : .headline)
            Text(count == 1 ? "1 habit" : "\(count) habits")
                .font(.caption)
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Small widget: just the next habit, big, with one tick. Ticking it brings up the next.
    private func nextUp(_ habit: Habit, remaining: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Next").font(.caption).opacity(0.6)
                Spacer()
                Text("\(total - remaining)/\(total)").font(.caption).monospacedDigit().opacity(0.6)
            }
            Spacer(minLength: 0)
            Text(habit.name)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let line = nudge(for: habit) {
                Text(line.text)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(line.isComeback ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary.opacity(0.6)))
            }
            Spacer(minLength: 0)
            Button(intent: ToggleHabitIntent(id: habit.id)) {
                HStack(spacing: 6) {
                    if habit.auto != nil {
                        Image(systemName: "sparkles")
                    } else {
                        Check(isOn: false, size: 26)
                    }
                    if habit.isCounted {
                        Text("\(habit.count(on: entry.date))/\(habit.target)").font(.caption).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(habit.auto != nil)
        }
    }

    /// The line under a habit still to do: the never-miss-twice nudge, or its cue.
    private func nudge(for habit: Habit) -> (text: String, isComeback: Bool)? {
        if habit.needsComeback(asOf: entry.date) {
            // The medium widget is too narrow for the small version as well.
            guard family != .systemMedium, let tiny = habit.tinyVersion else { return ("Don't miss twice", true) }
            return ("Don't miss twice · at least \(tiny.lowercased())", true)
        }
        if let cue = habit.cueText { return (cue, false) }
        if let tiny = habit.tinyVersion { return ("At least: \(tiny.lowercased())", false) }
        return nil
    }

    private func row(_ habit: Habit, isPending: Bool) -> some View {
        let done = habit.isDone(on: entry.date)
        let resting = !habit.isExpected(on: entry.date)
        return Button(intent: ToggleHabitIntent(id: habit.id)) {
            HStack(alignment: .center, spacing: 10) {
                if habit.auto != nil && !done {
                    Image(systemName: "sparkles")
                        .font(.system(size: isLarge ? 18 : 15, weight: .light))
                        .opacity(0.55)
                } else {
                    Check(isOn: done, size: isLarge ? 22 : 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name)
                        .font(isLarge ? .body : .subheadline)
                        .lineLimit(1)
                        .opacity(done || resting ? 0.5 : 1)
                    if isPending, let line = nudge(for: habit) {
                        Text(line.text)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(line.isComeback ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary.opacity(0.55)))
                    }
                }
                Spacer(minLength: 4)
                if habit.isCounted && !done {
                    Text("\(habit.count(on: entry.date))/\(habit.target)")
                        .font(.caption)
                        .monospacedDigit()
                        .opacity(0.6)
                }
                week(habit)
                let streak = habit.streak(asOf: entry.date)
                if streak > 1 {
                    Text(habit.streakText(asOf: entry.date, short: true))
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

    /// The last seven days, today last, so ticking today visibly extends the chain.
    private func week(_ habit: Habit) -> some View {
        HStack(spacing: 4) {
            ForEach(DayKey.days(endingOn: entry.date, count: 7), id: \.self) { day in
                let isToday = Calendar.current.isDate(day, inSameDayAs: entry.date)
                if habit.isDone(on: day) {
                    Circle().fill(.primary.opacity(0.85)).frame(width: 6, height: 6)
                } else if isToday && habit.isExpected(on: day) {
                    Circle().strokeBorder(.primary.opacity(0.5), lineWidth: 1).frame(width: 6, height: 6)
                } else {
                    Circle().fill(.primary.opacity(habit.isExpected(on: day) ? 0.15 : 0.05)).frame(width: 6, height: 6)
                }
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
        .description("Tap a habit to tick it off or count one more. Add habits in Ebb. Ebb Plus.")
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
                // Someday items stay in Ebb.
                content(TodoStore.load(asOf: entry.date).filter { !$0.isSomeday })
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
                Text("To-Do").font(.caption).opacity(0.6)
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

// MARK: - Lock Screen habits

struct HabitRingEntry: TimelineEntry {
    let date: Date
}

/// Refreshes at midnight; ticking a habit reloads it straight away.
struct HabitRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitRingEntry { HabitRingEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (HabitRingEntry) -> Void) {
        completion(HabitRingEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitRingEntry>) -> Void) {
        let midnight = Midnight.next(after: .now)
        completion(Timeline(entries: [HabitRingEntry(date: .now), HabitRingEntry(date: midnight.addingTimeInterval(1))],
                            policy: .after(midnight)))
    }
}

struct HabitRingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitRingEntry

    var body: some View {
        let due = HabitStore.load().filter { $0.isExpected(on: entry.date) }
        let done = due.filter { $0.isDone(on: entry.date) }.count
        let fraction = due.isEmpty ? 0 : Double(done) / Double(due.count)
        Group {
            if !EbbPlus.isActive {
                Image(systemName: "lock")
            } else if family == .accessoryRectangular {
                HStack(spacing: 10) {
                    Gauge(value: fraction) { EmptyView() }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Habits").font(.headline)
                        Text(due.isEmpty ? "Day off" : "\(done) of \(due.count) today")
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Gauge(value: fraction) {
                    Image(systemName: "checklist")
                } currentValueLabel: {
                    Text(due.isEmpty ? "–" : "\(done)/\(due.count)")
                }
                .gaugeStyle(.accessoryCircular)
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(DeepLink.home.url)
    }
}

struct HabitRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EbbHabitsRing", provider: HabitRingProvider()) { entry in
            HabitRingView(entry: entry)
        }
        .configurationDisplayName("Habits Today")
        .description("How many of today's habits are done. Ebb Plus.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
