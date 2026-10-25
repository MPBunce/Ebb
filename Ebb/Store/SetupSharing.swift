//
//  SetupSharing.swift
//  Ebb
//
//  Share your Ebb setup with another iPhone: apps and how they open, widget layout,
//  mindful pauses, and colors, in a small .ebbsetup file sent by AirDrop or Messages.
//  Opening it in Ebb asks before changing anything. Nothing about usage is included.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ebbSetup = UTType(exportedAs: "mpbunce.Ebb.setup", conformingTo: .json)
}

struct EbbSetup: Codable, Identifiable {
    struct App: Codable {
        var id: UUID
        var name: String
        var method: LaunchTarget.Method
        var isMindful: Bool
        var isHidden: Bool
        var bundleID: String?
    }

    struct Widget: Codable {
        var name: String
        var appIDs: [UUID]
    }

    var id = UUID()
    var version = 1
    var sharedBy: String?
    var apps: [App]
    var widgets: [Widget]
    /// Colors, typeface, alignment, and text size, by App Group key.
    var style: [String: String]

    static let styleKeys = [AppGroup.Key.backgroundHex, AppGroup.Key.textHex, AppGroup.Key.typeface,
                            AppGroup.Key.listAlignment, AppGroup.Key.listTextSize]

    @MainActor
    static func current(from store: LauncherStore) -> EbbSetup {
        var style: [String: String] = [:]
        for key in styleKeys {
            if let value = AppGroup.defaults.string(forKey: key) { style[key] = value }
        }
        return EbbSetup(
            sharedBy: UIDevice.current.name,
            apps: store.targets.map { App(id: $0.id, name: $0.name, method: $0.method, isMindful: $0.isMindful,
                                           isHidden: $0.isHidden, bundleID: $0.bundleID) },
            widgets: store.lists.map { Widget(name: $0.name, appIDs: $0.appIDs) },
            style: style
        )
    }

    /// Writes the setup to a file ready to share.
    func fileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Ebb Setup.ebbsetup")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        return url
    }

    static func read(from url: URL) -> EbbSetup? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        var setup = try? JSONDecoder().decode(EbbSetup.self, from: data)
        setup?.id = UUID()
        return setup
    }

    /// Apps that open with a Shortcut, which has to exist on this iPhone too.
    var shortcutApps: [String] {
        apps.compactMap { if case .shortcut = $0.method { return $0.name } else { return nil } }
    }
}

extension LauncherStore {
    /// Adds the setup's apps (matching ones already here) and, if asked, uses its widget
    /// layout. Returns how many apps were new.
    @discardableResult
    func apply(_ setup: EbbSetup, layout: Bool) -> Int {
        let before = targets.count
        var local: [UUID: UUID] = [:]
        for app in setup.apps {
            let target = add(LaunchTarget(name: app.name, method: app.method, isMindful: app.isMindful,
                                          isHidden: app.isHidden, bundleID: app.bundleID))
            local[app.id] = target.id
        }
        if layout {
            replaceLists(setup.widgets.map { widget in
                AppWidgetList(name: widget.name, appIDs: Array(widget.appIDs.compactMap { local[$0] }.prefix(AppWidgetList.capacity)))
            })
        } else {
            for app in setup.apps { if let id = local[app.id] { addToFirstOpenList(id) } }
        }
        return targets.count - before
    }
}

extension EbbSetup {
    /// Applies the colors and type, and refreshes the widgets.
    func applyStyle() {
        for (key, value) in style where Self.styleKeys.contains(key) {
            AppGroup.defaults.set(value, forKey: key)
        }
    }
}

/// Asks before applying a setup someone shared.
struct SetupImportView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let setup: EbbSetup

    @State private var useLayout = true
    @State private var useStyle = true
    @State private var result: Int?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(setup.sharedBy.map { "From \($0)" } ?? "A shared Ebb setup")
                            .font(.headline)
                        Text("\(setup.apps.count) apps · \(setup.widgets.count) widget\(setup.widgets.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(setup.widgets.indices, id: \.self) { index in
                        let widget = setup.widgets[index]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(widget.name)
                            Text(widget.appIDs.compactMap { id in setup.apps.first { $0.id == id }?.name }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Widgets")
                }

                Section {
                    Toggle("Use their widget layout", isOn: $useLayout)
                    if !setup.style.isEmpty {
                        Toggle("Use their colors and type", isOn: $useStyle)
                    }
                } footer: {
                    Text(useLayout ? "Your widgets are replaced with theirs. Your apps stay in Ebb."
                                   : "Their apps are added to your widgets where there's room.")
                }

                if !setup.shortcutApps.isEmpty {
                    Section {
                        Text(setup.shortcutApps.joined(separator: ", "))
                    } header: {
                        Text("Open with a Shortcut")
                    } footer: {
                        Text("These need their “Open App” Shortcut on this iPhone too. Edit one in Apps to set it up.")
                    }
                }
            }
            .navigationTitle("Import setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        store.apply(setup, layout: useLayout)
                        if useStyle { setup.applyStyle() }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

/// Settings rows for sending your setup to another iPhone, or bringing one in.
struct SetupShareRows: View {
    @Environment(LauncherStore.self) private var store
    @Environment(Router.self) private var router
    @State private var fileURL: URL?
    @State private var isImporting = false
    @State private var importFailed = false

    var body: some View {
        Group {
            if let fileURL {
                ShareLink(item: fileURL, preview: SharePreview("Ebb Setup")) {
                    SettingsRow(icon: "square.and.arrow.up", tint: .teal, title: "Share my setup",
                                subtitle: "Send your apps and widgets to another iPhone")
                }
            }
            Button { isImporting = true } label: {
                SettingsRow(icon: "square.and.arrow.down", tint: .teal, title: "Import a setup",
                            subtitle: "Open an Ebb Setup file someone sent you", showsChevron: true)
            }
        }
        .task(id: store.targets.count + store.lists.count) {
            fileURL = try? EbbSetup.current(from: store).fileURL()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.ebbSetup, .json]) { result in
            guard case .success(let url) = result, let setup = EbbSetup.read(from: url) else {
                importFailed = true
                return
            }
            router.importedSetup = setup
        }
        .alert("Couldn't read that file", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose an Ebb Setup file shared from Ebb on another iPhone.")
        }
    }
}
