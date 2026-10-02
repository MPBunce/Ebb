//
//  DashboardView.swift
//  Ebb
//
//  The main screen. Ebb's real home is the iPhone Home Screen, built from its widgets,
//  so this screen is for setting that up and keeping an eye on it.
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
                Section {
                    WidgetPreview(apps: store.primaryApps, label: isSetUp ? "Your Home Screen" : "Preview")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink(value: DashboardRoute.widgets) {
                        SettingsRow(icon: "square.grid.2x2.fill", tint: .indigo, title: "Widgets",
                                    subtitle: "Everything on your Home Screen: apps, style, colors, and extras")
                    }
                    NavigationLink(value: DashboardRoute.apps) {
                        SettingsRow(icon: "square.stack", tint: .blue, title: "Apps",
                                    subtitle: "Add apps, fix links, choose mindful pauses")
                    }
                } header: {
                    Text("Home Screen")
                }

                focusSection
                todaySection

                Section {
                    NavigationLink(value: DashboardRoute.help) {
                        SettingsRow(icon: isSetUp ? "questionmark" : "checklist", tint: isSetUp ? .gray : .green,
                                    title: "Help & Setup",
                                    subtitle: isSetUp
                                        ? "Guides and common questions"
                                        : "Setup: \(checklist.requiredDone) of \(checklist.requiredTotal) done · guides and common questions")
                    }
                }
            }
            .navigationDestination(for: DashboardRoute.self) { destination(for: $0) }
            .navigationTitle("Ebb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { router.sheet = .settings }
                }
            }
        }
        .task { await refreshWidgets() }
        .onAppear(perform: restoreState)
        .onChange(of: path) { _, newPath in savedPath = newPath.map(\.rawValue).joined(separator: ",") }
        .onChange(of: router.sheet) { _, sheet in savedSheet = sheet?.rawValue ?? "" }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshWidgets() } }
        }
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                case .settings: SettingsView()
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
        }
    }

    private func restoreState() {
        if path.isEmpty, !savedPath.isEmpty {
            path = savedPath.split(separator: ",").compactMap { DashboardRoute(rawValue: String($0)) }
        }
        if router.sheet == nil, let sheet = HomeSheet(rawValue: savedSheet) {
            router.sheet = sheet
        }
    }

    private var todaySection: some View {
        let insights = Insights(events: store.events)
        let saved = TimeSaved.load()
        return Section {
            Button { router.sheet = .insights } label: {
                HStack {
                    stat(saved.formattedHours, "hours given back")
                    Spacer()
                    stat("\(insights.today.resisted)", "let go today")
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: focusIcon)
                        .font(.title3)
                        .foregroundStyle(focus.isShielding ? .white : .indigo)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(focus.isShielding ? AnyShapeStyle(.indigo) : AnyShapeStyle(.indigo.opacity(0.15))))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(focusTitle)
                            .font(.headline)
                        Text(focusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { router.sheet = .focus }

                Button {
                    if focus.isAuthorized {
                        router.sheet = .focus
                    } else {
                        Task {
                            await focus.requestAuthorization()
                            if focus.isAuthorized { router.sheet = .focus }
                        }
                    }
                } label: {
                    Label(focusAction.title, systemImage: focusAction.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.indigo)
            }
            .padding(.vertical, 6)
        } header: {
            Text("Focus")
        }
    }

    /// The one thing to do next with blocking.
    private var focusAction: (title: String, icon: String) {
        if !focus.isAuthorized { return ("Turn on blocking", "lock.shield") }
        if focus.isInWorkPeriod { return ("Manage work time", "briefcase") }
        if let end = focus.sessionEnd, end > .now { return ("View session", "moon.fill") }
        if focus.workPeriods.filter(\.isEnabled).isEmpty { return ("Set up work time", "briefcase") }
        return ("Start a focus session", "moon")
    }

    private var focusIcon: String {
        if focus.isInWorkPeriod { return "briefcase.fill" }
        return focus.isShielding ? "moon.fill" : "moon"
    }

    private var focusTitle: String {
        if !focus.isAuthorized { return "Blocking is off" }
        if let period = focus.currentWorkPeriod, focus.isInWorkPeriod {
            return "\(period.name) until \(WorkPeriod.format(period.end))"
        }
        if let end = focus.sessionEnd, end > .now {
            return "Focusing until \(end.formatted(date: .omitted, time: .shortened))"
        }
        return focus.isShielding ? "Apps are blocked" : "Nothing blocked right now"
    }

    private var focusDetail: String {
        if !focus.isAuthorized { return "Turn on Screen Time to block apps during work and focus." }
        let periods = focus.workPeriods.filter(\.isEnabled)
        if periods.isEmpty { return "Set up work time, focus sessions, and limits." }
        return periods.map { "\($0.name): \($0.daysDescription) \($0.timeRange)" }.joined(separator: " · ")
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
