//
//  ShieldController.swift
//  Shared between Ebb and its Screen Time extensions.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Why apps are currently shielded. Shields stay up while at least one reason is active,
/// so a nightly wind-down ending doesn't cancel a focus session that is still running.
nonisolated enum ShieldReason: String, Codable, CaseIterable {
    case session
    case nightly
    case dailyLimit
    /// A work period: everything is blocked except the allowed apps.
    case work
}

nonisolated extension DeviceActivityName {
    static let session = DeviceActivityName("ebb.session")
    static let nightly = DeviceActivityName("ebb.nightly")
    static let daily = DeviceActivityName("ebb.daily")
}

nonisolated extension DeviceActivityEvent.Name {
    static let dailyLimit = DeviceActivityEvent.Name("ebb.dailyLimit")
    static let allowanceUsed = DeviceActivityEvent.Name("ebb.allowanceUsed")
}

nonisolated extension ManagedSettingsStore.Name {
    static let ebb = ManagedSettingsStore.Name("ebb")
}

/// Time the user chose to spend in a blocked app after a breather. The app stays
/// unblocked until they've used it for `minutes`, or the day ends.
nonisolated struct Allowance: Codable, Hashable {
    var token: ApplicationToken
    var minutes: Int
    var granted: Date
    /// Which DeviceActivity slot tracks its usage.
    var slot: Int

    static let slotCount = 4
    static let activityPrefix = "ebb.allow."

    static func activityName(slot: Int) -> DeviceActivityName {
        DeviceActivityName(activityPrefix + String(slot))
    }

    static func slot(for activity: DeviceActivityName) -> Int? {
        guard activity.rawValue.hasPrefix(activityPrefix) else { return nil }
        return Int(activity.rawValue.dropFirst(activityPrefix.count))
    }
}

/// Owns the app selections and the managed shield. Safe to call from extensions.
nonisolated enum ShieldController {
    private enum Key {
        static let selection = "blockSelection"
        static let allowedSelection = "workAllowedSelection"
        static let reasons = "activeShieldReasons"
        static let sessionEnd = "sessionEnd"
        static let allowances = "allowances"
        static let pendingUnlock = "pendingUnlockToken"
    }

    private static var store: ManagedSettingsStore { ManagedSettingsStore(named: .ebb) }

    // MARK: Selections

    /// Apps blocked during sessions, wind-down, and after the daily limit.
    static func loadSelection() -> FamilyActivitySelection { load(Key.selection) }

    static func saveSelection(_ selection: FamilyActivitySelection) {
        save(selection, Key.selection)
    }

    /// Apps that stay available during work periods.
    static func loadAllowedSelection() -> FamilyActivitySelection { load(Key.allowedSelection) }

    static func saveAllowedSelection(_ selection: FamilyActivitySelection) {
        save(selection, Key.allowedSelection)
    }

    private static func load(_ key: String) -> FamilyActivitySelection {
        guard let data = AppGroup.defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    private static func save(_ selection: FamilyActivitySelection, _ key: String) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        AppGroup.defaults.set(data, forKey: key)
        refreshShield()
    }

    // MARK: Reasons

    static var activeReasons: Set<ShieldReason> {
        let raw = AppGroup.defaults.stringArray(forKey: Key.reasons) ?? []
        return Set(raw.compactMap(ShieldReason.init(rawValue:)))
    }

    private static func setActiveReasons(_ reasons: Set<ShieldReason>) {
        AppGroup.defaults.set(reasons.map(\.rawValue).sorted(), forKey: Key.reasons)
    }

    static func activate(_ reason: ShieldReason) {
        var reasons = activeReasons
        reasons.insert(reason)
        setActiveReasons(reasons)
        refreshShield()
    }

    static func deactivate(_ reason: ShieldReason) {
        var reasons = activeReasons
        reasons.remove(reason)
        setActiveReasons(reasons)
        refreshShield()
    }

    static var sessionEnd: Date? {
        get { AppGroup.defaults.object(forKey: Key.sessionEnd) as? Date }
        set { AppGroup.defaults.set(newValue, forKey: Key.sessionEnd) }
    }

    /// Clears a focus session whose end time has passed, in case the monitor extension
    /// didn't get a chance to (it is best-effort on iOS).
    static func reconcileExpiredSession(now: Date = .now) {
        if let end = sessionEnd, end <= now, activeReasons.contains(.session) {
            sessionEnd = nil
            deactivate(.session)
        }
    }

    /// Turns work blocking on or off to match the schedule, in case a monitor callback was missed.
    static func reconcileWorkPeriods(now: Date = .now) {
        let inWork = WorkPeriod.loadAll().contains { $0.contains(now) }
        let active = activeReasons.contains(.work)
        if inWork && !active { activate(.work) }
        if !inWork && active { deactivate(.work) }
    }

    // MARK: Allowances

    static var allowances: [Allowance] {
        guard let data = AppGroup.defaults.data(forKey: Key.allowances) else { return [] }
        return (try? JSONDecoder().decode([Allowance].self, from: data)) ?? []
    }

    private static func setAllowances(_ allowances: [Allowance]) {
        guard let data = try? JSONEncoder().encode(allowances) else { return }
        AppGroup.defaults.set(data, forKey: Key.allowances)
    }

    /// A free monitoring slot for a new allowance, reusing the oldest if all are taken.
    static func nextAllowanceSlot() -> Int {
        let used = Set(allowances.map(\.slot))
        if let free = (0..<Allowance.slotCount).first(where: { !used.contains($0) }) { return free }
        return allowances.min { $0.granted < $1.granted }?.slot ?? 0
    }

    static func addAllowance(_ allowance: Allowance) {
        var current = allowances.filter { $0.slot != allowance.slot && $0.token != allowance.token }
        current.append(allowance)
        setAllowances(current)
        refreshShield()
    }

    static func endAllowance(slot: Int) {
        setAllowances(allowances.filter { $0.slot != slot })
        refreshShield()
    }

    /// Allowances only last for the day they were granted.
    static func pruneAllowances(now: Date = .now, calendar: Calendar = .current) {
        let current = allowances
        let kept = current.filter { calendar.isDate($0.granted, inSameDayAs: now) }
        if kept.count != current.count {
            setAllowances(kept)
            refreshShield()
        }
    }

    // MARK: Pending unlock

    /// The blocked app the user asked to breathe through, set by the shield and read by Ebb.
    static var pendingUnlock: ApplicationToken? {
        get {
            guard let data = AppGroup.defaults.data(forKey: Key.pendingUnlock) else { return nil }
            return try? JSONDecoder().decode(ApplicationToken.self, from: data)
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) }
            AppGroup.defaults.set(data, forKey: Key.pendingUnlock)
        }
    }

    // MARK: Shield

    /// Rebuilds the shield from the active reasons, selections, and allowances.
    static func refreshShield() {
        let reasons = activeReasons
        let store = store
        guard !reasons.isEmpty else {
            store.clearAllSettings()
            return
        }

        let allowed = Set(allowances.map(\.token))

        if reasons.contains(.work) {
            // Block everything except the allowed apps, sites, and categories.
            let selection = loadAllowedSelection()
            let exceptApps = selection.applicationTokens.union(allowed)
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: exceptApps)
            store.shield.webDomains = nil
            store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
            return
        }

        let selection = loadSelection()
        let apps = selection.applicationTokens.subtracting(allowed)
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: allowed)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
    }
}
