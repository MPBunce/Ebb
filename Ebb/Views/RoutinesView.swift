//
//  RoutinesView.swift
//  Ebb
//
//  Ebb Plus habits and to-dos: add and edit them here, check them off here or on the
//  Home Screen widgets. Checked to-dos clear at midnight.
//

import SwiftUI
import WidgetKit

func reloadRoutineWidgets() {
    WidgetCenter.shared.reloadTimelines(ofKind: "EbbHabits")
    WidgetCenter.shared.reloadTimelines(ofKind: "EbbTodo")
}

/// Shown instead of habits or to-dos for free users: a look at the real thing, then the lock.
private struct RoutinesLocked<Preview: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let preview: Preview

    var body: some View {
        VStack(spacing: 24) {
            preview
                .allowsHitTesting(false)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
                .overlay(alignment: .topTrailing) {
                    Text("Preview")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                        .padding(10)
                }
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Label(title, systemImage: "lock")
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            NavigationLink("Unlock with Ebb Plus") { EbbPlusView() }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            Spacer()
        }
        .padding(.top, 32)
    }
}

/// Sample rows for the locked preview.
private struct SampleRow: View {
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.indigo : Color.secondary)
            Text(title).strikethrough(done && detail.isEmpty)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Habits

struct HabitsView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    /// Every habit, archived ones too, so saving never drops any.
    @State private var all = HabitStore.loadAll()
    @State private var newName = ""
    @State private var editing: Habit?
    @State private var showArchived = false

    private var active: [Habit] { all.filter { !$0.isArchived } }
    private var archived: [Habit] { all.filter(\.isArchived) }
    private var dueToday: [Habit] { active.filter { $0.schedule.isScheduled(.now) } }
    private var restDay: [Habit] { active.filter { !$0.schedule.isScheduled(.now) } }
    private var unusedAuto: [HabitAuto] {
        HabitAuto.allCases.filter { kind in !all.contains { $0.auto == kind } }
    }

    var body: some View {
        Group {
            if store.isPlus {
                list
            } else {
                RoutinesLocked(title: "Habits",
                               detail: "Track habits on your schedule, with streaks, reminders, and ones Ebb ticks off for you.") {
                    VStack(spacing: 14) {
                        SampleRow(title: "Walk 30 min", detail: "12 days", done: true)
                        SampleRow(title: "Drink water", detail: "5 / 8", done: false)
                        SampleRow(title: "Finish a focus session", detail: "Automatic", done: true)
                    }
                }
            }
        }
        .navigationTitle("Habits")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: scenePhase) { _, phase in
            // Habits may have been checked off on the widget.
            if phase == .active { reload() }
        }
        .sheet(item: $editing) { habit in
            HabitEditor(habit: habit) { saved in
                if let index = all.firstIndex(where: { $0.id == saved.id }) { all[index] = saved } else { all.append(saved) }
                save()
            }
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
            } footer: {
                Text("Tap a habit's name for its history and options.")
            }

            if !dueToday.isEmpty {
                Section("Today") {
                    ForEach(dueToday) { habit in row(habit) }
                        .onMove { move($0, $1, within: dueToday) }
                }
            }

            if !restDay.isEmpty {
                Section("Not today") {
                    ForEach(restDay) { habit in row(habit) }
                        .onMove { move($0, $1, within: restDay) }
                }
            }

            if active.count < 3, !unusedStarters.isEmpty {
                Section {
                    ForEach(unusedStarters.prefix(4)) { starter in
                        Button {
                            addStarter(starter)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(starter.name).foregroundStyle(.primary)
                                    Text("After \(starter.cue) · start with: \(starter.tiny.lowercased())")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                } header: {
                    Text("Small starts")
                } footer: {
                    Text("Tiny habits tied to something you already do are the ones that stick.")
                }
            }

            if !unusedAuto.isEmpty {
                Section {
                    ForEach(unusedAuto) { kind in
                        Button {
                            addAuto(kind)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.defaultName).foregroundStyle(.primary)
                                    Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                } header: {
                    Text("Automatic habits")
                } footer: {
                    Text("Ebb ticks these off from what it sees, so there's nothing to check.")
                }
            }

            if !archived.isEmpty {
                Section {
                    DisclosureGroup("Archived (\(archived.count))", isExpanded: $showArchived) {
                        ForEach(archived) { habit in
                            HStack {
                                Text(habit.name).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(habit.completions.count) days").font(.caption).foregroundStyle(.tertiary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { delete(habit) }
                                Button("Restore") { setArchived(habit, false) }.tint(.indigo)
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if active.count > 1 { EditButton() }
        }
        .overlay {
            if active.isEmpty {
                ContentUnavailableView("No habits yet",
                                       systemImage: "checklist",
                                       description: Text("Add one above, or pick an automatic one below."))
                    .allowsHitTesting(false)
                    .padding(.top, 60)
            }
        }
    }

    private func row(_ habit: Habit) -> some View {
        HabitRow(habit: habit, onToggle: { toggle(habit) })
            .swipeActions(edge: .trailing) {
                Button("Archive") { setArchived(habit, true) }.tint(.gray)
                Button("Edit") { editing = habit }.tint(.indigo)
            }
    }

    private func reload() {
        all = HabitStore.loadAll()
        HabitReminders.schedule(all)
    }

    /// Opens the editor so the new habit can be made small and tied to a cue.
    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        editing = Habit(name: name, createdAt: .now, allowsSkip: true)
        newName = ""
    }

    private func addStarter(_ starter: HabitStarters.Starter) {
        editing = Habit(name: starter.name, createdAt: .now, allowsSkip: true, cue: starter.cue, tinyVersion: starter.tiny)
    }

    private var unusedStarters: [HabitStarters.Starter] {
        HabitStarters.all.filter { starter in !all.contains { $0.name == starter.name } }
    }

    private func addAuto(_ kind: HabitAuto) {
        var habit = Habit(name: kind.defaultName, createdAt: .now, allowsSkip: true, auto: kind)
        habit.syncAuto()
        all.append(habit)
        save()
    }

    private func toggle(_ habit: Habit) {
        guard habit.auto == nil, let index = all.firstIndex(where: { $0.id == habit.id }) else { return }
        all[index].toggle(on: .now)
        save()
    }

    /// Reorders within one section, keeping everything else where it is.
    private func move(_ from: IndexSet, _ to: Int, within section: [Habit]) {
        var reordered = section
        reordered.move(fromOffsets: from, toOffset: to)
        let ids = Set(section.map(\.id))
        var queue = reordered[...]
        all = all.map { ids.contains($0.id) ? queue.popFirst()! : $0 }
        save()
    }

    private func setArchived(_ habit: Habit, _ archived: Bool) {
        guard let index = all.firstIndex(where: { $0.id == habit.id }) else { return }
        all[index].isArchived = archived
        save()
    }

    private func delete(_ habit: Habit) {
        all.removeAll { $0.id == habit.id }
        save()
    }

    private func save() {
        HabitStore.save(all)
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
                    HabitCheck(habit: habit, day: .now)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(habit.auto != nil)
                .accessibilityLabel(habit.auto != nil ? "Automatic" : habit.isCounted ? "Add one" : done ? "Mark not done" : "Mark done today")
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            ForEach(DayKey.days(endingOn: .now, count: 7), id: \.self) { day in
                                let scheduled = habit.schedule.isScheduled(day)
                                Circle()
                                    .fill(habit.isDone(on: day) ? Color.indigo : Color.secondary.opacity(scheduled ? 0.25 : 0.08))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .accessibilityHidden(true)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if streak > 0 {
                    Label(habit.streakText(), systemImage: "flame")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityValue(done ? "Done today" : "Not done today")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let cue = habit.cueText { parts.append(cue) }
        if habit.auto != nil { parts.append("Automatic") }
        if habit.isCounted { parts.append("\(habit.count(on: .now)) of \(habit.target)") }
        if case .weekly(let times) = habit.schedule { parts.append("\(habit.doneThisWeek(.now)) of \(times) this week") }
        else if habit.schedule != .daily { parts.append(habit.schedule.label) }
        return parts.joined(separator: " · ")
    }
}

/// The tick for a habit: a circle, a filling ring for counted ones, a sparkle for automatic ones.
private struct HabitCheck: View {
    let habit: Habit
    let day: Date

    var body: some View {
        let done = habit.isDone(on: day)
        if habit.isCounted && !done {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(habit.count(on: day)) / CGFloat(habit.target))
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.indigo)
            }
            .frame(width: 24, height: 24)
        } else {
            Image(systemName: done ? "checkmark.circle.fill" : habit.auto != nil ? "sparkles" : "circle")
                .font(.title2)
                .foregroundStyle(done ? Color.indigo : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

// MARK: - Habit editor

/// Name, schedule, count, skips, and reminder for one habit.
struct HabitEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    let onSave: (Habit) -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case daily = "Every day", days = "Some days", weekly = "Times a week"
        var id: Self { self }
    }

    @State private var kind: Kind = .daily
    @State private var days: Set<Int> = [2, 3, 4, 5, 6]
    @State private var timesPerWeek = 3
    @State private var hasReminder = false
    @State private var reminder = Calendar.current.date(from: DateComponents(hour: 20)) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Habit", text: $habit.name)
                }

                if habit.auto == nil {
                    Section {
                        LabeledContent("After") {
                            TextField("I pour my morning coffee", text: Binding(
                                get: { habit.cue ?? "" }, set: { habit.cue = $0.isEmpty ? nil : $0 }))
                        }
                        LabeledContent("At least") {
                            TextField("read one page", text: Binding(
                                get: { habit.tinyVersion ?? "" }, set: { habit.tinyVersion = $0.isEmpty ? nil : $0 }))
                        }
                    } header: {
                        Text("Make it small")
                    } footer: {
                        Text("Tie it to something you already do, and pick a two-minute version for hard days. It still counts.")
                    }
                }

                Section {
                    Picker("Repeat", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch kind {
                    case .daily:
                        EmptyView()
                    case .days:
                        WeekdayPicker(selection: $days)
                    case .weekly:
                        Stepper("\(timesPerWeek)× a week", value: $timesPerWeek, in: 1...6)
                    }
                    if kind != .weekly {
                        Toggle("Never miss twice", isOn: $habit.allowsSkip)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(kind == .weekly ? "Any days count. The streak is weeks in a row you hit it."
                                         : habit.allowsSkip ? "One miss a week won't break your streak. Two in a row will."
                                                            : "Days off never break a streak.")
                }

                if habit.auto == nil {
                    Section {
                        Stepper(habit.target == 1 ? "Just a tick" : "\(habit.target) times a day",
                                value: $habit.target, in: 1...50)
                    } header: {
                        Text("Count")
                    } footer: {
                        Text("More than one counts up, like 8 glasses of water.")
                    }
                } else if let auto = habit.auto {
                    Section("Automatic") {
                        Text(auto.detail).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Remind me", isOn: $hasReminder)
                    if hasReminder {
                        DatePicker("Time", selection: $reminder, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Only on days it isn't done yet.")
                }
            }
            .navigationTitle(habit.name.isEmpty ? "Habit" : habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(habit.name.trimmingCharacters(in: .whitespaces).isEmpty || (kind == .days && days.isEmpty))
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        switch habit.schedule {
        case .daily: kind = .daily
        case .days(let set): kind = .days; days = set
        case .weekly(let n): kind = .weekly; timesPerWeek = n
        }
        if let minutes = habit.reminderMinutes {
            hasReminder = true
            reminder = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? reminder
        }
    }

    private func save() {
        habit.name = habit.name.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .daily: habit.schedule = .daily
        case .days: habit.schedule = days.count == 7 ? .daily : .days(days)
        case .weekly: habit.schedule = .weekly(timesPerWeek)
        }
        if hasReminder {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: reminder)
            habit.reminderMinutes = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
            Task { _ = await HabitReminders.requestPermission() }
        } else {
            habit.reminderMinutes = nil
        }
        onSave(habit)
        dismiss()
    }
}

/// Seven round buttons, Monday first.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(on ? Color.indigo : Color.secondary.opacity(0.15)))
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
                if day != 1 { Spacer(minLength: 0) }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Habit history

/// One habit's history: streaks, this month, the day you miss most, and a heat map of the
/// last six months. Tap any day on the map to fill in a day you missed logging.
struct HabitDetailView: View {
    let habitID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var habit: Habit?
    @State private var isEditing = false
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
        .toolbar {
            if habit != nil { Button("Edit") { isEditing = true } }
        }
        .onAppear { habit = HabitStore.loadAll().first { $0.id == habitID } }
        .sheet(isPresented: $isEditing) {
            if let habit {
                HabitEditor(habit: habit) { saved in update { $0 = saved } }
            }
        }
    }

    private func content(_ habit: Habit) -> some View {
        let done = habit.isDone(on: .now)
        return List {
            Section {
                if habit.auto != nil {
                    Label(done ? "Done today" : "Ebb ticks this off for you",
                          systemImage: done ? "checkmark.circle.fill" : "sparkles")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(done ? .green : .secondary)
                } else if habit.isCounted {
                    HStack {
                        Button { update { $0.decrement(on: .now) } } label: {
                            Image(systemName: "minus").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.circle)
                        .disabled(habit.count(on: .now) == 0)
                        Spacer()
                        VStack(spacing: 0) {
                            Text("\(habit.count(on: .now)) of \(habit.target)")
                                .font(.title.weight(.light)).monospacedDigit()
                            Text(done ? "Done today" : "today").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { update { $0.toggle(on: .now) } } label: {
                            Image(systemName: done ? "arrow.counterclockwise" : "plus").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.indigo)
                    }
                } else {
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
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                HStack(spacing: 0) {
                    stat(habit.streakText(), "current streak")
                    stat(habit.schedule.isWeekly ? "\(habit.longestStreak())w" : "\(habit.longestStreak())d", "best streak")
                    stat(habit.monthRate().map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–", "this month")
                }
                .padding(.vertical, 6)
                if habit.cueText != nil || habit.tinyVersion != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text([habit.cueText.map { "\($0), I will \(habit.name.lowercased())." }, habit.tinyVersion.map { "At least: \($0)." }]
                            .compactMap { $0 }.joined(separator: "\n"))
                    }
                    .font(.subheadline)
                }
                LabeledContent("Schedule", value: habit.schedule.label)
                if let weekday = habit.mostMissedWeekday() {
                    LabeledContent("Missed most", value: Calendar.current.weekdaySymbols[weekday - 1] + "s")
                }
                if let minutes = habit.reminderMinutes,
                   let time = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) {
                    LabeledContent("Reminder", value: time.formatted(date: .omitted, time: .shortened))
                }
            }

            Section {
                HabitHeatMap(habit: habit) { day in if habit.auto == nil { toggle(day) } }
                    .padding(.vertical, 8)
            } header: {
                Text("Last 6 months")
            } footer: {
                Text(habit.auto == nil ? "Tap a day to fix it. \(habit.completions.count) days done in total."
                                       : "\(habit.completions.count) days done in total.")
            }

            Section {
                Button(habit.isArchived ? "Restore" : "Archive") {
                    update { $0.isArchived.toggle() }
                    if !(self.habit?.isArchived ?? true) { return }
                    dismiss()
                }
                Button("Delete habit", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Archiving hides it and keeps its history.")
            }
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
        var habits = HabitStore.loadAll()
        guard let index = habits.firstIndex(where: { $0.id == habitID }) else { return }
        change(&habits[index])
        HabitStore.save(habits)
        habit = habits[index]
        reloadRoutineWidgets()
    }

    private func toggle(_ day: Date) {
        update { $0.toggle(on: day) }
    }

    private func delete() {
        HabitStore.save(HabitStore.loadAll().filter { $0.id != habitID })
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
                                    .fill(done ? Color.indigo : Color.secondary.opacity(habit.schedule.isScheduled(date) ? 0.15 : 0.05))
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

    private var open: [TodoItem] { items.filter { !$0.isDone && !$0.isSomeday } }
    private var someday: [TodoItem] { items.filter { !$0.isDone && $0.isSomeday } }
    private var done: [TodoItem] { items.filter(\.isDone) }

    var body: some View {
        Group {
            if store.isPlus {
                list
            } else {
                RoutinesLocked(title: "To-Do",
                               detail: "A to-do list on your Home Screen that clears what you've finished every night.") {
                    VStack(spacing: 14) {
                        SampleRow(title: "Call the dentist", detail: "", done: false)
                        SampleRow(title: "Buy groceries", detail: "", done: true)
                        SampleRow(title: "Book flights", detail: "Someday", done: false)
                    }
                }
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
                Section {
                    ForEach(open) { item in
                        row(item)
                    }
                    .onMove { from, to in
                        var reordered = open
                        reordered.move(fromOffsets: from, toOffset: to)
                        items = reordered + someday + done
                        save()
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text("The widget shows these, top first. Drag to reorder in Edit.")
                }
            }

            if !someday.isEmpty {
                Section {
                    ForEach(someday) { item in
                        row(item)
                    }
                    .onMove { from, to in
                        var reordered = someday
                        reordered.move(fromOffsets: from, toOffset: to)
                        items = open + reordered + done
                        save()
                    }
                } header: {
                    Text("Someday")
                } footer: {
                    Text("Kept here, off the widget. Swipe one to move it to Today.")
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
            if open.count + someday.count > 1 { EditButton() }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing to do",
                                       systemImage: "checkmark.circle",
                                       description: Text("Add a to-do above."))
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
            if !item.isDone {
                Button(item.isSomeday ? "Today" : "Someday") { moveToSomeday(item, !item.isSomeday) }
                    .tint(.indigo)
            }
        }
        .accessibilityValue(item.isDone ? "Done" : item.isSomeday ? "Someday" : "To do")
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
        items = open + [TodoItem(title: title)] + someday + done
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

    private func moveToSomeday(_ item: TodoItem, _ someday: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation { items[index].isSomeday = someday }
        save()
    }

    private func save() {
        TodoStore.save(items)
        reloadRoutineWidgets()
    }
}

/// A habit on the main screen: tick it (or count one more) without leaving.
struct DashboardHabitRow: View {
    let habit: Habit
    let onToggle: () -> Void

    var body: some View {
        let done = habit.isDone(on: .now)
        HStack(spacing: 12) {
            Button(action: onToggle) {
                HabitCheck(habit: habit, day: .now)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(habit.auto != nil)
            .accessibilityLabel(habit.auto != nil ? "Automatic" : habit.isCounted ? "Add one" : done ? "Mark not done" : "Mark done")
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .foregroundStyle(done ? .secondary : .primary)
                if let line = detail {
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 3) {
                ForEach(DayKey.days(endingOn: .now, count: 6), id: \.self) { day in
                    Circle()
                        .fill(habit.isDone(on: day) ? Color.indigo : Color.secondary.opacity(habit.schedule.isScheduled(day) ? 0.25 : 0.08))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            let streak = habit.streak(asOf: .now)
            if streak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill").font(.caption2)
                    Text(habit.streakText(short: true))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
                .accessibilityLabel("\(habit.streakText()) streak")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The count so far, or the tiny version as a nudge while it isn't done.
    private var detail: String? {
        if habit.isCounted && !habit.isDone(on: .now) { return "\(habit.count(on: .now)) of \(habit.target)" }
        if !habit.isDone(on: .now), let tiny = habit.tinyVersion, !tiny.isEmpty { return "At least: \(tiny.lowercased())" }
        return habit.cueText
    }
}
