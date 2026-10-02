//
//  AddAppsView.swift
//  Ebb
//
//  Pick apps from the catalog, or add anything else with a URL scheme, Shortcut, or website.
//

import SwiftUI

struct AddAppsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CatalogPicker()
                .navigationTitle("Add apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Tap-to-toggle list of known apps. Used by Add Apps and onboarding.
struct CatalogPicker: View {
    @Environment(LauncherStore.self) private var store
    @State private var query = ""
    @State private var showFull = false
    @State private var storeResults: [AppStoreSearchView.StoreApp] = []
    @State private var isSearchingStore = false
    @State private var needsShortcut: AppStoreSearchView.StoreApp?
    @State private var isAddingManually = false
    @State private var installed: [CatalogApp] = []
    var addsToHome = false
    /// When set, tapping an app puts it on (or takes it off) this app widget.
    var widgetID: UUID?

    private var widget: AppWidgetList? { widgetID.flatMap { id in store.lists.first { $0.id == id } } }

    private func isChecked(_ app: CatalogApp) -> Bool {
        guard let target = store.targets.first(where: { $0.name == app.name }) else { return false }
        if let widget { return widget.appIDs.contains(target.id) }
        return true
    }

    private var grouped: [(String, [CatalogApp])] {
        let apps = query.isEmpty
            ? AppCatalog.apps
            : AppCatalog.apps.filter { $0.name.localizedStandardContains(query) }
        // Third-party apps found on this iPhone come first.
        let found = apps.filter { app in app.category != .essentials && installed.contains(app) }
        let rest = CatalogApp.Category.allCases.compactMap { category -> (String, [CatalogApp])? in
            let matches = apps.filter { $0.category == category && !found.contains($0) }
            return matches.isEmpty ? nil : (category.rawValue, matches)
        }
        return (found.isEmpty ? [] : [("On this iPhone", found)]) + rest
    }

    /// App Store results that aren't already shown from Ebb's own list.
    private var extraStoreResults: [AppStoreSearchView.StoreApp] {
        let known = Set(AppCatalog.bundleIDs.values)
        return storeResults.filter { !known.contains($0.bundleId) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.0) { title, apps in
                Section(title) {
                    ForEach(apps) { app in
                        Button {
                            toggle(app)
                        } label: {
                            HStack(spacing: 14) {
                                AppIconView(name: app.name)
                                Text(app.name)
                                Spacer()
                                Image(systemName: isChecked(app) ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.title3)
                                    .foregroundStyle(isChecked(app) ? Color.accentColor : Color.secondary)
                                    .accessibilityLabel(isChecked(app) ? "Added" : "Add")
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !query.isEmpty {
                Section {
                    if isSearchingStore && extraStoreResults.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                    ForEach(extraStoreResults) { app in
                        StoreAppRow(app: app, query: query) { addFromStore(app) }
                    }
                } header: {
                    Text("More on the App Store")
                } footer: {
                    if !isSearchingStore && extraStoreResults.isEmpty && grouped.isEmpty {
                        Text("No apps found for “\(query)”.")
                    }
                }
            }

            Section {
                Button("Add by link or Shortcut") { isAddingManually = true }
            } footer: {
                Text(query.isEmpty
                     ? "Search to find any app on the App Store. iPhone doesn't let Ebb see which apps you have."
                     : "Can't find it? Add any app with a Shortcut.")
            }
        }
        .searchable(text: $query, prompt: "Search apps")
        .task(id: query) { await searchStore() }
        .onAppear { installed = InstalledApps.detect() }
        .alert("This widget is full", isPresented: $showFull) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("An app widget holds \(AppWidgetList.capacity) apps. Remove one, or add this app to another app widget.")
        }
        .sheet(item: $needsShortcut) { app in
            NavigationStack { ShortcutSetupView(app: app, widgetID: widgetID) {} }
        }
        .sheet(isPresented: $isAddingManually) {
            NavigationStack { TargetEditor(target: nil, widgetID: widgetID) }
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

    private func addFromStore(_ app: AppStoreSearchView.StoreApp) {
        guard let scheme = AppCatalog.scheme(forBundleID: app.bundleId) else {
            needsShortcut = app
            return
        }
        if let widget, widget.isFull {
            showFull = true
            return
        }
        let target = LaunchTarget(name: app.shortName(matching: query), method: .urlScheme(scheme), bundleID: app.bundleId)
        store.add(target)
        if let widgetID { store.toggle(target.id, in: widgetID) } else if addsToHome { store.addToFirstOpenList(target.id) }
        storeResults.removeAll { $0.id == app.id }
    }

    private func toggle(_ app: CatalogApp) {
        if let widget {
            let target = store.targets.first(where: { $0.name == app.name }) ?? {
                let new = app.makeTarget()
                store.add(new)
                return new
            }()
            if !widget.appIDs.contains(target.id) && widget.isFull {
                showFull = true
                return
            }
            store.toggle(target.id, in: widget.id)
            return
        }
        if let existing = store.targets.first(where: { $0.name == app.name }) {
            store.remove(existing)
        } else {
            let target = app.makeTarget()
            store.add(target)
            if addsToHome { store.addToFirstOpenList(target.id) }
        }
    }
}

/// One App Store search result.
struct StoreAppRow: View {
    let app: AppStoreSearchView.StoreApp
    var query = ""
    let action: () -> Void

    var body: some View {
        let known = AppCatalog.scheme(forBundleID: app.bundleId) != nil
        Button(action: action) {
            HStack(spacing: 14) {
                AsyncImage(url: app.artworkUrl100.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.shortName(matching: query)).foregroundStyle(.primary).lineLimit(1)
                    Text(known ? "Adds in one tap" : "Opens with a Shortcut")
                        .font(.caption)
                        .foregroundStyle(known ? Color.green : Color.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let target = makeTarget(id: original?.id ?? UUID())
                    if original == nil {
                        store.add(target)
                        if let widgetID {
                            store.toggle(target.id, in: widgetID)
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

/// Walks through making an "Open App" Shortcut for an app Ebb can't open directly.
struct ShortcutSetupView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let app: AppStoreSearchView.StoreApp
    let widgetID: UUID?
    let onDone: () -> Void

    @State private var shortcutName: String

    init(app: AppStoreSearchView.StoreApp, widgetID: UUID?, onDone: @escaping () -> Void) {
        self.app = app
        self.widgetID = widgetID
        self.onDone = onDone
        _shortcutName = State(initialValue: "Open \(app.shortName)")
    }

    var body: some View {
        Form {
            Section {
                Text("\(app.shortName) doesn't share a launch link, so Ebb opens it with a Shortcut. It takes about 20 seconds, once.")
                    .foregroundStyle(.secondary)
            }
            Section("In the Shortcuts app") {
                StepRow(number: 1, title: "Create a shortcut", detail: "Tap Copy name & open Shortcuts below. A new, empty shortcut opens.")
                StepRow(number: 2, title: "Add “Open App”", detail: "Search actions for Open App and choose \(app.shortName).")
                StepRow(number: 3, title: "Name it", detail: "Rename the shortcut to exactly “\(shortcutName)”, then come back here.")
                Button {
                    UIPasteboard.general.string = shortcutName
                    if let url = URL(string: "shortcuts://create-shortcut") { openURL(url) }
                } label: {
                    Label("Copy name & open Shortcuts", systemImage: "arrow.up.forward.app")
                }
            }
            Section {
                TextField("Shortcut name", text: $shortcutName)
            } header: {
                Text("Shortcut name")
            } footer: {
                Text("Must match the shortcut's name exactly.")
            }
        }
        .navigationTitle(app.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let target = LaunchTarget(name: app.shortName, method: .shortcut(shortcutName), bundleID: app.bundleId)
                    store.add(target)
                    if let widgetID { store.toggle(target.id, in: widgetID) } else { store.addToFirstOpenList(target.id) }
                    dismiss()
                    onDone()
                }
                .disabled(shortcutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
