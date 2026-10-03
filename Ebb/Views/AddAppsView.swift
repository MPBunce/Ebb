//
//  AddAppsView.swift
//  Ebb
//
//  The one place apps are added: search, pick, and they go straight onto a widget.
//  Also the manual link/Shortcut editor and the "Open App" Shortcut walkthrough.
//

import SwiftUI

/// One app the picker can offer: from Ebb's list of known apps, already added, or the App Store.
struct PickerApp: Identifiable, Hashable {
    var name: String
    var bundleID: String?
    /// The launch link. Nil means it opens through an "Open App" Shortcut.
    var scheme: String?
    var artworkURL: URL?
    var suggestsPause = false

    var id: String { bundleID?.lowercased() ?? "name:" + name.lowercased() }
    var needsShortcut: Bool { scheme == nil }
    var shortcutName: String { "Open \(name)" }

    init(_ app: CatalogApp) {
        name = app.name
        bundleID = app.bundleID
        scheme = app.scheme
        suggestsPause = app.suggestsPause
    }

    init(_ app: AppStoreSearchView.StoreApp, query: String) {
        name = app.shortName(matching: query)
        bundleID = app.bundleId
        scheme = AppCatalog.scheme(forBundleID: app.bundleId)
        artworkURL = app.artworkUrl100.flatMap(URL.init(string:))
    }

    init(_ target: LaunchTarget) {
        name = target.name
        bundleID = target.iconBundleID
        // Already set up, however it opens, so it never needs a new Shortcut.
        if case .urlScheme(let scheme) = target.method { self.scheme = scheme } else { scheme = "" }
    }

    func makeTarget() -> LaunchTarget {
        let method: LaunchTarget.Method = scheme.map { .urlScheme($0) } ?? .shortcut(shortcutName)
        return LaunchTarget(name: name, method: method, isMindful: suggestsPause, bundleID: bundleID)
    }
}

/// Settings › Apps › Add apps, and a widget's Add apps: one sheet for adding apps everywhere.
struct AddAppsView: View {
    /// The app widget picked apps go on. Nil puts them on the first widgets with room.
    var widgetID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppPicker(widgetID: widgetID) { dismiss() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

/// Search and pick apps. Apps on this iPhone come first, then App Store results.
/// In a sheet, picks wait for the Add button; during onboarding they apply straight away.
struct AppPicker: View {
    @Environment(LauncherStore.self) private var store
    var widgetID: UUID?
    /// Onboarding: tapping adds or removes an app at once, with no Add button.
    var addsImmediately = false
    var onDone: () -> Void = {}

    @State private var query = ""
    @State private var selection: [PickerApp] = []
    @State private var storeResults: [AppStoreSearchView.StoreApp] = []
    @State private var isSearchingStore = false
    @State private var installed: [CatalogApp] = []
    @State private var fullMessage = false
    @State private var shortcutQueue: [PickerApp] = []
    @State private var settingUpShortcut: PickerApp?
    @State private var isAddingManually = false

    private var widget: AppWidgetList? { widgetID.flatMap { id in store.lists.first { $0.id == id } } }

    // MARK: What's shown

    private func status(of app: PickerApp) -> AppPickerStatus {
        guard let target = store.existing(name: app.name, bundleID: app.bundleID) else { return .available }
        if let widget {
            return widget.appIDs.contains(target.id) ? .added("On this widget") : .unplaced
        }
        let names = store.widgetNames(for: target.id)
        return names.isEmpty ? .unplaced : .added("On \(names.joined(separator: ", "))")
    }

    private func isSelected(_ app: PickerApp) -> Bool {
        // Onboarding applies taps at once, so "selected" means "added".
        if addsImmediately { return store.existing(name: app.name, bundleID: app.bundleID) != nil }
        return selection.contains { $0.id == app.id }
    }

    /// Apps already in Ebb that aren't on this widget (or on any widget).
    private var unplacedApps: [PickerApp] {
        store.targets
            .filter { target in widget.map { !$0.appIDs.contains(target.id) } ?? store.widgetNames(for: target.id).isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(PickerApp.init)
    }

    private var installedThirdParty: [PickerApp] {
        listedOnce(installed.filter { $0.category != .essentials })
    }

    private var appleApps: [PickerApp] {
        listedOnce(AppCatalog.apps.filter { $0.category == .essentials })
    }

    /// Catalog apps, alphabetical, minus any already shown in "Added, not on a widget".
    private func listedOnce(_ apps: [CatalogApp]) -> [PickerApp] {
        let shown = addsImmediately ? [] : Set(unplacedApps.map(\.name))
        return apps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(PickerApp.init)
            .filter { app in
                guard let target = store.existing(name: app.name, bundleID: app.bundleID) else { return true }
                return !shown.contains(target.name)
            }
    }

    /// Search: matching apps from Ebb's list (installed first), then the App Store, without repeats.
    private var searchResults: [PickerApp] {
        let catalog = AppCatalog.apps
            .filter { $0.name.localizedStandardContains(query) }
            .sorted { lhs, rhs in installed.contains(lhs) && !installed.contains(rhs) }
            .map(PickerApp.init)
        var seen = Set(catalog.map(\.id))
        let fromStore = storeResults.map { PickerApp($0, query: query) }.filter { seen.insert($0.id).inserted }
        return catalog + fromStore
    }

    /// Spots left where picked apps will go.
    private var freeSlots: Int {
        if let widget { return AppWidgetList.capacity - widget.appIDs.count }
        return store.freeWidgetSlots
    }

    /// Where the picked apps will end up, under the Add button.
    private var destinationDetail: String {
        if freeSlots >= selection.count { return "to \(destinationName)" }
        if freeSlots == 0 { return selection.count == 1 ? "Your widgets are full, so it'll go in Apps" : "Your widgets are full, so they'll go in Apps" }
        return "\(freeSlots) fit on your widgets; the rest go in Apps"
    }

    private var destinationName: String {
        if let widget { return widget.name }
        return store.lists.prefix(store.maxLists).first { !$0.isFull }?.name ?? "your widgets"
    }

    var body: some View {
        List {
            if query.isEmpty {
                if !addsImmediately && !unplacedApps.isEmpty {
                    section(widget == nil ? "Added, not on a widget" : "Already in Ebb", unplacedApps)
                }
                if !installedThirdParty.isEmpty {
                    section("On this iPhone", installedThirdParty)
                }
                section("Apple apps", appleApps)
            } else {
                if !searchResults.isEmpty {
                    section("Results", searchResults)
                }
                if isSearchingStore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                Button {
                    isAddingManually = true
                } label: {
                    Label("Add with a link or Shortcut", systemImage: "link")
                }
            } header: {
                Text("Can't find an app?")
            } footer: {
                Text(query.isEmpty
                     ? "Search for any app on the App Store. iPhone only lets Ebb check for some apps, so yours may not be listed until you search."
                     : "A Shortcut with the Open App action works for every app.")
            }
        }
        .navigationTitle(widget.map { "Add to \($0.name)" } ?? "Add apps")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search apps")
        .task(id: query) { await searchStore() }
        .onAppear { installed = InstalledApps.detect() }
        .safeAreaInset(edge: .bottom) {
            if !addsImmediately { addBar }
        }
        .sheet(item: $settingUpShortcut) { app in
            NavigationStack {
                ShortcutSetupView(name: app.name, bundleID: app.bundleID, shortcutName: app.shortcutName) { shortcut in
                    if let shortcut {
                        var target = app.makeTarget()
                        target.method = .shortcut(shortcut)
                        place(store.add(target))
                    }
                    nextShortcut()
                }
            }
            // A fresh screen per app, so the suggested name doesn't carry over.
            .id(app.id)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isAddingManually) {
            NavigationStack { TargetEditor(target: nil, widgetID: widgetID) }
        }
    }

    private func section(_ title: String, _ apps: [PickerApp]) -> some View {
        Section(title) {
            ForEach(apps) { app in
                PickerRow(app: app, status: addsImmediately ? .available : status(of: app),
                          isSelected: isSelected(app)) { tap(app) }
            }
        }
    }

    private var addBar: some View {
        VStack(spacing: 6) {
            if fullMessage {
                Text(widget == nil ? "Your app widgets are full" : "\(destinationName) is full: an app widget holds \(AppWidgetList.capacity) apps")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(action: commit) {
                VStack(spacing: 2) {
                    Text(selection.isEmpty ? "Pick apps to add" : selection.count == 1 ? "Add 1 app" : "Add \(selection.count) apps")
                        .font(.headline)
                    if !selection.isEmpty {
                        Text(destinationDetail)
                            .font(.caption)
                            .opacity(0.75)
                    }
                }
            }
            .buttonStyle(CapsuleButtonStyle())
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.default, value: fullMessage)
    }

    // MARK: Actions

    private func tap(_ app: PickerApp) {
        if addsImmediately {
            toggleNow(app)
            return
        }
        if let index = selection.firstIndex(where: { $0.id == app.id }) {
            selection.remove(at: index)
            fullMessage = false
            return
        }
        // Only a specific widget has a hard limit; apps past "your widgets" still join your apps.
        if widget != nil && selection.count >= freeSlots {
            fullMessage = true
            return
        }
        selection.append(app)
    }

    /// Onboarding: add (or take off) right away.
    private func toggleNow(_ app: PickerApp) {
        if let target = store.existing(name: app.name, bundleID: app.bundleID) {
            store.remove(target)
        } else if app.needsShortcut {
            shortcutQueue = [app]
            nextShortcut()
        } else {
            place(store.add(app.makeTarget()))
        }
    }

    private func commit() {
        var needsShortcuts: [PickerApp] = []
        for app in selection {
            if let target = store.existing(name: app.name, bundleID: app.bundleID) {
                place(target)
            } else if app.needsShortcut {
                needsShortcuts.append(app)
            } else {
                place(store.add(app.makeTarget()))
            }
        }
        selection = []
        shortcutQueue = needsShortcuts
        nextShortcut()
    }

    /// Shows the next app that needs a Shortcut, or finishes.
    private func nextShortcut() {
        guard !shortcutQueue.isEmpty else {
            settingUpShortcut = nil
            if !addsImmediately { onDone() }
            return
        }
        let next = shortcutQueue.removeFirst()
        // Wait for the list (or the previous sheet) to settle, or the sheet may not show.
        let delay = settingUpShortcut == nil ? 150 : 450
        settingUpShortcut = nil
        Task {
            try? await Task.sleep(for: .milliseconds(delay))
            settingUpShortcut = next
        }
    }

    private func place(_ target: LaunchTarget) {
        if let widgetID {
            if widget?.appIDs.contains(target.id) == false { store.toggle(target.id, in: widgetID) }
        } else {
            store.addToFirstOpenList(target.id)
        }
    }

    private func searchStore() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { storeResults = []; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearchingStore = true
        defer { isSearchingStore = false }
        let results = await AppStoreSearchView.search(term)
        guard !Task.isCancelled else { return }
        storeResults = results
    }
}

/// A full-width capsule in the text color, so it reads in every Ebb color theme
/// (the accent color is the text color, which makes the system prominent style unreadable).
struct CapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color(.systemBackground) : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(isEnabled ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.regularMaterial)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Whether an app in the picker can be added.
enum AppPickerStatus {
    case available
    /// Already where it would go; the text says where.
    case added(String)
    /// In Ebb, but not on this widget (or any widget).
    case unplaced

    var isAdded: Bool { if case .added = self { true } else { false } }
}

/// One app in the picker: icon, name, what happens if you add it, and a selection circle.
private struct PickerRow: View {
    let app: PickerApp
    let status: AppPickerStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                indicator
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(status.isAdded)
        .accessibilityAddTraits(isSelected || status.isAdded ? .isSelected : [])
    }

    @ViewBuilder
    private var icon: some View {
        if let artworkURL = app.artworkURL {
            AsyncImage(url: artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            AppIconView(name: app.name, bundleID: app.bundleID, size: 40)
        }
    }

    private var detail: String? {
        switch status {
        case .added(let text): return text
        case .unplaced: return nil
        case .available: return app.needsShortcut ? "Opens with a quick Shortcut" : nil
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if status.isAdded {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

/// Create or edit a launch target.
struct TargetEditor: View {
    enum Kind: String, CaseIterable, Identifiable {
        case urlScheme = "URL scheme"
        case shortcut = "Shortcut"
        case website = "Website"
        var id: Self { self }
    }

    @Environment(LauncherStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let original: LaunchTarget?
    /// A new app goes straight onto this app widget, when set.
    var widgetID: UUID?
    @State private var name: String
    @State private var kind: Kind
    @State private var value: String
    @State private var isMindful: Bool
    @State private var isHidden: Bool

    init(target: LaunchTarget?, widgetID: UUID? = nil) {
        original = target
        self.widgetID = widgetID
        _name = State(initialValue: target?.name ?? "")
        _isMindful = State(initialValue: target?.isMindful ?? false)
        _isHidden = State(initialValue: target?.isHidden ?? false)
        switch target?.method {
        case .urlScheme(let scheme)?:
            _kind = State(initialValue: .urlScheme); _value = State(initialValue: scheme)
        case .shortcut(let shortcut)?:
            _kind = State(initialValue: .shortcut); _value = State(initialValue: shortcut)
        case .website(let address)?:
            _kind = State(initialValue: .website); _value = State(initialValue: address)
        case nil:
            _kind = State(initialValue: .shortcut); _value = State(initialValue: "")
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedValue: String { value.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
            }
            Section {
                Picker("Open with", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField(placeholder, text: $value)
                    .textInputAutocapitalization(kind == .shortcut ? .sentences : .never)
                    .autocorrectionDisabled()
                    .keyboardType(kind == .shortcut ? .default : .URL)
            } footer: {
                Text(help)
            }
            Section {
                Toggle("Mindful pause", isOn: $isMindful)
                Toggle("Hide from list", isOn: $isHidden)
            } footer: {
                Text("Hidden apps only show up when you search for them.")
            }
            if let original {
                Section {
                    Button("Test link") { store.open(makeTarget(id: original.id), intention: nil) }
                    Button("Delete", role: .destructive) {
                        store.remove(original)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(original == nil ? "New app" : "Edit app")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    var target = makeTarget(id: original?.id ?? UUID())
                    if original == nil {
                        // Adding an app Ebb already has updates how it opens instead of adding it twice.
                        if let match = store.existing(name: target.name, bundleID: nil) {
                            target.id = match.id
                            target.bundleID = match.bundleID
                            store.update(target)
                        } else {
                            store.add(target)
                        }
                        if let widgetID {
                            if store.lists.first(where: { $0.id == widgetID })?.appIDs.contains(target.id) == false {
                                store.toggle(target.id, in: widgetID)
                            }
                        } else {
                            store.addToFirstOpenList(target.id)
                        }
                    } else {
                        store.update(target)
                    }
                    dismiss()
                }
                .disabled(trimmedName.isEmpty || trimmedValue.isEmpty)
            }
        }
    }

    private func makeTarget(id: UUID) -> LaunchTarget {
        let method: LaunchTarget.Method = switch kind {
        case .urlScheme: .urlScheme(trimmedValue)
        case .shortcut: .shortcut(trimmedValue)
        case .website: .website(trimmedValue)
        }
        return LaunchTarget(id: id, name: trimmedName, method: method,
                            isMindful: isMindful, isHidden: isHidden, bundleID: original?.bundleID)
    }

    private var placeholder: String {
        switch kind {
        case .urlScheme: "e.g. spotify://"
        case .shortcut: "Shortcut name, e.g. Open Camera"
        case .website: "e.g. news.ycombinator.com"
        }
    }

    private var help: String {
        switch kind {
        case .urlScheme:
            "Opens the app directly. Many apps publish a scheme, but some don't."
        case .shortcut:
            "Works for any app. In Shortcuts, create a shortcut with the “Open App” action and enter its exact name here. Shortcuts may briefly flash on screen."
        case .website:
            "Opens in your default browser. Handy for using a site instead of its app."
        }
    }
}

/// App Store lookups used by the app search.
enum AppStoreSearchView {
    struct StoreApp: Decodable, Identifiable, Hashable {
        let trackId: Int
        let trackName: String
        let bundleId: String
        let sellerName: String?
        let artworkUrl100: String?
        var id: Int { trackId }

        /// "Spotify: Music and Podcasts" reads as "Spotify" on a widget.
        var shortName: String { shortName(matching: "") }

        /// The app's name without its App Store tagline. Usually that's the part before
        /// the colon or dash, unless only the part after it matches the search
        /// ("LINE: Disney Tsum Tsum" for "Disney").
        func shortName(matching query: String) -> String {
            var parts = [trackName]
            for separator in [": ", " - ", " – ", " — ", " | "] {
                parts = parts.flatMap { $0.components(separatedBy: separator) }
            }
            parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let first = parts.first else { return trackName }
            let term = query.trimmingCharacters(in: .whitespaces)
            if !term.isEmpty, !first.localizedStandardContains(term),
               let match = parts.dropFirst().first(where: { $0.localizedStandardContains(term) }) {
                return match
            }
            return first
        }
    }

    private struct Response: Decodable { let results: [StoreApp] }

    static func search(_ term: String) async -> [StoreApp] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "us"),
            URLQueryItem(name: "limit", value: "15"),
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return [] }
        return decoded.results
    }
}

/// Walks through making an "Open App" Shortcut, for apps iOS gives no launch link
/// (Camera, Clock, and some App Store apps). Done once per app.
struct ShortcutSetupView: View {
    @Environment(\.openURL) private var openURL
    let name: String
    let bundleID: String?
    /// Called with the shortcut's name when added, or nil when skipped.
    let onFinish: (String?) -> Void

    @State private var shortcutName: String
    @State private var openedShortcuts = false
    @State private var showName = false

    init(name: String, bundleID: String?, shortcutName: String, onFinish: @escaping (String?) -> Void) {
        self.name = name
        self.bundleID = bundleID
        self.onFinish = onFinish
        _shortcutName = State(initialValue: shortcutName)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    AppIconView(name: name, bundleID: bundleID, size: 64)
                    Text("Set up \(name)")
                        .font(.title2.weight(.semibold))
                    Text("iPhone doesn't let other apps open \(name) directly, so Ebb uses a Shortcut. It takes about 20 seconds, and you only do it once.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                StepRow(number: 1, title: "Tap Create Shortcut below",
                        detail: "Shortcuts opens a new, empty shortcut. Ebb copies its name for you.")
                StepRow(number: 2, title: "Add Open App",
                        detail: "Search the actions for “Open App”, tap it, then tap App and choose \(name).")
                StepRow(number: 3, title: "Name it and come back",
                        detail: "Tap the name at the top, choose Rename, paste “\(shortcutName)”, then tap Done and return to Ebb.")
            }

            Section {
                Button {
                    UIPasteboard.general.string = shortcutName
                    openedShortcuts = true
                    if let url = URL(string: "shortcuts://create-shortcut") { openURL(url) }
                } label: {
                    Label(openedShortcuts ? "Open Shortcuts again" : "Create Shortcut", systemImage: "square.on.square")
                        .font(.headline)
                }
                .buttonStyle(CapsuleButtonStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if openedShortcuts {
                    Button {
                        var components = URLComponents(string: "shortcuts://run-shortcut")
                        components?.queryItems = [URLQueryItem(name: "name", value: shortcutName)]
                        if let url = components?.url { openURL(url) }
                    } label: {
                        Label("Test it", systemImage: "play")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                }
            } footer: {
                if openedShortcuts {
                    Text("Test it should open \(name). If Shortcuts says it can't find the shortcut, check its name matches “\(shortcutName)” exactly.")
                }
            }

            Section {
                DisclosureGroup("Use a different shortcut name", isExpanded: $showName) {
                    TextField("Shortcut name", text: $shortcutName)
                        .autocorrectionDisabled()
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { onFinish(nil) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onFinish(shortcutName.trimmingCharacters(in: .whitespaces)) }
                    .fontWeight(.semibold)
                    .disabled(shortcutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
