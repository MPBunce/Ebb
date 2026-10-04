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
        .onAppear { habits = HabitStore.load() }
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
        NavigationLink {
            HabitDetailView(habitID: habit.id)
        } label: {
            HStack(spacing: 12) {
                // Its own button, so tapping the circle checks it off instead of opening history.
                Button(action: onToggle) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(done ? Color.indigo : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(done ? "Mark not done" : "Mark done today")
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
        }
        .accessibilityValue(done ? "Done today" : "Not done today")
    }
}

// MARK: - Habit history

/// One habit's history: streaks, totals, and a heat map of the last six months.
/// Tap any day on the map to fill in a day you missed logging.
struct HabitDetailView: View {
    let habitID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var habit: Habit?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let habit {
                content(habit)
            } else {
                ContentUnavailableView("Habit not found", systemImage: "checklist")
            }
        }
        .navigationTitle(habit?.name ?? "Habit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { habit = HabitStore.load().first { $0.id == habitID } }
    }

    private func content(_ habit: Habit) -> some View {
        let done = habit.isDone(on: .now)
        return List {
            Section {
                Button {
                    toggle(.now)
                } label: {
                    Label(done ? "Done today" : "Mark done today",
                          systemImage: done ? "checkmark.circle.fill" : "circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(done ? .green : .indigo)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                HStack(spacing: 0) {
                    stat("\(habit.streak(asOf: .now))", "current streak")
                    stat("\(habit.longestStreak())", "best streak")
                    stat("\(habit.doneCount(lastDays: 30, endingOn: .now))/30", "last 30 days")
                }
                .padding(.vertical, 6)
            }

            Section {
                HabitHeatMap(habit: habit) { day in toggle(day) }
                    .padding(.vertical, 8)
            } header: {
                Text("Last 6 months")
            } footer: {
                Text("Each square is a day. Tap one to mark it done or not, if you forgot to check it off. \(habit.completions.count) day\(habit.completions.count == 1 ? "" : "s") done in total.")
            }

            Section {
                Button("Rename") {
                    newName = habit.name
                    isRenaming = true
                }
                Button("Delete habit", role: .destructive) { confirmDelete = true }
            }
        }
        .alert("Rename habit", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(habit.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete habit and its history", role: .destructive) { delete() }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.light))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func update(_ change: (inout Habit) -> Void) {
        var habits = HabitStore.load()
        guard let index = habits.firstIndex(where: { $0.id == habitID }) else { return }
        change(&habits[index])
        HabitStore.save(habits)
        habit = habits[index]
        reloadRoutineWidgets()
    }

    private func toggle(_ day: Date) {
        update { $0.toggle(on: day) }
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        update { $0.name = name }
    }

    private func delete() {
        HabitStore.save(HabitStore.load().filter { $0.id != habitID })
        reloadRoutineWidgets()
        dismiss()
    }
}

/// A GitHub-style grid: one column per week, one row per weekday, filled on days it was done.
private struct HabitHeatMap: View {
    let habit: Habit
    let onTap: (Date) -> Void

    private let weeks = 26
    private let gap: CGFloat = 3
    @State private var width: CGFloat = 320

    private var cell: CGFloat { max((width - 24 - gap * CGFloat(weeks - 1)) / CGFloat(weeks), 4) }
    private var calendar: Calendar { .current }

    /// The first day of the week, `weeks - 1` weeks before this one.
    private var start: Date {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
    }

    private func day(week: Int, weekday: Int) -> Date {
        calendar.date(byAdding: .day, value: week * 7 + weekday, to: start) ?? start
    }

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        VStack(alignment: .leading, spacing: 4) {
            monthLabels(cell: cell)
            HStack(alignment: .top, spacing: gap) {
                weekdayLabels(cell: cell)
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let date = day(week: week, weekday: weekday)
                            if date > today {
                                Color.clear.frame(width: cell, height: cell)
                            } else {
                                let done = habit.isDone(on: date)
                                RoundedRectangle(cornerRadius: cell * 0.25)
                                    .fill(done ? Color.indigo : Color.secondary.opacity(0.15))
                                    .overlay {
                                        if calendar.isDate(date, inSameDayAs: today) {
                                            RoundedRectangle(cornerRadius: cell * 0.25)
                                                .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                                        }
                                    }
                                    .frame(width: cell, height: cell)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onTap(date) }
                                    .accessibilityElement()
                                    .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted))
                                    .accessibilityValue(done ? "Done" : "Not done")
                                    .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func monthLabels(cell: CGFloat) -> some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: 24 - gap, height: 12)
            ForEach(0..<weeks, id: \.self) { week in
                let first = day(week: week, weekday: 0)
                let previous = day(week: max(week - 1, 0), weekday: 0)
                let isNewMonth = week == 0 || calendar.component(.month, from: first) != calendar.component(.month, from: previous)
                Text(isNewMonth ? first.formatted(.dateTime.month(.abbreviated)) : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: cell, height: 12, alignment: .leading)
            }
        }
    }

    private func weekdayLabels(cell: CGFloat) -> some View {
        let symbols = calendar.veryShortWeekdaySymbols
        return VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                let weekday = (calendar.firstWeekday - 1 + row) % 7
                Text(row % 2 == 1 ? symbols[weekday] : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 24 - gap, height: cell, alignment: .leading)
            }
        }
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
