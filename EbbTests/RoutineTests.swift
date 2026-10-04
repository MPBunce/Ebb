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
