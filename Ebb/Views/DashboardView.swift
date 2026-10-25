//
//  DashboardView.swift
//  Ebb
//
//  The main screen, about today: the focus that's on, habits and to-dos to tick off right
//  here, and what Ebb has saved. Setting up the Home Screen sits at the bottom and shrinks
//  to two rows once it's done.
//

import SwiftUI
import WidgetKit

struct DashboardView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(FocusManager.self) private var focus
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults) private var backgroundHex: String?
    @AppStorage(AppGroup.Key.wallpaperSet, store: AppGroup.defaults) private var wallpaperSet = false

    @State private var widgetsAdded = false
    @State private var habits = HabitStore.load()
    @State private var todos = TodoStore.load()
    /// Shown when Screen Time access was declined, instead of nothing happening.
    @State private var showingBlockingHelp = false
    /// The focus being created or edited from the main screen.
    @State private var editingFocus: WorkPeriod?
    @State private var path: [DashboardRoute] = []
    /// Where the user was, so Ebb reopens to the same screen even after iOS closes it.
    @SceneStorage("dashboardPath") private var savedPath = ""
    @SceneStorage("dashboardSheet") private var savedSheet = ""

    private var checklist: SetupChecklist {
        SetupChecklist(store: store, focus: focus, backgroundHex: backgroundHex,
                       wallpaperSet: wallpaperSet, widgetsAdded: widgetsAdded)
    }
    private var isSetUp: Bool { checklist.isSetUp }

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store

        NavigationStack(path: $path) {
            List {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))

                focusSection
                habitsSection
                todosSection
                todaySection
                homeScreenSection
            }
            .navigationDestination(for: DashboardRoute.self) { destination(for: $0) }
            .navigationTitle("Ebb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { path.append(.settings) }
                }
            }
        }
        .task { await refreshWidgets() }
        .onAppear {
            restoreState()
            openPendingRoute()
        }
        .onChange(of: router.pendingRoute) { openPendingRoute() }
        .onChange(of: path) { _, newPath in savedPath = newPath.map(\.rawValue).joined(separator: ",") }
        .onChange(of: router.sheet) { _, sheet in savedSheet = sheet?.rawValue ?? "" }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshWidgets() }
                reloadRoutines()
            }
        }
        .onChange(of: path) { _, newPath in
            // Back from Habits or To-Do: show what changed there.
            if newPath.isEmpty { reloadRoutines() }
        }
        .alert("Screen Time is off", isPresented: $showingBlockingHelp) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Ebb needs Screen Time access to block apps. Turn it on in Settings › Screen Time, or tap Turn on blocking again. Apple only gives Ebb anonymous tokens, never your activity.")
        }
        .sheet(item: $router.importedSetup) { setup in
            SetupImportView(setup: setup)
                .ebbColorScheme()
        }
        .sheet(item: $editingFocus) { period in
            NavigationStack {
                FocusEditor(period: period, isNew: !focus.workPeriods.contains { $0.id == period.id })
            }
            .ebbColorScheme()
        }
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                // Settings is a page now; an old saved state opens it there.
                case .settings: Color.clear.onAppear { router.sheet = nil; path = [.settings] }
                case .focus: FocusView()
                case .insights: InsightsView()
                }
            }
            .ebbColorScheme()
        }
        .fullScreenCover(item: $router.breather) { request in
            UnlockBreatherView(token: request.token)
                .ebbColorScheme()
        }
        .fullScreenCover(item: $store.pendingPause) { target in
            MindfulPauseView(target: target)
                .ebbColorScheme()
        }
        .alert(
            "Couldn't open \(store.failedLaunch?.name ?? "app")",
            isPresented: Binding(
                get: { store.failedLaunch != nil },
                set: { if !$0 { store.failedLaunch = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It may not be installed, or its link may have changed. Edit it in Apps and try a Shortcut instead. Shortcuts can open any app.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func destination(for route: DashboardRoute) -> some View {
        switch route {
        case .widgets: WidgetsView()
        case .apps: ManageAppsView()
        case .colors: AppearanceView()
        case .wallpaper: WallpaperStepView()
        case .help: HelpView()
        case .habits: HabitsView()
        case .todos: TodoListView()
        case .settings: SettingsView()
        }
    }

    /// Opens a page a deep link asked for, like the To-Do widget's +.
    private func openPendingRoute() {
        guard let route = router.pendingRoute else { return }
        router.pendingRoute = nil
        path = [route]
    }

    private func restoreState() {
        if path.isEmpty, !savedPath.isEmpty {
            path = savedPath.split(separator: ",").compactMap { DashboardRoute(rawValue: String($0)) }
        }
        if router.sheet == nil, let sheet = HomeSheet(rawValue: savedSheet) {
            router.sheet = sheet
        }
        #if DEBUG
        // Screenshot launch option: `-EbbScreen widgets|apps|add|colors|help|settings|plus`.
        if let screen = UserDefaults.standard.string(forKey: "EbbScreen") {
            if let route = DashboardRoute(rawValue: screen) {
                path = [route]
            } else if screen == "add" {
                path = [.apps]
            } else if screen == "plus" {
                path = [.settings]
            } else if let sheet = HomeSheet(rawValue: screen) {
                router.sheet = sheet
            }
        }
        #endif
    }

    // MARK: Habits & To-Do, ticked off right here

    private var dueHabits: [Habit] { habits.filter { $0.schedule.isScheduled(.now) } }
    private var todayTodos: [TodoItem] { TodoStore.ordered(todos.filter { !$0.isSomeday }) }

    private func reloadRoutines() {
        habits = HabitStore.load()
        todos = TodoStore.load()
    }

    @ViewBuilder
    private var habitsSection: some View {
        Section {
            if !store.isPlus {
                NavigationLink(value: DashboardRoute.habits) {
                    HStack {
                        SettingsRow(icon: "checklist", tint: .green, title: "Habits",
                                    subtitle: "Small habits, tracked on your Home Screen")
                        PlusBadge()
                    }
                }
            } else if dueHabits.isEmpty {
                NavigationLink(value: DashboardRoute.habits) {
                    Text(habits.isEmpty ? "Add a small habit to start" : "A day off from your habits")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(dueHabits.prefix(6)) { habit in
                    DashboardHabitRow(habit: habit) {
                        HabitStore.toggle(id: habit.id)
                        reloadRoutineWidgets()
                        withAnimation { habits = HabitStore.load() }
                    }
                }
            }
        } header: {
            sectionHeader("Habits", route: .habits,
                          detail: store.isPlus && !dueHabits.isEmpty
                              ? "\(dueHabits.filter { $0.isDone(on: .now) }.count) of \(dueHabits.count)" : nil)
        }
    }

    @ViewBuilder
    private var todosSection: some View {
        Section {
            if !store.isPlus {
                NavigationLink(value: DashboardRoute.todos) {
                    HStack {
                        SettingsRow(icon: "checkmark.circle", tint: .orange, title: "To-Do",
                                    subtitle: "A to-do list that clears finished items every night")
                        PlusBadge()
                    }
                }
            } else if todayTodos.isEmpty {
                Button {
                    router.focusNewTodo = true
                    path = [.todos]
                } label: {
                    Text("Nothing to do. Add something")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(todayTodos.prefix(6)) { item in
                    Button {
                        TodoStore.toggle(id: item.id)
                        reloadRoutineWidgets()
                        withAnimation { todos = TodoStore.load() }
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
                    .accessibilityValue(item.isDone ? "Done" : "To do")
                }
                if todayTodos.count > 6 {
                    NavigationLink("\(todayTodos.count - 6) more", value: DashboardRoute.todos)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                sectionHeader("To-Do", route: .todos, detail: nil, chevron: false)
                if store.isPlus {
                    Button {
                        router.focusNewTodo = true
                        path = [.todos]
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("Add a to-do")
                }
            }
        }
    }

    /// A section title that opens its page, with an optional count like "2 of 4".
    private func sectionHeader(_ title: String, route: DashboardRoute, detail: String?, chevron: Bool = true) -> some View {
        Button { path = [route] } label: {
            HStack(spacing: 4) {
                Text(title)
                Spacer()
                if let detail { Text(detail).monospacedDigit() }
                if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    /// Widgets and apps, plus setup while it isn't finished.
    private var homeScreenSection: some View {
        Section {
            if !isSetUp {
                NavigationLink(value: DashboardRoute.help) {
                    SettingsRow(icon: "checklist", tint: .green, title: "Set up your Home Screen",
                                subtitle: "\(checklist.requiredDone) of \(checklist.requiredTotal) done")
                }
            }
            NavigationLink(value: DashboardRoute.widgets) {
                SettingsRow(icon: "square.grid.2x2.fill", tint: .indigo, title: "Widgets",
                            subtitle: "Apps, style, colors, and extras")
            }
            NavigationLink(value: DashboardRoute.apps) {
                SettingsRow(icon: "square.stack", tint: .blue, title: "Apps",
                            subtitle: "Add apps, fix links, choose mindful pauses")
            }
        } header: {
            Text("Home Screen")
        }
    }

    private var todaySection: some View {
        let insights = Insights(events: store.events)
        let saved = TimeSaved.load()
        return Section {
            Button { router.sheet = .insights } label: {
                HStack {
                    stat(saved.formattedHours, "hours saved")
                    Spacer()
                    stat("\(insights.today.resisted)", "resisted today")
                    Spacer()
                    stat("\(insights.today.opened)", "opened today")
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Today")
        }
    }

    private var focusSection: some View {
        Section {
            if !focus.isAuthorized {
                Button {
                    Task {
                        await focus.requestAuthorization()
                        if focus.isAuthorized { router.sheet = .focus } else { showingBlockingHelp = true }
                    }
                } label: {
                    SettingsRow(icon: "lock.shield", tint: .indigo, title: "Turn on blocking",
                                subtitle: "Block apps during work time, wind-down, and focus sessions",
                                showsChevron: true)
                }
            } else {
                focusCard
                Button {
                    editingFocus = WorkPeriod(name: "Focus")
                    Task { await focus.requestNotificationPermission() }
                } label: {
                    Label("New schedule", systemImage: "plus")
                        .font(.subheadline)
                }
                ForEach(focus.workPeriods) { period in
                    focusRow(icon: period.mode == .allowOnly ? "lock.fill" : "moon.fill", tint: .indigo, title: period.name,
                             detail: "\(period.daysDescription) · \(period.timeRange) · \(period.appsSummary)",
                             isActive: focus.isRunning(period),
                             isOff: !period.isEnabled) {
                        editingFocus = period
                    }
                }
                if focus.limitEnabled {
                    focusRow(icon: "hourglass", tint: .orange, title: "Daily limit",
                             detail: "\(focus.limitMinutes) min a day on blocked apps",
                             isActive: focus.activeReasons.contains(.dailyLimit)) {
                        router.sheet = .focus
                    }
                }
            }
        } header: {
            Text("Focus")
        } footer: {
            if focus.isAuthorized && !focus.workPeriods.isEmpty {
                Text("Tap a focus to edit or delete it.")
            }
        }
    }

    /// What's blocking right now, with End, or Start focus when nothing is.
    @ViewBuilder
    private var focusCard: some View {
        let running = focus.workPeriods.first { focus.isRunning($0) }
        HStack(spacing: 14) {
            Image(systemName: focus.sessionEnd.map { $0 > .now } == true || running != nil ? "moon.fill" : "moon")
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                if let end = focus.sessionEnd, end > .now {
                    Text("Focus session").font(.headline)
                    Text("Until \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if let running {
                    Text(running.name).font(.headline)
                    Text("Blocking now · \(running.timeRange)")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Nothing blocked").font(.headline)
                    Text("Start a focus to block distractions").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let end = focus.sessionEnd, end > .now {
                if focus.canEndSession {
                    Button("End") { focus.endSession() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            } else if running == nil {
                Button("Start") { router.sheet = .focus }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
            }
        }
        .padding(.vertical, 6)
    }

    /// One schedule or rule, with whether it's blocking apps right now.
    private func focusRow(icon: String, tint: Color, title: String, detail: String,
                          isActive: Bool, isOff: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tint.gradient))
                    .opacity(isOff ? 0.4 : 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(isOff ? .secondary : .primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isActive {
                    Text("Now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.green))
                } else if isOff {
                    Text("Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityValue(isActive ? "Blocking now" : isOff ? "Off" : "Scheduled")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .light))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func refreshWidgets() async {
        widgetsAdded = await SetupChecklist.isAppsWidgetAdded()
    }
}
