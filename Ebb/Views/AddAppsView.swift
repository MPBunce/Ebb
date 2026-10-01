//
//  AddAppsView.swift
//  Ebb
//
//  Pick apps from the catalog, or add anything else with a URL scheme, Shortcut, or website.
//

import SwiftUI

struct AddAppsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingCustom = false

    var body: some View {
        NavigationStack {
            CatalogPicker()
                .navigationTitle("Add apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Custom") { isAddingCustom = true }
                    }
                }
                .sheet(isPresented: $isAddingCustom) {
                    NavigationStack { TargetEditor(target: nil) }
                }
        }
    }
}

/// Tap-to-toggle list of known apps. Used by Add Apps and onboarding.
struct CatalogPicker: View {
    @Environment(LauncherStore.self) private var store
    @State private var query = ""
    @State private var showFull = false
    @State private var isAddingCustom = false
    var addsToHome = false
    /// When set, tapping an app puts it on (or takes it off) this app widget.
    var widgetID: UUID?

    private var widget: AppWidgetList? { widgetID.flatMap { id in store.lists.first { $0.id == id } } }

    private func isChecked(_ app: CatalogApp) -> Bool {
        guard let target = store.targets.first(where: { $0.name == app.name }) else { return false }
        if let widget { return widget.appIDs.contains(target.id) }
        return true
    }

    @State private var installed: [CatalogApp] = []

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


    var body: some View {
        List {
            Section {
                Button {
                    isAddingCustom = true
                } label: {
                    Label("Add an app that isn't listed", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            } footer: {
                Text("iPhone doesn't let Ebb see which apps you have, so pick from this list. For anything else, add it with a Shortcut (works for every app) or the app's link.")
            }
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
        }
        .searchable(text: $query, prompt: "Search apps")
        .onAppear { installed = InstalledApps.detect() }
        .alert("This widget is full", isPresented: $showFull) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("An app widget holds \(AppWidgetList.capacity) apps. Remove one, or add this app to another app widget.")
        }
        .sheet(isPresented: $isAddingCustom) {
            NavigationStack { TargetEditor(target: nil, widgetID: widgetID) }
        }
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
                            isMindful: isMindful, isHidden: isHidden)
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
