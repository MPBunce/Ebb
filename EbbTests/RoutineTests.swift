//
//  RoutineTests.swift
//  EbbTests
//

import Foundation
import Testing
@testable import Ebb

struct RoutineTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    @Test func streakCountsBackFromToday() {
        var habit = Habit(name: "Read")
        for d in [3, 4, 5] { habit.toggle(on: day(d), calendar: calendar) }
        #expect(habit.streak(asOf: day(5), calendar: calendar) == 3)
    }

    @Test func streakSurvivesUntilTodayIsDone() {
        var habit = Habit(name: "Walk")
        for d in [3, 4] { habit.toggle(on: day(d), calendar: calendar) }
        // Not done yet today (the 5th): yesterday's streak still counts.
        #expect(habit.streak(asOf: day(5), calendar: calendar) == 2)
        // A missed day breaks it.
        #expect(habit.streak(asOf: day(6), calendar: calendar) == 0)
    }

    @Test func toggleTwiceUndoes() {
        var habit = Habit(name: "Stretch")
        habit.toggle(on: day(5), calendar: calendar)
        habit.toggle(on: day(5, hour: 20), calendar: calendar)
        #expect(!habit.isDone(on: day(5), calendar: calendar))
    }

    @Test func finishedTodosClearAtMidnight() {
        let open = TodoItem(title: "Email")
        let doneToday = TodoItem(title: "Groceries", completedAt: day(5, hour: 9))
        let doneYesterday = TodoItem(title: "Laundry", completedAt: day(4, hour: 22))
        let kept = TodoStore.clearingFinished([open, doneToday, doneYesterday], now: day(5, hour: 23), calendar: calendar)
        #expect(kept.map(\.title) == ["Email", "Groceries"])

        let nextMorning = TodoStore.clearingFinished(kept, now: day(6, hour: 7), calendar: calendar)
        #expect(nextMorning.map(\.title) == ["Email"])
    }

    @Test func openTodosComeFirst() {
        let items = [TodoItem(title: "A", completedAt: day(5)), TodoItem(title: "B"), TodoItem(title: "C")]
        #expect(TodoStore.ordered(items).map(\.title) == ["B", "C", "A"])
    }

    @Test func widgetKeepsCheckedItemsInPlaceWhenTheyFit() {
        let items = [TodoItem(title: "A", completedAt: day(5)), TodoItem(title: "B"), TodoItem(title: "C")]
        #expect(TodoStore.shown(items, limit: 4).map(\.title) == ["A", "B", "C"])
        // Short on room: unfinished items come first.
        #expect(TodoStore.shown(items, limit: 2).map(\.title) == ["B", "C"])
    }
    // MARK: Schedules, counts, skips

    @Test func daysOffDontBreakAStreak() {
        // Oct 2026: the 5th is a Monday. Weekdays only, done Mon–Fri, then the weekend off.
        var habit = Habit(name: "Run", schedule: .weekdays)
        for d in 5...9 { habit.toggle(on: day(d), calendar: calendar) }
        #expect(habit.streak(asOf: day(11), calendar: calendar) == 5)
        // Monday the 12th, not done yet: still 5.
        #expect(habit.streak(asOf: day(12), calendar: calendar) == 5)
    }

    @Test func neverMissTwiceForgivesOneMissAWeek() {
        var habit = Habit(name: "Read", allowsSkip: true)
        for d in [5, 6, 8, 9] { habit.toggle(on: day(d), calendar: calendar) }
        // Missed the 7th only: forgiven.
        #expect(habit.streak(asOf: day(9), calendar: calendar) == 4)
        var strict = habit
        strict.allowsSkip = false
        #expect(strict.streak(asOf: day(9), calendar: calendar) == 2)
        // Two misses in the same week break it.
        var twice = Habit(name: "Read", allowsSkip: true)
        for d in [5, 8, 9] { twice.toggle(on: day(d), calendar: calendar) }
        #expect(twice.streak(asOf: day(9), calendar: calendar) == 2)
    }

    @Test func countedHabitsFillUpThenReset() {
        var habit = Habit(name: "Water", target: 3)
        habit.toggle(on: day(5), calendar: calendar)
        habit.toggle(on: day(5), calendar: calendar)
        #expect(habit.count(on: day(5), calendar: calendar) == 2)
        #expect(!habit.isDone(on: day(5), calendar: calendar))
        habit.toggle(on: day(5), calendar: calendar)
        #expect(habit.isDone(on: day(5), calendar: calendar))
        habit.decrement(on: day(5), calendar: calendar)
        #expect(habit.count(on: day(5), calendar: calendar) == 2)
        #expect(!habit.isDone(on: day(5), calendar: calendar))
    }

    @Test func weeklyHabitsStreakInWeeks() {
        var habit = Habit(name: "Gym", schedule: .weekly(2))
        // Week of the 5th: twice. Week of the 12th: twice. Week of the 19th: once so far.
        for d in [5, 8, 13, 15, 20] { habit.toggle(on: day(d), calendar: calendar) }
        #expect(habit.streak(asOf: day(21), calendar: calendar) == 2)
        habit.toggle(on: day(22), calendar: calendar)
        #expect(habit.streak(asOf: day(22), calendar: calendar) == 3)
    }

    @Test func oldSavedHabitsStillLoad() throws {
        let json = #"[{"id":"7E7B2D7C-3B0B-4C59-9E43-6E1B9A0C2B11","name":"Read","completions":["2026-10-05"]}]"#
        let habits = try JSONDecoder().decode([Habit].self, from: Data(json.utf8))
        #expect(habits.first?.name == "Read")
        #expect(habits.first?.schedule == .daily)
        #expect(habits.first?.target == 1)
        #expect(habits.first?.isArchived == false)

        let todos = try JSONDecoder().decode([TodoItem].self, from: Data(#"[{"id":"7E7B2D7C-3B0B-4C59-9E43-6E1B9A0C2B12","title":"Email"}]"#.utf8))
        #expect(todos.first?.isSomeday == false)
    }

    @Test func cueReadsAsASentence() {
        #expect(Habit(name: "Read", cue: "I get into bed").cueText == "After I get into bed")
        #expect(Habit(name: "Read", cue: "When I wake up").cueText == "When I wake up")
        #expect(Habit(name: "Read", cue: "  ").cueText == nil)
    }
}

@Suite(.serialized)
struct TodoStoreToggleTests {
    @Test func uncheckingKeepsTheItem() {
        let saved = TodoStore.load()
        defer { TodoStore.save(saved) }
        let item = TodoItem(title: "Probe")
        TodoStore.save([item])
        TodoStore.toggle(id: item.id)
        #expect(TodoStore.load().first?.isDone == true)
        TodoStore.toggle(id: item.id)
        let after = TodoStore.load()
        #expect(after.map(\.title) == ["Probe"])
        #expect(after.first?.isDone == false)
    }

    @Test func drawingTomorrowsWidgetDoesNotDeleteTodaysCheckedItems() {
        let saved = TodoStore.load()
        defer { TodoStore.save(saved) }
        let item = TodoItem(title: "Probe")
        TodoStore.save([item])
        TodoStore.toggle(id: item.id)
        // WidgetKit draws the after-midnight entry ahead of time.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        #expect(TodoStore.load(asOf: tomorrow).isEmpty)
        // Today's list still has it, crossed off.
        #expect(TodoStore.load().first?.isDone == true)
    }

}
