//
//  EbbTests.swift
//  EbbTests
//
//  Created by Matthew Bunce on 2026-10-01.
//

import CoreGraphics
import Foundation
import Testing
@testable import Ebb

@MainActor
struct DeepLinkTests {
    @Test func roundTripsLaunchLinks() {
        let id = UUID()
        #expect(DeepLink(url: DeepLink.launch(id).url) == .launch(id))
        #expect(DeepLink(url: DeepLink.home.url) == .home)
        #expect(DeepLink(url: DeepLink.focus.url) == .focus)
    }

    @Test func rejectsForeignOrMalformedLinks() {
        #expect(DeepLink(url: URL(string: "https://home")!) == nil)
        #expect(DeepLink(url: URL(string: "ebb://launch/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "ebb://elsewhere")!) == nil)
    }
}

@MainActor
struct LaunchTargetTests {
    @Test func normalizesSchemes() {
        #expect(LaunchTarget(name: "Spotify", method: .urlScheme("spotify")).url?.absoluteString == "spotify://")
        #expect(LaunchTarget(name: "Spotify", method: .urlScheme("spotify://")).url?.absoluteString == "spotify://")
        #expect(LaunchTarget(name: "HN", method: .website("news.ycombinator.com")).url?.absoluteString == "https://news.ycombinator.com")
    }

    @Test func encodesShortcutNames() {
        let url = LaunchTarget(name: "Camera", method: .shortcut("Open Camera")).url
        #expect(url?.absoluteString == "shortcuts://run-shortcut?name=Open%20Camera")
    }
}

@MainActor
struct InsightsTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func event(_ name: String, daysAgo: Int, _ outcome: LaunchEvent.Outcome) -> LaunchEvent {
        LaunchEvent(targetID: UUID(), name: name,
                    date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
                    outcome: outcome)
    }

    @Test func countsTodayAndTopApps() {
        let insights = Insights(events: [
            event("Instagram", daysAgo: 0, .opened),
            event("Instagram", daysAgo: 0, .resisted),
            event("Instagram", daysAgo: 1, .opened),
            event("Maps", daysAgo: 2, .opened),
            event("Old", daysAgo: 20, .opened),
        ], now: now, calendar: calendar)

        #expect(insights.today.opened == 1)
        #expect(insights.today.resisted == 1)
        #expect(insights.week.count == 7)
        #expect(insights.topApps.map(\.name) == ["Instagram", "Maps"])
    }

    @Test func streakCountsConsecutiveResistDays() {
        let insights = Insights(events: [
            event("X", daysAgo: 0, .resisted),
            event("X", daysAgo: 1, .resisted),
            event("X", daysAgo: 3, .resisted),
        ], now: now, calendar: calendar)
        #expect(insights.resistStreak == 2)
    }
}

@MainActor
struct LauncherStoreTests {
    private func makeStore() -> LauncherStore {
        LauncherStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    @Test func appWidgetsHoldSixAppsInOrder() {
        let store = makeStore()
        let list = store.lists[0]
        let ids = (1...7).map { number -> UUID in
            let target = LaunchTarget(name: "App \(number)", method: .urlScheme("app\(number)"))
            store.add(target)
            store.toggle(target.id, in: list.id)
            return target.id
        }
        #expect(store.lists[0].appIDs == Array(ids.prefix(6)))

        store.moveApps(in: list.id, from: [5], to: 0)
        #expect(store.lists[0].appIDs.first == ids[5])
    }

    @Test func newAppsFillTheNextWidgetWithRoom() {
        let store = makeStore()
        for number in 1...7 {
            let target = LaunchTarget(name: "App \(number)", method: .urlScheme("app\(number)"))
            store.add(target)
            store.addToFirstOpenList(target.id)
        }
        // The first widget fills up, but there's no second one yet.
        #expect(store.lists[0].appIDs.count == 6)
        #expect(store.widgetAppIDs.count == 6)

        store.addList()
        let last = store.targets.last!
        #expect(store.addToFirstOpenList(last.id))
        #expect(store.lists[1].appIDs == [last.id])
    }

    @Test func freePlanLimitsAppWidgets() {
        let store = makeStore()
        while store.canAddList { store.addList() }
        #expect(store.lists.count == store.maxLists)
        #expect(store.addList() == nil)
    }

    @Test func removingAnAppTakesItOffWidgets() {
        let store = makeStore()
        let target = LaunchTarget(name: "Maps", method: .urlScheme("maps://"))
        store.add(target)
        store.addToFirstOpenList(target.id)
        store.remove(target)
        #expect(store.widgetAppIDs.isEmpty)
    }

    @Test func mindfulAppsWaitForPause() {
        let store = makeStore()
        let target = LaunchTarget(name: "Instagram", method: .urlScheme("instagram://"), isMindful: true)
        store.add(target)

        store.requestLaunch(target)
        #expect(store.pendingPause == target)

        store.resist(target, intention: "  just bored ")
        #expect(store.pendingPause == nil)
        #expect(store.events.last?.outcome == .resisted)
        #expect(store.events.last?.intention == "just bored")
    }

    @Test func persistsAcrossInstances() {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let first = LauncherStore(directory: directory)
        let maps = LaunchTarget(name: "Maps", method: .urlScheme("maps://"))
        first.add(maps)
        first.addToFirstOpenList(maps.id)

        let second = LauncherStore(directory: directory)
        #expect(second.primaryApps.map(\.name) == ["Maps"])
    }
}

@MainActor
struct NightlyWindowTests {
    private func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
    }

    @Test func handlesWindowsThatWrapMidnight() {
        let start = 22 * 60, end = 7 * 60
        #expect(FocusManager.isWithinNightly(start: start, end: end, now: date(hour: 23, minute: 0)))
        #expect(FocusManager.isWithinNightly(start: start, end: end, now: date(hour: 3, minute: 0)))
        #expect(!FocusManager.isWithinNightly(start: start, end: end, now: date(hour: 12, minute: 0)))
    }

    @Test func handlesSameDayWindows() {
        #expect(FocusManager.isWithinNightly(start: 9 * 60, end: 17 * 60, now: date(hour: 10, minute: 0)))
        #expect(!FocusManager.isWithinNightly(start: 9 * 60, end: 17 * 60, now: date(hour: 18, minute: 0)))
    }
}

@MainActor
struct WidgetMathTests {
    @Test func lifeProgressUsesAgeAndSexAverage() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let birth = LifeProgress.estimatedBirthDate(age: 40, now: now)
        #expect(LifeProgress.age(birthDate: birth, now: now) == 40)

        let male = LifeProgress(birthDate: birth, expectancyYears: Sex.male.lifeExpectancy)
        let female = LifeProgress(birthDate: birth, expectancyYears: Sex.female.lifeExpectancy)
        #expect(abs(male.fraction(at: now) - 40.5 / 75.8) < 0.0001)
        #expect(female.fraction(at: now) < male.fraction(at: now))
        #expect(male.fraction(at: birth.addingTimeInterval(-1)) == 0)
    }

    @Test func lifeBreakdownRoundsEachUnit() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let birth = now.addingTimeInterval(-10 * 365.2425 * 86400)
        let life = LifeProgress(birthDate: birth, expectancyYears: 80)
        let lived = life.breakdown(remaining: false, at: now)
        #expect(lived.years == 10)
        #expect(lived.weeks == 522)
        #expect(lived.days == 3652)
        let left = life.breakdown(remaining: true, at: now)
        #expect(left.years == 70)

        // Ebb stores age as halfway to the next birthday; lived years still read as the age.
        let fromAge = LifeProgress(birthDate: LifeProgress.estimatedBirthDate(age: 32, now: now), expectancyYears: 80)
        #expect(fromAge.breakdown(remaining: false, at: now).years == 32)
    }

    @Test func pastExpectancyCountsExtraTime() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        // 90.5 years old against 75.8 expected: about 15 years of extra time.
        let life = LifeProgress(birthDate: LifeProgress.estimatedBirthDate(age: 90, now: now), expectancyYears: 75.8)
        let span = life.breakdown(remaining: true, at: now)
        #expect(span.isExtraTime)
        #expect(span.years == 15)
        #expect(!life.breakdown(remaining: false, at: now).isExtraTime)
    }

    @Test func timeSavedCombinesLetGoAndFocus() {
        let saved = TimeSaved(since: .now, resistedCount: 6, focusMinutes: 90, minutesPerResist: 10)
        #expect(saved.totalMinutes == 150)
        #expect(saved.formattedHours == "2.5")
    }

    @Test func yearProgressBounds() {
        let calendar = Calendar(identifier: .gregorian)
        let newYear = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        #expect(TimeProgress.fraction(of: .year, at: newYear, calendar: calendar) == 0)
        let midYear = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12))!
        #expect(abs(TimeProgress.fraction(of: .year, at: midYear, calendar: calendar) - 0.5) < 0.01)
    }
}

@MainActor
struct WorkPeriodTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        // 2026-09-27 is a Sunday (weekday 1).
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        let day = calendar.date(byAdding: .day, value: weekday - 1, to: sunday)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @Test func weekdayHoursOnly() {
        let period = WorkPeriod(start: 9 * 60, end: 17 * 60, weekdays: [2, 3, 4, 5, 6])
        #expect(period.contains(date(weekday: 2, hour: 10), calendar: calendar))
        #expect(!period.contains(date(weekday: 2, hour: 18), calendar: calendar))
        #expect(!period.contains(date(weekday: 1, hour: 10), calendar: calendar))
    }

    @Test func overnightBelongsToStartDay() {
        // Friday 22:00 – 02:00.
        let period = WorkPeriod(start: 22 * 60, end: 2 * 60, weekdays: [6])
        #expect(period.contains(date(weekday: 6, hour: 23), calendar: calendar))
        #expect(period.contains(date(weekday: 7, hour: 1), calendar: calendar))
        #expect(!period.contains(date(weekday: 6, hour: 1), calendar: calendar))
    }

    @Test func disabledNeverApplies() {
        let period = WorkPeriod(start: 0, end: 23 * 60, weekdays: Set(1...7), isEnabled: false)
        #expect(!period.contains(date(weekday: 3, hour: 12), calendar: calendar))
    }
}

@MainActor
struct TimeInWordsTests {
    private func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
    }

    @Test func readsLikeSpeech() {
        #expect(TimeInWords.phrase(for: time(9, 0)) == "nine o’clock")
        #expect(TimeInWords.phrase(for: time(9, 15)) == "quarter past nine")
        #expect(TimeInWords.phrase(for: time(9, 30)) == "half past nine")
        #expect(TimeInWords.phrase(for: time(10, 40)) == "twenty to eleven")
        #expect(TimeInWords.phrase(for: time(10, 58)) == "eleven o’clock")
        #expect(TimeInWords.phrase(for: time(12, 0)) == "noon")
        #expect(TimeInWords.phrase(for: time(23, 59)) == "midnight")
        #expect(TimeInWords.phrase(for: time(14, 25)) == "twenty-five past two")
    }
}

@MainActor
struct WallpaperMatcherTests {
    /// A fake screenshot: wallpaper everywhere, with a widget-colored block in the middle.
    private func screenshot(wallpaper: (UInt8, UInt8, UInt8), widget: (UInt8, UInt8, UInt8)) -> CGImage {
        let width = 300, height = 600
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let inWidget = (40..<260).contains(x) && (100..<300).contains(y)
                let color = inWidget ? widget : wallpaper
                let i = (y * width + x) * 4
                data[i] = color.0; data[i + 1] = color.1; data[i + 2] = color.2; data[i + 3] = 255
            }
        }
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    @Test func tunesWidgetsToADarkerWallpaper() throws {
        let paper = HexColor(hex: "#F3EFE6")!
        // iOS drew the wallpaper about 4% darker than the widget.
        let image = screenshot(wallpaper: (233, 229, 221), widget: (243, 239, 230))
        let measurement = try WallpaperMatcher.measure(image, base: paper, widgetColor: paper).get()
        #expect(measurement.difference > 5)

        let tuned = WallpaperMatcher.widgetColor(current: paper, measurement: measurement)
        // The widgets now draw the color the wallpaper actually shows.
        #expect(abs(tuned.red * 255 - 233) < 1.5)
        #expect(abs(tuned.blue * 255 - 221) < 1.5)
    }

    @Test func worksForWhite() throws {
        let white = HexColor(hex: "#FFFFFF")!
        let image = screenshot(wallpaper: (245, 245, 245), widget: (255, 255, 255))
        let measurement = try WallpaperMatcher.measure(image, base: white, widgetColor: white).get()
        let tuned = WallpaperMatcher.widgetColor(current: white, measurement: measurement)
        #expect(abs(tuned.red * 255 - 245) < 1.5)
    }

    @Test func reportsAPerfectMatch() throws {
        let paper = HexColor(hex: "#F3EFE6")!
        let image = screenshot(wallpaper: (243, 239, 230), widget: (243, 239, 230))
        let measurement = try WallpaperMatcher.measure(image, base: paper, widgetColor: paper).get()
        #expect(measurement.difference < 1)
    }

    @Test func failsWithoutTheWallpaper() {
        let paper = HexColor(hex: "#F3EFE6")!
        let image = screenshot(wallpaper: (20, 20, 20), widget: (40, 90, 200))
        #expect(throws: WallpaperMatcher.Failure.noWallpaper) {
            try WallpaperMatcher.measure(image, base: paper, widgetColor: paper).get()
        }
    }
}
