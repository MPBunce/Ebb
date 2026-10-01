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
    @AppStorage("showSetupWhenDone") private var showSetupWhenDone = false

    @State private var widgetsAdded = false
    @State private var path: [DashboardRoute] = []
    /// Where the user was, so Ebb reopens to the same screen even after iOS closes it.
    @SceneStorage("dashboardPath") private var savedPath = ""
    @SceneStorage("dashboardSheet") private var savedSheet = ""

    private var steps: [SetupStep] {
        [
            SetupStep(
                id: .apps, title: "Choose your apps",
                detail: store.widgetAppIDs.isEmpty
                    ? "Pick the few apps you want on your Home Screen."
                    : "\(store.widgetAppIDs.count) on your app widgets, \(store.targets.count) in total.",
                isDone: !store.widgetAppIDs.isEmpty
            ),
            SetupStep(
                id: .colors, title: "Pick your colors",
                detail: "One color for Ebb, your widgets, and your wallpaper.",
                isDone: backgroundHex != nil
            ),
            SetupStep(
                id: .wallpaper, title: "Set a matching wallpaper",
                detail: "So your widgets blend in and only app names show.",
                isDone: wallpaperSet
            ),
            SetupStep(
                id: .widgets, title: "Add the Apps widget",
                detail: widgetsAdded ? "Ebb's widget is on your Home Screen." : "Put your apps on your Home Screen as plain text.",
                isDone: widgetsAdded
            ),
            SetupStep(
                id: .screenTime, title: "Turn on blocking",
                detail: "Lets Ebb block apps during work time and focus.",
                isDone: focus.isAuthorized, isOptional: true
            ),
        ]
    }

    private var requiredDone: Int { steps.filter { !$0.isOptional && $0.isDone }.count }
    private var requiredTotal: Int { steps.filter { !$0.isOptional }.count }
    private var isSetUp: Bool { requiredDone == requiredTotal }

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

                if !isSetUp || showSetupWhenDone {
                    setupSection
                }

                if isSetUp {
                    Section {
                        Toggle("Show setup checklist", isOn: $showSetupWhenDone)
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

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(requiredDone), total: Double(requiredTotal))
                    .tint(.green)
                Text(isSetUp ? "All set" : "\(requiredDone) of \(requiredTotal) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                switch step.id {
                case .screenTime:
                    Button { router.sheet = .focus } label: {
                        SetupStepRow(number: index + 1, step: step, showsChevron: true)
                    }
                default:
                    NavigationLink(value: route(for: step.id)) {
                        SetupStepRow(number: index + 1, step: step)
                    }
                }
            }
        } header: {
            Text("Set up your Home Screen")
        } footer: {
            Text("iPhone doesn't let apps replace the Home Screen, so Ebb builds yours from widgets on a matching wallpaper.")
        }
    }

    private func route(for step: SetupStep.ID) -> DashboardRoute {
        switch step {
        case .apps, .widgets, .screenTime: .widgets
        case .colors: .colors
        case .wallpaper: .wallpaper
        }
    }

    @ViewBuilder
    private func destination(for route: DashboardRoute) -> some View {
        switch route {
        case .widgets: WidgetsView()
        case .apps: ManageAppsView()
        case .colors: AppearanceView()
        case .wallpaper: WallpaperStepView()
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
            Button { router.sheet = .focus } label: {
                HStack(spacing: 14) {
                    Image(systemName: focusIcon)
                        .font(.title3)
                        .frame(width: 30)
                        .foregroundStyle(focus.isShielding ? .indigo : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(focusTitle)
                            .foregroundStyle(.primary)
                        Text(focusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Focus")
        }
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
        let configurations = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        widgetsAdded = configurations.contains { $0.kind == "EbbLauncher.apps" }
    }
}

// MARK: - Setup steps

struct SetupStep: Identifiable {
    enum ID { case apps, colors, wallpaper, widgets, screenTime }

    let id: ID
    let title: String
    let detail: String
    let isDone: Bool
    var isOptional = false
}

private struct SetupStepRow: View {
    let number: Int
    let step: SetupStep
    var showsChevron = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if step.isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                } else {
                    Text("\(number)")
                        .font(.callout.weight(.medium))
                        .frame(width: 26, height: 26)
                        .background(Circle().strokeBorder(.secondary.opacity(0.5)))
                }
            }
            .frame(width: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.title)
                        .foregroundStyle(step.isDone ? .secondary : .primary)
                    if step.isOptional {
                        Text("Optional")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(step.isDone ? "Done" : "Not done")
    }
}

// MARK: - Step screens

private struct WallpaperStepView: View {
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults) private var backgroundHex = Appearance.defaultBackground
    @AppStorage(AppGroup.Key.wallpaperSet, store: AppGroup.defaults) private var wallpaperSet = false

    var body: some View {
        Form {
            ExplainerHeader(icon: "photo.on.rectangle", text: "iPhone doesn't let apps change your wallpaper, so Ebb saves one in your color to Photos and you set it from there. With matching colors, your widgets' edges disappear.")
            Section {
                WallpaperSaveFlow(background: HexColor(hex: backgroundHex) ?? HexColor(red: 0, green: 0, blue: 0))
            }
            Section {
                SeamlessTips()
                    .padding(.vertical, 4)
            }
            Section {
                Toggle("I've set it as my wallpaper", isOn: $wallpaperSet)
            } footer: {
                Text("Ebb can't see your wallpaper, so tick this once it's set.")
            }
        }
        .navigationTitle("Wallpaper")
        .navigationBarTitleDisplayMode(.inline)
    }
}

