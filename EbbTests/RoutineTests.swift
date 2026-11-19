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

struct ScreenshotImportTests {
    @Test func skipsWidgetAndSystemText() {
        for text in ["9:41", "100%", "Saturday", "SAT", "October", "No Events Today", "Q Search", "Search App Library", "Siri", "A"] {
            #expect(!ScreenshotImport.looksLikeAppName(text), "\(text)")
        }
        for text in ["Photos", "WhatsApp", "Google Maps", "Uber Eats", "YouTube"] {
            #expect(ScreenshotImport.looksLikeAppName(text), "\(text)")
        }
    }

    @Test func matchesCatalogNamesIncludingShortenedLabels() {
        #expect(AppCatalog.app(named: "photos")?.name == "Photos")
        #expect(AppCatalog.app(named: "Google Cal…")?.name == "Google Calendar")
        #expect(AppCatalog.app(named: "Microso…") == nil || AppCatalog.app(named: "Microso…")?.name.hasPrefix("Microsoft") == true)
        #expect(AppCatalog.app(named: "Xyzzy") == nil)
    }

    @Test func starterSetsOnlyUseAppsThatCanOpen() {
        let essentials = AppCatalog.starterSets.first { $0.name == "Essentials" }!
        #expect(AppCatalog.apps(in: essentials, installed: []).map(\.name) == ["Phone", "Messages", "Camera", "Maps", "Music", "Calendar"])
        let work = AppCatalog.starterSets.first { $0.name == "Work" }!
        // Without Slack or Zoom installed, only Apple's apps are offered.
        #expect(AppCatalog.apps(in: work, installed: []).map(\.name) == ["Mail", "Calendar", "Notes"])
    }
}

struct SetupSharingTests {
    @Test func setupFileRoundTrips() throws {
        let app = EbbSetup.App(id: UUID(), name: "Camera", method: .shortcut("Open Camera"), isMindful: false, isHidden: false, bundleID: "com.apple.camera")
        let setup = EbbSetup(sharedBy: "Test", apps: [app], widgets: [.init(name: "Widget 1", appIDs: [app.id])],
                             style: [AppGroup.Key.backgroundHex: "#112233"])
        let read = try #require(EbbSetup.read(from: setup.fileURL()))
        #expect(read.apps.first?.name == "Camera")
        #expect(read.widgets.first?.appIDs == [app.id])
        #expect(read.shortcutApps == ["Camera"])
        #expect(read.style[AppGroup.Key.backgroundHex] == "#112233")
    }
}

struct FocusTextTests {
    @Test func compactDaysAndTimes() {
        var period = WorkPeriod(name: "Work")
        period.weekdays = [2, 3, 4, 5, 6]
        period.start = 9 * 60
        period.end = 17 * 60
        #expect(period.shortDays == "Mon–Fri")
        #expect(!period.shortTimeRange.contains(":00"))
        period.weekdays = [1, 7]
        #expect(period.shortDays == "Sat–Sun")
    }
}

struct DirectLaunchTests {
    @Test func plainAppsOpenDirectly() {
        let id = UUID()
        let plain = WidgetApp(id: id, name: "Maps", url: URL(string: "maps://"), isMindful: false)
        #expect(plain.directURL == URL(string: "maps://"))

        let mindful = WidgetApp(id: id, name: "Instagram", url: URL(string: "instagram://"), isMindful: true)
        #expect(mindful.directURL == nil)

        let shortcut = WidgetApp(id: id, name: "Camera",
                                 url: URL(string: "shortcuts://run-shortcut?name=Open%20Camera"), isMindful: false)
        #expect(shortcut.directURL == nil)
        #expect(WidgetApp(id: id, name: "Broken", url: nil, isMindful: false).directURL == nil)
    }

    @Test func shortcutTestLinksRoundTrip() {
        #expect(DeepLink(url: DeepLink.shortcutTested(true).url) == .shortcutTested(true))
        #expect(DeepLink(url: DeepLink.shortcutTested(false).url) == .shortcutTested(false))
        let test = ShortcutSetupView.testURL(for: "Open Camera")!.absoluteString
        #expect(test.hasPrefix("shortcuts://x-callback-url/run-shortcut"))
        #expect(test.contains("name=Open%20Camera"))
        #expect(test.contains("x-success=ebb://shortcut-ok"))
    }
}

struct NeverMissTwiceTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ offset: Int, from today: Date) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18))! } // a Wednesday

    private func habit(doneOn offsets: [Int], created: Int = -40) -> Habit {
        var h = Habit(name: "Read 10 pages")
        h.createdAt = day(created, from: today)
        h.completions = Set(offsets.map { DayKey.key(for: day($0, from: today), calendar: calendar) })
        return h
    }

    @Test func flagsAHabitThatSlippedLastTime() {
        #expect(habit(doneOn: [-2, -3]).needsComeback(asOf: today, calendar: calendar))
        #expect(!habit(doneOn: [-1, -2]).needsComeback(asOf: today, calendar: calendar))
        // Done today: nothing to flag.
        #expect(!habit(doneOn: [0, -2]).needsComeback(asOf: today, calendar: calendar))
    }

    @Test func setDaysLookBackToTheLastScheduledDay() {
        var h = habit(doneOn: [])
        h.schedule = .weekdays
        // Monday the 16th done; Tuesday the 17th missed → Wednesday is a comeback day.
        h.completions = [DayKey.key(for: day(-2, from: today), calendar: calendar)]
        #expect(h.needsComeback(asOf: today, calendar: calendar))
    }

    @Test func oneSlipDoesntEndTheForgivingStreak() {
        // Done for 10 days, missed 1 (day -4), done since.
        let h = habit(doneOn: [-1, -2, -3, -5, -6, -7, -8, -9, -10, -11, -12])
        #expect(h.streak(asOf: today, calendar: calendar) == 3)
        #expect(h.neverMissedTwice(asOf: today, calendar: calendar) >= 12)
        // Two misses in a row (days -4 and -5) do end it.
        let broken = habit(doneOn: [-1, -2, -3, -6, -7, -8])
        #expect(broken.neverMissedTwice(asOf: today, calendar: calendar) == 3)
    }

    @Test func skipsKeepTheStreakAndAreLimited() {
        var h = habit(doneOn: [-1, -3, -4])
        #expect(h.streak(asOf: today, calendar: calendar) == 1)
        h.skips = [DayKey.key(for: day(-2, from: today), calendar: calendar)]
        #expect(h.streak(asOf: today, calendar: calendar) == 3)

        h.skips = []
        h.toggleSkip(on: today, calendar: calendar)
        #expect(h.isSkipped(on: today, calendar: calendar))
        #expect(!h.isExpected(on: today, calendar: calendar))
        // A second skip this month is allowed, a third isn't.
        h.toggleSkip(on: day(1, from: today), calendar: calendar)
        #expect(h.skipsLeft(in: today, calendar: calendar) == 0)
        h.toggleSkip(on: day(2, from: today), calendar: calendar)
        #expect(!h.isSkipped(on: day(2, from: today), calendar: calendar))
        // Ticking a skipped day un-skips it.
        h.toggle(on: today, calendar: calendar)
        #expect(!h.isSkipped(on: today, calendar: calendar))
    }
}

struct HabitTuneTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18))! }

    private func habit(_ name: String, doneEveryNth n: Int, days: Int = 40) -> Habit {
        var h = Habit(name: name)
        h.createdAt = calendar.date(byAdding: .day, value: -days, to: today)
        h.tinyVersion = "Read one page"
        h.completions = Set((1...days).filter { $0 % n == 0 }.map {
            DayKey.key(for: calendar.date(byAdding: .day, value: -$0, to: today)!, calendar: calendar)
        })
        return h
    }

    @Test func slippingHabitsGetSmallerOptions() throws {
        let tune = try #require(habit("Read 10 pages", doneEveryNth: 3).tune(asOf: today, calendar: calendar))
        #expect(tune.kind == .smaller)
        var h = habit("Read 10 pages", doneEveryNth: 3)
        h.applyTune(tune.options[0], now: today, calendar: calendar)
        #expect(h.name == "Read one page")
        // Quiet for three weeks after.
        #expect(h.tune(asOf: today, calendar: calendar) == nil)
    }

    @Test func easyHabitsGetAStepUp() throws {
        let tune = try #require(habit("Read 10 pages", doneEveryNth: 1).tune(asOf: today, calendar: calendar))
        #expect(tune.kind == .bigger)
        #expect(tune.options.first?.title == "Try “Read 15 pages”")
        #expect(Habit.stepUp(20) == 30)
        #expect(Habit.stepUp(3) == 4)
    }

    @Test func newOrSteadyHabitsGetNothing() {
        #expect(habit("Read 10 pages", doneEveryNth: 3, days: 7).tune(asOf: today, calendar: calendar) == nil)
        #expect(habit("Read 10 pages", doneEveryNth: 2).tune(asOf: today, calendar: calendar) == nil)
    }
}
