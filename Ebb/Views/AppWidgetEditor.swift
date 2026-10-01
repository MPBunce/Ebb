//
//  AppWidgetEditor.swift
//  Ebb
//
//  Editing one app widget (name and up to six apps), and the Ebb Plus page.
//

import SwiftUI

struct AppWidgetEditor: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let listID: UUID

    @State private var name = ""
    @State private var confirmDelete = false

    private var list: AppWidgetList? { store.lists.first { $0.id == listID } }

    var body: some View {
        if let list {
            let apps = store.apps(in: list)
            let others = store.library(matching: "").filter { !list.appIDs.contains($0.id) }

            List {
                Section {
                    TextField("Name", text: $name)
                        .onSubmit { store.renameList(listID, to: name) }
                } footer: {
                    Text("This name shows when you choose an app widget in Edit Widget on your Home Screen.")
                }

                Section {
                    ForEach(apps) { app in
                        AppRow(target: app, detail: app.isMindful ? "Mindful pause" : "Opens directly")
                    }
                    .onMove { store.moveApps(in: listID, from: $0, to: $1) }
                    .onDelete { offsets in
                        offsets.map { apps[$0].id }.forEach { store.toggle($0, in: listID) }
                    }
                    if apps.isEmpty {
                        Text("No apps yet. Add some below.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("On this widget · \(apps.count) of \(AppWidgetList.capacity)")
                } footer: {
                    Text("Tap Edit to reorder. Swipe to remove. Tap Open to check an app opens.")
                }

                Section {
                    NavigationLink {
                        CatalogPicker(widgetID: listID)
                            .navigationTitle("Add to \(list.name)")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Add apps", systemImage: "plus.circle.fill")
                    }
                    ForEach(others) { app in
                        Button {
                            store.toggle(app.id, in: listID)
                        } label: {
                            HStack(spacing: 14) {
                                AppMonogram(name: app.name)
                                    .opacity(list.isFull ? 0.5 : 1)
                                Text(app.name)
                                    .foregroundStyle(list.isFull ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(list.isFull ? Color.secondary.opacity(0.4) : Color.accentColor)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(list.isFull)
                    }
                } header: {
                    Text("Add apps")
                } footer: {
                    if list.isFull {
                        Text("This widget is full. Remove an app, or put more apps on another app widget.")
                    } else if !others.isEmpty {
                        Text("Apps you've added to Ebb but not to this widget.")
                    }
                }

                if store.lists.count > 1 {
                    Section {
                        Button("Delete app widget", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(list.name)
            .toolbar {
                if !apps.isEmpty { EditButton() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = list.name }
            .onDisappear { store.renameList(listID, to: name) }
            .confirmationDialog("Delete \(list.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteList(listID)
                    dismiss()
                }
            } message: {
                Text("Any Home Screen widget showing it will switch to your first app widget.")
            }
        } else {
            ContentUnavailableView("App widget deleted", systemImage: "square.dashed")
        }
    }
}

/// What Ebb Plus will include. Purchases come later; development builds can preview it.
struct EbbPlusView: View {
    @State private var isActive = EbbPlus.isActive
    @Environment(LauncherStore.self) private var store

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .light))
                    Text("Ebb Plus")
                        .font(.largeTitle.weight(.light))
                    Text("More room on your Home Screen and more ways to show the time.")
                        .foregroundStyle(.secondary)
                    Text("Coming soon")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary))
                        .padding(.top, 4)
                }
                .padding(.vertical, 8)
            }

            Section("Included") {
                Label("\(EbbPlus.plusAppWidgets - EbbPlus.freeAppWidgets) more app widgets, \(EbbPlus.plusAppWidgets) in total",
                      systemImage: "square.grid.2x2")
                ForEach(ClockStyle.allCases.filter(\.isPlus)) { style in
                    Label("\(style.name) clock: \(style.summary)", systemImage: "clock")
                }
                Label("Everything to come", systemImage: "plus.circle")
            }

            Section("Free forever") {
                Label("\(EbbPlus.freeAppWidgets) app widgets with 6 apps each", systemImage: "checkmark")
                Label("Digital and Analog clocks", systemImage: "checkmark")
                Label("Colors, wallpapers, mindful pause, focus and blocking", systemImage: "checkmark")
            }

            #if DEBUG
            Section {
                Toggle("Preview Plus features", isOn: $isActive)
                    .onChange(of: isActive) { _, newValue in
                        EbbPlus.isActive = newValue
                        store.refreshPlan()
                    }
            } header: {
                Text("Developer")
            } footer: {
                Text("Only in development builds. Unlocks Plus so you can test it before purchases exist.")
            }
            #endif
        }
        .navigationTitle("Ebb Plus")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A small "Plus" tag for locked features.
struct PlusBadge: View {
    var body: some View {
        Text("Plus")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
            .accessibilityLabel("Ebb Plus")
    }
}
