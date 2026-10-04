//
//  RoutinesView.swift
//  Ebb
//
//  Ebb Plus habits and to-dos: add and edit them here, check them off here or on the
//  Home Screen widgets. Checked to-dos clear at midnight.
//

import SwiftUI
import WidgetKit

private func reloadRoutineWidgets() {
    WidgetCenter.shared.reloadTimelines(ofKind: "EbbHabits")
    WidgetCenter.shared.reloadTimelines(ofKind: "EbbTodo")
}

/// Shown instead of habits or to-dos for free users.
private struct RoutinesLocked: View {
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "lock")
        } description: {
            Text(detail)
        } actions: {
            NavigationLink("About Ebb Plus") { EbbPlusView() }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
        }
    }
}

// MARK: - Habits

struct HabitsView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var habits = HabitStore.load()
    @State private var newName = ""
    @State private var editing: Habit?

    var body: some View {
        Group {
            if store.isPlus {
                list
            } else {
                RoutinesLocked(title: "Habits",
                               detail: "Track daily habits and check them off right on your Home Screen with Ebb Plus.")
            }
        }
        .navigationTitle("Habits")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            // Habits may have been checked off on the widget.
            if phase == .active { habits = HabitStore.load() }
        }
    }

    private var list: some View {
        List {
            Section {
                HStack {
                    TextField("New habit, like Read 10 pages", text: $newName)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !habits.isEmpty {
                Section {
                    ForEach(habits) { habit in
                        HabitRow(habit: habit) {
                            toggle(habit)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { delete(habit) }
                            Button("Rename") { editing = habit }
                                .tint(.indigo)
                        }
                    }
                    .onMove { from, to in
                        habits.move(fromOffsets: from, toOffset: to)
                        save()
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text("Tap a habit to mark it done today. Dots show the last week; the number is your streak. Add the Habits widget to check them off from your Home Screen.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if !habits.isEmpty { EditButton() }
        }
        .overlay {
            if habits.isEmpty {
                ContentUnavailableView("No habits yet",
                                       systemImage: "checklist",
                                       description: Text("Add a habit above, like a walk, reading, or no phone before bed."))
                    .allowsHitTesting(false)
                    .padding(.top, 120)
            }
        }
        .alert("Rename habit", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Name", text: Binding(get: { editing?.name ?? "" }, set: { editing?.name = $0 }))
            Button("Save") {
                if let editing, let index = habits.firstIndex(where: { $0.id == editing.id }),
                   !editing.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    habits[index].name = editing.name.trimmingCharacters(in: .whitespaces)
                    save()
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        habits.append(Habit(name: name))
        newName = ""
        save()
    }

    private func toggle(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].toggle(on: .now)
        save()
    }

    private func delete(_ habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        save()
    }

    private func save() {
        HabitStore.save(habits)
        reloadRoutineWidgets()
    }
}

private struct HabitRow: View {
    let habit: Habit
    let onToggle: () -> Void

    var body: some View {
        let done = habit.isDone(on: .now)
        let streak = habit.streak(asOf: .now)
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.indigo : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        ForEach(DayKey.days(endingOn: .now, count: 7), id: \.self) { day in
                            Circle()
                                .fill(habit.isDone(on: day) ? Color.indigo : Color.secondary.opacity(0.2))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Spacer()
                if streak > 0 {
                    Text("\(streak) day\(streak == 1 ? "" : "s")")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(done ? "Done today" : "Not done today")
    }
}

// MARK: - To-dos

struct TodoListView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Router.self) private var router
    @FocusState private var isAdding: Bool

    @State private var items = TodoStore.load()
    @State private var newTitle = ""

    private var open: [TodoItem] { items.filter { !$0.isDone } }
    private var done: [TodoItem] { items.filter(\.isDone) }

    var body: some View {
        Group {
            if store.isPlus {
                list
            } else {
                RoutinesLocked(title: "To-Do",
                               detail: "Keep a simple to-do list on your Home Screen that clears what you've finished every night, with Ebb Plus.")
            }
        }
        .onAppear(perform: focusIfAsked)
        .onChange(of: router.focusNewTodo) { focusIfAsked() }
        .navigationTitle("To-Do")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            // Items may have been checked off on the widget, or cleared overnight.
            if phase == .active { items = TodoStore.load() }
        }
    }

    private var list: some View {
        List {
            Section {
                HStack {
                    TextField("Add a to-do", text: $newTitle)
                        .focused($isAdding)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !open.isEmpty {
                Section("To do") {
                    ForEach(open) { item in
                        row(item)
                    }
                    .onMove { from, to in
                        var reordered = open
                        reordered.move(fromOffsets: from, toOffset: to)
                        items = reordered + done
                        save()
                    }
                }
            }

            if !done.isEmpty {
                Section {
                    ForEach(done) { item in
                        row(item)
                    }
                } header: {
                    Text("Done today")
                } footer: {
                    Text("Finished items clear at midnight.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if !open.isEmpty { EditButton() }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing to do",
                                       systemImage: "checkmark.circle",
                                       description: Text("Add a to-do above. Check things off here or on the To-Do widget; finished items clear at midnight."))
                    .allowsHitTesting(false)
                    .padding(.top, 120)
            }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        Button {
            toggle(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? Color.indigo : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(item.title)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { delete(item) }
        }
        .accessibilityValue(item.isDone ? "Done" : "To do")
    }

    /// The To-Do widget's + opens this page ready to type.
    private func focusIfAsked() {
        guard router.focusNewTodo else { return }
        router.focusNewTodo = false
        Task {
            // Wait for the page to finish appearing, or the keyboard won't show.
            try? await Task.sleep(for: .milliseconds(450))
            isAdding = true
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        items = open + [TodoItem(title: title)] + done
        newTitle = ""
        save()
    }

    private func toggle(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].completedAt = items[index].isDone ? nil : .now
        save()
    }

    private func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    private func save() {
        TodoStore.save(items)
        reloadRoutineWidgets()
    }
}
