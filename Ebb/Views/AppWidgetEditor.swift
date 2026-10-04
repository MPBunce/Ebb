//
//  AppWidgetEditor.swift
//  Ebb
//
//  Editing one app widget (name and up to six apps), and the Ebb Plus page.
//

import StoreKit
import SwiftUI

struct AppWidgetEditor: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let listID: UUID

    @State private var name = ""
    @State private var confirmDelete = false
    @State private var isAdding = false

    private var list: AppWidgetList? { store.lists.first { $0.id == listID } }

    var body: some View {
        if let list {
            let apps = store.apps(in: list)

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
                        Text("No apps yet.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("On this widget · \(apps.count) of \(AppWidgetList.capacity)")
                } footer: {
                    Text("Tap Edit to reorder. Swipe to remove. Tap Open to check an app opens.")
                }

                Section {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add apps", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(list.isFull)
                } footer: {
                    if list.isFull {
                        Text("This widget is full. Remove an app, or put more apps on another app widget.")
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
            .sheet(isPresented: $isAdding) { AddAppsView(widgetID: listID) }
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

/// What Ebb Plus includes, with buying and restoring it.
struct EbbPlusView: View {
    @Bindable private var plus = PlusStore.shared

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
                    if plus.isActive {
                        Text("Unlocked")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.quaternary))
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            if !plus.isActive {
                Section {
                    Button {
                        Task { await plus.purchase() }
                    } label: {
                        HStack {
                            Text(plus.product.map { "Unlock Ebb Plus for \($0.displayPrice)" } ?? "Unlock Ebb Plus")
                                .fontWeight(.semibold)
                            Spacer()
                            if plus.isPurchasing { ProgressView() }
                        }
                    }
                    .disabled(plus.isPurchasing || plus.isRestoring)

                    Button {
                        Task { await plus.restore() }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            Spacer()
                            if plus.isRestoring { ProgressView() }
                        }
                    }
                    .disabled(plus.isPurchasing || plus.isRestoring)
                } footer: {
                    Text("A one-time purchase, not a subscription. It works on all your devices signed in with the same Apple Account.")
                }
            }

            Section("Included") {
                Label("\(EbbPlus.plusAppWidgets - EbbPlus.freeAppWidgets) more app widgets, \(EbbPlus.plusAppWidgets) in total",
                      systemImage: "square.grid.2x2")
                Label("Time & Life widget: time given back and life left, made for the Today View",
                      systemImage: "hourglass")
                Label("Habits widget: check off daily habits and keep your streaks", systemImage: "checklist")
                Label("To-Do widget: a list that clears finished items every night", systemImage: "checkmark.circle")
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
                Toggle("Preview Plus features", isOn: Binding(
                    get: { plus.isActive },
                    set: { plus.setActive($0) }
                ))
            } header: {
                Text("Developer")
            } footer: {
                Text("Only in development builds. Unlocks Plus without buying it.")
            }
            #endif
        }
        .navigationTitle("Ebb Plus")
        .navigationBarTitleDisplayMode(.inline)
        .task { await plus.loadProduct() }
        .alert("Ebb Plus", isPresented: Binding(
            get: { plus.errorMessage != nil },
            set: { if !$0 { plus.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(plus.errorMessage ?? "")
        }
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
