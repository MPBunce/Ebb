//
//  LauncherStore.swift
//  Ebb
//

import Foundation
import Observation
import SwiftUI
import UIKit
import WidgetKit

@Observable
final class LauncherStore {
    private(set) var targets: [LaunchTarget] = []
    /// The app widgets, each with up to six apps.
    private(set) var lists: [AppWidgetList] = []
    /// Mirrors `EbbPlus.isActive` so views update when the plan changes.
    private(set) var isPlus = EbbPlus.isActive
    private(set) var events: [LaunchEvent] = []

    /// An app waiting behind a mindful pause.
    var pendingPause: LaunchTarget?
    /// An app whose link didn't open, so the UI can offer to fix it.
    var failedLaunch: LaunchTarget?

    private let directory: URL
    private var targetsURL: URL { directory.appending(path: "targets.json") }
    private var eventsURL: URL { directory.appending(path: "events.json") }
    private var listsURL: URL { directory.appending(path: "lists.json") }

    /// How long launch history is kept on-device.
    static let historyDays = 30

    init(directory: URL = AppGroup.containerURL.appending(path: "Ebb", directoryHint: .isDirectory)) {
        self.directory = directory
        TimeSaved.markInstallIfNeeded()
        WidgetTuning.applyCalibrationUpdate()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        targets = Self.read([LaunchTarget].self, from: targetsURL) ?? []
        events = Self.read([LaunchEvent].self, from: eventsURL) ?? []
        lists = Self.read([AppWidgetList].self, from: listsURL) ?? migrateFavorites()
        if lists.isEmpty { lists = [AppWidgetList(name: "Widget 1")] }
        mergeDuplicates()
        pruneHistory()
        // Keep widgets in sync even if their copy is missing or from an older version.
        syncWidgets()
    }

    // MARK: Queries

    /// Apps on the first app widget, used for previews.
    var primaryApps: [LaunchTarget] { lists.first.map(apps(in:)) ?? [] }

    /// Every app that's on at least one app widget.
    var widgetAppIDs: Set<UUID> { Set(lists.flatMap(\.appIDs)) }

    func apps(in list: AppWidgetList) -> [LaunchTarget] {
        list.appIDs.compactMap(target(id:))
    }

    /// Lists past the plan's limit stay saved but are locked.
    func isLocked(_ list: AppWidgetList) -> Bool {
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return false }
        return index >= maxLists
    }

    var maxLists: Int { isPlus ? EbbPlus.plusAppWidgets : EbbPlus.freeAppWidgets }

    var canAddList: Bool { lists.count < maxLists }

    /// Call after the plan changes so limits and widgets update.
    func refreshPlan() {
        isPlus = EbbPlus.isActive
        syncWidgets()
    }

    /// Everything for the app library, alphabetical, hidden apps excluded unless searched for.
    func library(matching query: String) -> [LaunchTarget] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matches = trimmed.isEmpty
            ? targets.filter { !$0.isHidden }
            : targets.filter { $0.name.localizedStandardContains(trimmed) }
        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func target(id: UUID) -> LaunchTarget? {
        targets.first { $0.id == id }
    }

    func contains(catalogApp app: CatalogApp) -> Bool {
        existing(name: app.name, bundleID: app.bundleID) != nil
    }

    /// The app already in Ebb that matches this name or App Store bundle ID, if any.
    /// Used everywhere apps are added, so the same app never ends up in Ebb twice.
    func existing(name: String, bundleID: String?) -> LaunchTarget? {
        targets.first { Self.isSameApp($0, name: name, bundleID: bundleID) }
    }

    /// The app widgets an app is on, by name.
    func widgetNames(for appID: UUID) -> [String] {
        lists.filter { $0.appIDs.contains(appID) }.map(\.name)
    }

    /// Free spots across the unlocked app widgets.
    var freeWidgetSlots: Int {
        lists.prefix(maxLists).reduce(0) { $0 + AppWidgetList.capacity - min($1.appIDs.count, AppWidgetList.capacity) }
    }

    private static func isSameApp(_ target: LaunchTarget, name: String, bundleID: String?) -> Bool {
        if let bundleID, let other = target.iconBundleID, other.caseInsensitiveCompare(bundleID) == .orderedSame {
            return true
        }
        return normalized(target.name) == normalized(name)
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: Editing

    /// Adds an app, or returns the matching app already in Ebb instead of adding a duplicate.
    @discardableResult
    func add(_ target: LaunchTarget) -> LaunchTarget {
        if let match = existing(name: target.name, bundleID: target.bundleID) { return match }
        targets.append(target)
        saveTargets()
        return target
    }

    func update(_ target: LaunchTarget) {
        guard let index = targets.firstIndex(where: { $0.id == target.id }) else { return }
        targets[index] = target
        saveTargets()
    }

    func remove(_ target: LaunchTarget) {
        targets.removeAll { $0.id == target.id }
        for index in lists.indices {
            lists[index].appIDs.removeAll { $0 == target.id }
        }
        saveTargets()
        saveLists()
    }

    // MARK: App widgets

    @discardableResult
    func addList() -> AppWidgetList? {
        guard canAddList else { return nil }
        let list = AppWidgetList(name: "Widget \(lists.count + 1)")
        lists.append(list)
        saveLists()
        return list
    }

    func renameList(_ id: UUID, to name: String) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        lists[index].name = trimmed.isEmpty ? "Widget \(index + 1)" : trimmed
        saveLists()
    }

    /// Deletes an app widget. There's always at least one.
    func deleteList(_ id: UUID) {
        guard lists.count > 1 else { return }
        lists.removeAll { $0.id == id }
        saveLists()
    }

    /// Adds or removes an app. Full lists ignore additions.
    func toggle(_ appID: UUID, in listID: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        if let position = lists[index].appIDs.firstIndex(of: appID) {
            lists[index].appIDs.remove(at: position)
        } else if !lists[index].isFull {
            lists[index].appIDs.append(appID)
        }
        saveLists()
    }

    func moveApps(in listID: UUID, from source: IndexSet, to destination: Int) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[index].appIDs.move(fromOffsets: source, toOffset: destination)
        saveLists()
    }

    /// Puts an app on the first unlocked widget with room. Returns false if they're all full.
    @discardableResult
    func addToFirstOpenList(_ appID: UUID) -> Bool {
        guard !widgetAppIDs.contains(appID) else { return true }
        for index in lists.indices.prefix(maxLists) where !lists[index].isFull {
            lists[index].appIDs.append(appID)
            saveLists()
            return true
        }
        return false
    }

    /// Earlier versions could add the same app twice (for example once from the list and
    /// once from App Store search). Keep the first copy and point widgets at it.
    private func mergeDuplicates() {
        var kept: [LaunchTarget] = []
        var replacement: [UUID: UUID] = [:]
        for target in targets {
            if let index = kept.firstIndex(where: { Self.isSameApp($0, name: target.name, bundleID: target.bundleID) }) {
                replacement[target.id] = kept[index].id
                kept[index].isMindful = kept[index].isMindful || target.isMindful
                if kept[index].bundleID == nil { kept[index].bundleID = target.bundleID }
            } else {
                kept.append(target)
            }
        }
        guard !replacement.isEmpty else { return }
        targets = kept
        for index in lists.indices {
            var seen = Set<UUID>()
            lists[index].appIDs = lists[index].appIDs
                .map { replacement[$0] ?? $0 }
                .filter { seen.insert($0).inserted }
        }
        for index in events.indices {
            if let id = replacement[events[index].targetID] { events[index].targetID = id }
        }
        Self.write(targets, to: targetsURL)
        Self.write(lists, to: listsURL)
        saveEvents()
    }

    /// Before app widgets, apps were marked as favorites. Spread those over widgets of six.
    private func migrateFavorites() -> [AppWidgetList] {
        struct Legacy: Decodable { var id: UUID; var isFavorite: Bool? }
        let legacy = Self.read([Legacy].self, from: targetsURL) ?? []
        let favorites = legacy.filter { $0.isFavorite == true }.map(\.id)
        guard !favorites.isEmpty else { return [] }
        let chunks = stride(from: 0, to: favorites.count, by: AppWidgetList.capacity).map {
            Array(favorites[$0..<min($0 + AppWidgetList.capacity, favorites.count)])
        }
        let migrated = chunks.enumerated().map { AppWidgetList(name: "Widget \($0.offset + 1)", appIDs: $0.element) }
        Self.write(migrated, to: listsURL)
        return migrated
    }

    // MARK: Launching

    /// Opens an app, or holds it behind a mindful pause first.
    func requestLaunch(_ target: LaunchTarget) {
        if target.isMindful {
            pendingPause = target
        } else {
            open(target, intention: nil)
        }
    }

    func requestLaunch(id: UUID) {
        guard let target = target(id: id) else { return }
        requestLaunch(target)
    }

    func open(_ target: LaunchTarget, intention: String?) {
        pendingPause = nil
        guard let url = target.url else {
            failedLaunch = target
            return
        }
        log(target, outcome: .opened, intention: intention)
        UIApplication.shared.open(url) { [weak self] success in
            if !success { self?.failedLaunch = target }
        }
    }

    func resist(_ target: LaunchTarget, intention: String?) {
        pendingPause = nil
        log(target, outcome: .resisted, intention: intention)
        TimeSaved.recordResist()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: History

    private func log(_ target: LaunchTarget, outcome: LaunchEvent.Outcome, intention: String?) {
        let note = intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        events.append(LaunchEvent(
            targetID: target.id,
            name: target.name,
            date: .now,
            outcome: outcome,
            intention: note?.isEmpty == false ? note : nil
        ))
        saveEvents()
    }

    func clearHistory() {
        events = []
        saveEvents()
    }

    private func pruneHistory() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.historyDays, to: .now) else { return }
        let before = events.count
        events.removeAll { $0.date < cutoff }
        if events.count != before { saveEvents() }
    }

    // MARK: Persistence

    private func saveTargets() {
        Self.write(targets, to: targetsURL)
        syncWidgets()
    }

    private func saveLists() {
        Self.write(lists, to: listsURL)
        syncWidgets()
    }

    private func syncWidgets() {
        WidgetApp.save(targets.map {
            WidgetApp(id: $0.id, name: $0.name, url: $0.url, isMindful: $0.isMindful)
        })
        AppWidgetList.saveAll(lists)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func saveEvents() {
        Self.write(events, to: eventsURL)
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
