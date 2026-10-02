//
//  FocusManager.swift
//  Ebb
//
//  App-side control of Screen Time blocking: authorization, the app selection,
//  focus sessions, a nightly wind-down, and a daily usage limit.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation
import UserNotifications
import WidgetKit

@Observable
final class FocusManager {
    private enum Key {
        static let nightlyEnabled = "nightlyEnabled"
        static let nightlyStart = "nightlyStart"
        static let nightlyEnd = "nightlyEnd"
        static let limitEnabled = "limitEnabled"
        static let limitMinutes = "limitMinutes"
        static let strictSessions = "strictSessions"
    }

    /// DeviceActivity rejects intervals shorter than 15 minutes.
    static let sessionLengths = [15, 30, 60, 120, 240]

    private let center = DeviceActivityCenter()
    private let defaults = AppGroup.defaults

    var authorizationStatus: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    var errorMessage: String?

    var selection: FamilyActivitySelection {
        didSet {
            ShieldController.saveSelection(selection)
            if limitEnabled { scheduleDailyLimit() }
        }
    }

    /// Apps that stay open during work periods.
    var allowedSelection: FamilyActivitySelection {
        didSet { ShieldController.saveAllowedSelection(allowedSelection) }
    }

    var workPeriods: [WorkPeriod] {
        didSet {
            WorkPeriod.saveAll(workPeriods)
            scheduleWorkPeriods()
        }
    }

    private(set) var sessionEnd: Date?
    private(set) var activeReasons: Set<ShieldReason> = []

    var nightlyEnabled: Bool { didSet { defaults.set(nightlyEnabled, forKey: Key.nightlyEnabled); scheduleNightly() } }
    /// Minutes after midnight.
    var nightlyStart: Int { didSet { defaults.set(nightlyStart, forKey: Key.nightlyStart); scheduleNightly() } }
    var nightlyEnd: Int { didSet { defaults.set(nightlyEnd, forKey: Key.nightlyEnd); scheduleNightly() } }
    var limitEnabled: Bool { didSet { defaults.set(limitEnabled, forKey: Key.limitEnabled); scheduleDailyLimit() } }
    var limitMinutes: Int { didSet { defaults.set(limitMinutes, forKey: Key.limitMinutes); scheduleDailyLimit() } }
    /// Strict sessions can't be ended early.
    var strictSessions: Bool { didSet { defaults.set(strictSessions, forKey: Key.strictSessions) } }

    init() {
        selection = ShieldController.loadSelection()
        allowedSelection = ShieldController.loadAllowedSelection()
        workPeriods = WorkPeriod.loadAll()
        nightlyEnabled = defaults.bool(forKey: Key.nightlyEnabled)
        nightlyStart = defaults.object(forKey: Key.nightlyStart) as? Int ?? 22 * 60
        nightlyEnd = defaults.object(forKey: Key.nightlyEnd) as? Int ?? 7 * 60
        limitEnabled = defaults.bool(forKey: Key.limitEnabled)
        limitMinutes = defaults.object(forKey: Key.limitMinutes) as? Int ?? 30
        strictSessions = defaults.bool(forKey: Key.strictSessions)
        migrateToFocuses()
        refresh()
    }

    /// Focuses used to share one "allowed during work" list and blocked everything else, and
    /// wind-down was a separate setting. Now each focus has its own apps and blocks only those,
    /// so earlier work times keep the apps that were checked, and wind-down becomes a focus.
    private func migrateToFocuses() {
        let key = "focusMigrationVersion"
        guard defaults.integer(forKey: key) < 1 else { return }
        defaults.set(1, forKey: key)

        var periods = workPeriods
        for index in periods.indices where !periods[index].hasApps {
            periods[index].selection = allowedSelection
        }
        if nightlyEnabled {
            var windDown = WorkPeriod(name: "Wind-down", start: nightlyStart, end: nightlyEnd, weekdays: Set(1...7))
            windDown.selection = selection
            periods.append(windDown)
            nightlyEnabled = false
            defaults.set(false, forKey: Key.nightlyEnabled)
            center.stopMonitoring([.nightly])
            ShieldController.deactivate(.nightly)
        }
        if periods != workPeriods {
            // Observers don't run during init, so save and reschedule explicitly.
            workPeriods = periods
            WorkPeriod.saveAll(periods)
            scheduleWorkPeriods()
        }
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var selectionSummary: String {
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let sites = selection.webDomainTokens.count
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: ", ")
    }

    var isShielding: Bool { !activeReasons.isEmpty }

    var isInWorkPeriod: Bool { activeReasons.contains(.work) }

    var allowedSummary: String {
        let apps = allowedSelection.applicationTokens.count
        let sites = allowedSelection.webDomainTokens.count
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        return parts.isEmpty ? "None yet" : parts.joined(separator: ", ")
    }

    /// Whether this focus is blocking apps right now.
    func isRunning(_ period: WorkPeriod) -> Bool {
        ShieldController.activeFocusIDs.contains(period.id) && activeReasons.contains(.work)
    }

    /// The work period running now, if any.
    var currentWorkPeriod: WorkPeriod? { workPeriods.first { $0.contains(.now) } }

    /// Re-reads state the extensions may have changed.
    func refresh() {
        ShieldController.reconcileExpiredSession()
        ShieldController.reconcileWorkPeriods()
        ShieldController.pruneAllowances()
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        sessionEnd = ShieldController.sessionEnd
        activeReasons = ShieldController.activeReasons
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            errorMessage = nil
        } catch {
            errorMessage = "Screen Time access wasn't granted. Blocking needs it, and it only works on a real iPhone. (\(error.localizedDescription))"
        }
        refresh()
        if isAuthorized {
            // Schedules saved before access was granted couldn't be registered yet.
            scheduleWorkPeriods()
            scheduleNightly()
            scheduleDailyLimit()
        }
    }

    // MARK: Focus sessions

    func startSession(minutes: Int) {
        guard hasSelection else {
            errorMessage = "Choose apps to block first."
            return
        }
        let start = Date.now
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: start),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
        // Shield immediately rather than waiting for the monitor to wake up.
        ShieldController.sessionEnd = end
        ShieldController.activate(.session)
        TimeSaved.recordFocus(minutes: minutes)
        do {
            center.stopMonitoring([.session])
            try center.startMonitoring(.session, during: schedule)
            WidgetCenter.shared.reloadAllTimelines()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't schedule the end of this session, so end it manually. (\(error.localizedDescription))"
        }
        refresh()
    }

    var canEndSession: Bool { !strictSessions }

    func endSession() {
        // Only count the part of the session that actually happened.
        if let end = ShieldController.sessionEnd, end > .now {
            TimeSaved.recordFocus(minutes: -Int(end.timeIntervalSinceNow / 60))
        }
        center.stopMonitoring([.session])
        ShieldController.sessionEnd = nil
        ShieldController.deactivate(.session)
        WidgetCenter.shared.reloadAllTimelines()
        refresh()
    }

    // MARK: Schedules

    private func scheduleNightly() {
        center.stopMonitoring([.nightly])
        ShieldController.deactivate(.nightly)
        guard nightlyEnabled, isAuthorized else { refresh(); return }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: nightlyStart / 60, minute: nightlyStart % 60),
            intervalEnd: DateComponents(hour: nightlyEnd / 60, minute: nightlyEnd % 60),
            repeats: true
        )
        do {
            try center.startMonitoring(.nightly, during: schedule)
            // startMonitoring doesn't fire intervalDidStart if we're already inside the window.
            if Self.isWithinNightly(start: nightlyStart, end: nightlyEnd) {
                ShieldController.activate(.nightly)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't schedule wind-down. (\(error.localizedDescription))"
        }
        refresh()
    }

    private func scheduleDailyLimit() {
        center.stopMonitoring([.daily])
        guard limitEnabled, isAuthorized, hasSelection else {
            ShieldController.deactivate(.dailyLimit)
            refresh()
            return
        }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: limitMinutes)
        )
        do {
            try center.startMonitoring(.daily, during: schedule, events: [.dailyLimit: event])
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't set the daily limit. (\(error.localizedDescription))"
        }
        refresh()
    }

    // MARK: Work periods

    private func scheduleWorkPeriods() {
        let existing = center.activities.filter { $0.rawValue.hasPrefix(WorkPeriod.activityPrefix) }
        center.stopMonitoring(existing)
        guard isAuthorized else { refresh(); return }
        for period in workPeriods where period.isEnabled && period.start != period.end {
            // One daily schedule per period; the monitor skips days that aren't selected.
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: period.start / 60, minute: period.start % 60),
                intervalEnd: DateComponents(hour: period.end / 60, minute: period.end % 60),
                repeats: true
            )
            do {
                try center.startMonitoring(period.activityName, during: schedule)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't schedule \(period.name). (\(error.localizedDescription))"
            }
        }
        // startMonitoring doesn't fire intervalDidStart if a period is already underway.
        ShieldController.reconcileWorkPeriods()
        refresh()
    }

    // MARK: Breather allowances

    /// Unblocks an app until it has been used for `minutes`, or until midnight.
    func grantAllowance(for token: ApplicationToken, minutes: Int) {
        let slot = ShieldController.nextAllowanceSlot()
        let activity = Allowance.activityName(slot: slot)
        center.stopMonitoring([activity])

        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
        // DeviceActivity needs at least a 15-minute window.
        let end = max(midnight.addingTimeInterval(-60), now.addingTimeInterval(16 * 60))
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: now),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
        let event = DeviceActivityEvent(applications: [token], threshold: DateComponents(minute: minutes))

        ShieldController.addAllowance(Allowance(token: token, minutes: minutes, granted: now, slot: slot))
        do {
            try center.startMonitoring(activity, during: schedule, events: [.allowanceUsed: event])
            errorMessage = nil
        } catch {
            // Without a monitor the app would stay open all day, so block it again.
            ShieldController.endAllowance(slot: slot)
            errorMessage = "Couldn't start the timer for this app. (\(error.localizedDescription))"
        }
        refresh()
    }

    /// Notifications let the block screen's "Take a breath" button open Ebb.
    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Whether `now` falls inside a window that may wrap past midnight.
    static func isWithinNightly(start: Int, end: Int, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start == end { return false }
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }
}
