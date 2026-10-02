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
            if !focus.isAuthorized {
                Button {
                    Task {
                        await focus.requestAuthorization()
                        if focus.isAuthorized { router.sheet = .focus }
                    }
                } label: {
                    SettingsRow(icon: "lock.shield", tint: .indigo, title: "Turn on blocking",
                                subtitle: "Block apps during work time, wind-down, and focus sessions",
                                showsChevron: true)
                }
            } else {
                if let end = focus.sessionEnd, end > .now {
                    focusRow(icon: "moon.fill", tint: .indigo, title: "Focus session",
                             detail: "Until \(end.formatted(date: .omitted, time: .shortened))", isActive: true)
                }
                ForEach(focus.workPeriods) { period in
                    focusRow(icon: period.mode == .allowOnly ? "lock.fill" : "moon.fill", tint: .indigo, title: period.name,
                             detail: "\(period.daysDescription) · \(period.timeRange) · \(period.appsSummary)",
                             isActive: focus.isRunning(period),
                             isOff: !period.isEnabled)
                }
                if focus.limitEnabled {
                    focusRow(icon: "hourglass", tint: .orange, title: "Daily limit",
                             detail: "\(focus.limitMinutes) min a day on blocked apps",
                             isActive: focus.activeReasons.contains(.dailyLimit))
                }
                Button { router.sheet = .focus } label: {
                    if hasFocusRules {
                        Label("Manage focus", systemImage: "slider.horizontal.3")
                    } else {
                        Label("Create a focus", systemImage: "plus")
                    }
                }
            }
        } header: {
            Text("Focus")
        } footer: {
            if focus.isAuthorized && !hasFocusRules {
                Text("Nothing is set up yet. A focus blocks the apps you choose on a schedule.")
            }
        }
    }

    private var hasFocusRules: Bool {
        !focus.workPeriods.isEmpty || focus.limitEnabled
            || (focus.sessionEnd.map { $0 > .now } ?? false)
    }

    /// One schedule or rule, with whether it's blocking apps right now.
    private func focusRow(icon: String, tint: Color, title: String, detail: String,
                          isActive: Bool, isOff: Bool = false) -> some View {
        Button { router.sheet = .focus } label: {
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
