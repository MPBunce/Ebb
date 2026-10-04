//
//  WidgetsView.swift
//  Ebb
//
//  One page for everything on the Home Screen: whether the widgets are added, what the
//  Apps widget shows and how it looks, the shared colors, and the extra widgets' settings.
//

import SwiftUI
import WidgetKit

struct WidgetsView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppGroup.Key.listAlignment, store: AppGroup.defaults) private var alignment = ListAlignment.leading
    @AppStorage(AppGroup.Key.listTextSize, store: AppGroup.defaults) private var textSize = ListTextSize.medium
    @AppStorage(AppGroup.Key.typeface, store: AppGroup.defaults) private var typeface = Typeface.system
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults) private var backgroundHex = Appearance.defaultBackground
    @AppStorage(AppGroup.Key.textHex, store: AppGroup.defaults) private var textHex = Appearance.defaultText
    @AppStorage(AppGroup.Key.sex, store: AppGroup.defaults) private var sex = Sex.unspecified
    @AppStorage(AppGroup.Key.minutesPerResist, store: AppGroup.defaults)
    private var minutesPerResist = TimeSaved.defaultMinutesPerResist

    @State private var birthDate = AppGroup.defaults.object(forKey: AppGroup.Key.birthDate) as? Date
    @State private var addedKinds: Set<String> = []

    var body: some View {
        Form {
            Section {
                WidgetPreview(apps: store.primaryApps, label: store.lists.first?.name ?? "Apps widget")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            appWidgetsSection
            styleSection
            clockSection
            colorsSection
            lifeSection
            timeSavedSection
            WeatherSection()
            statusSection

            Section {
                Text("Apps and Spacer come in medium and large; the rest also come in small. Every widget follows the alignment above unless you change it. Long-press one › Edit Widget for its options:\n\n**Clock**: style and date.\n**Year**: today, this week, month, or year, shown as a percent, bar, dots, ring, or countdown.\n**Life**: years, weeks & days, percent, bar, years as dots, ring, or weeks left, as life lived or remaining.\n**Time Saved**: a number, a breakdown, or what it adds up to, in minutes, hours, or days.\n**Weather**: now, the next hours, or the week where you are, in °C or °F.\n**Spacer**: an empty block in your widget color for spacing things out.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Sizes & options")
            }
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onChange(of: alignment) { reload() }
        .onChange(of: textSize) { reload() }
        .onChange(of: typeface) { reload() }
        .onChange(of: backgroundHex) { reload() }
        .onChange(of: textHex) { reload() }
        .onChange(of: sex) { reload() }
        .onChange(of: minutesPerResist) { reload() }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            ForEach(Self.kinds, id: \.kind) { item in
                HStack {
                    Label(item.name, systemImage: item.icon)
                    Spacer()
                    if addedKinds.contains(item.kind) {
                        Text("On Home Screen")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Not added")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink("How to add widgets") { WidgetsGuideView() }
        } header: {
            Text("Your widgets")
        } footer: {
            Text("iPhone doesn't let apps add widgets for you. Long-press the Home Screen › Edit › Add Widget › Ebb.")
        }
    }

    private var appWidgetsSection: some View {
        Section {
            ForEach(Array(store.lists.enumerated()), id: \.element.id) { index, list in
                let locked = store.isLocked(list)
                NavigationLink {
                    AppWidgetEditor(listID: list.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name)
                            Text(summary(for: list))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if locked {
                            PlusBadge()
                        } else {
                            Text("\(list.appIDs.count)/\(AppWidgetList.capacity)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(locked)
            }

            if store.canAddList {
                Button {
                    store.addList()
                } label: {
                    Label("Add app widget", systemImage: "plus")
                }
            } else {
                NavigationLink { EbbPlusView() } label: {
                    HStack {
                        Label(store.isPlus ? "All \(store.maxLists) app widgets in use" : "\(EbbPlus.plusAppWidgets - EbbPlus.freeAppWidgets) more app widgets",
                              systemImage: store.isPlus ? "checkmark" : "lock")
                        Spacer()
                        if !store.isPlus { PlusBadge() }
                    }
                    .foregroundStyle(.secondary)
                }
                .disabled(store.isPlus)
            }
        } header: {
            Text("App widgets")
        } footer: {
            Text("Each app widget holds up to \(AppWidgetList.capacity) apps. Add an Apps widget to your Home Screen for each one, then long-press it › Edit Widget › App Widget to choose which it shows.")
        }
    }

    private func summary(for list: AppWidgetList) -> String {
        let names = store.apps(in: list).map(\.name)
        return names.isEmpty ? "No apps yet" : names.joined(separator: ", ")
    }

    private var styleSection: some View {
        Section {
            Picker("Alignment", selection: $alignment) {
                ForEach(ListAlignment.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Text size", selection: $textSize) {
                ForEach(ListTextSize.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Typeface", selection: $typeface) {
                ForEach(Typeface.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Style")
        } footer: {
            Text("Used by every widget: apps, clocks, and progress. Taps open apps directly; apps with a mindful pause go through Ebb first. To style one widget differently, long-press it › Edit Widget.")
        }
    }

    private var clockSection: some View {
        Section {
            ForEach(ClockStyle.allCases) { style in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: style))
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(style.name)
                            if style.isPlus && !store.isPlus { PlusBadge() }
                        }
                        Text(style.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(style.isPlus && !store.isPlus ? 0.6 : 1)
                .accessibilityElement(children: .combine)
            }
            if !store.isPlus {
                NavigationLink("About Ebb Plus") { EbbPlusView() }
            }
        } header: {
            Text("Clock widget styles")
        } footer: {
            Text("Add the Clock widget, then long-press it › Edit Widget › Style.")
        }
    }

    private func icon(for style: ClockStyle) -> String {
        switch style {
        case .digital: "textformat.123"
        case .analog: "clock"
        case .stacked: "square.stack"
        case .words: "text.quote"
        case .dayRing: "circle.dashed"
        }
    }

    private var colorsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Appearance.presets) { preset in
                        let isSelected = backgroundHex == preset.background
                        Button {
                            backgroundHex = preset.background
                            textHex = preset.text
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(HexColor(hex: preset.background)!.color)
                                    .overlay {
                                        Text("Aa")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(HexColor(hex: preset.text)!.color)
                                    }
                                    .overlay {
                                        Circle().strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                                              lineWidth: isSelected ? 2 : 1)
                                    }
                                    .frame(width: 44, height: 44)
                                Text(preset.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            NavigationLink("Custom colors & wallpaper") { AppearanceView() }
        } header: {
            Text("Colors")
        } footer: {
            Text("Every widget uses this color. Set a wallpaper in the same color so the widgets' edges disappear.")
        }
    }

    private var lifeSection: some View {
        Section {
            if let birthDate {
                DatePicker("Birthday",
                           selection: Binding(get: { birthDate }, set: { saveBirthDate($0) }),
                           in: Self.birthDateRange,
                           displayedComponents: .date)
                LabeledContent("Age", value: "\(LifeProgress.age(birthDate: birthDate))")
                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Life expectancy", value: "\(sex.lifeExpectancy.formatted()) years")
                Button("Remove birthday", role: .destructive) { saveBirthDate(nil) }
            } else {
                Button("Add your birthday") {
                    saveBirthDate(Calendar.current.date(byAdding: .year, value: -30, to: .now))
                }
            }
        } header: {
            Text("Life widget")
        } footer: {
            Text("Shows how much of an average life you've lived, using US averages from the CDC (2023). Your birthday and sex never leave this iPhone.")
        }
    }

    private var timeSavedSection: some View {
        Section {
            Stepper("\(minutesPerResist) min per app let go", value: $minutesPerResist, in: 1...60)
        } header: {
            Text("Time Saved widget")
        } footer: {
            Text("iPhone doesn't share real Screen Time totals with apps, so this is an estimate: each app you back out of during a mindful pause, plus time in focus sessions.")
        }
    }

    // MARK: Helpers

    private static let kinds: [(kind: String, name: String, icon: String)] = [
        ("EbbLauncher.apps", "Apps", "list.bullet"),
        ("EbbClock", "Clock", "clock"),
        ("EbbYear", "Year", "calendar"),
        ("EbbLife", "Life", "hourglass"),
        ("EbbTimeSaved", "Time Saved", "leaf"),
        ("EbbTimeAndLife", "Time & Life (Plus)", "hourglass.and.lock"),
        ("EbbWeather", "Weather", "cloud.sun"),
        ("EbbHabits", "Habits", "checklist"),
        ("EbbTodo", "To-Do", "checkmark.circle"),
        ("EbbSpacer", "Spacer", "rectangle.dashed"),
        ("EbbOpen", "Open Ebb", "water.waves"),
    ]

    /// Birthdays from 110 years ago up to today.
    private static var birthDateRange: ClosedRange<Date> {
        (Calendar.current.date(byAdding: .year, value: -110, to: .now) ?? .distantPast)...Date.now
    }

    private func saveBirthDate(_ date: Date?) {
        // Store the start of the day, so the widget counts from the birthday itself.
        let day = date.map { Calendar.current.startOfDay(for: $0) }
        birthDate = day
        AppGroup.defaults.set(day, forKey: AppGroup.Key.birthDate)
        reload()
    }

    private func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refresh() async {
        let configurations = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        addedKinds = Set(configurations.map(\.kind))
    }
}

/// A live preview of the Apps widget in the user's colors and style.
struct WidgetPreview: View {
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults) private var backgroundHex = Appearance.defaultBackground
    @AppStorage(AppGroup.Key.textHex, store: AppGroup.defaults) private var textHex = Appearance.defaultText
    @AppStorage(AppGroup.Key.listAlignment, store: AppGroup.defaults) private var alignment = ListAlignment.leading
    @AppStorage(AppGroup.Key.listTextSize, store: AppGroup.defaults) private var textSize = ListTextSize.medium
    @AppStorage(AppGroup.Key.typeface, store: AppGroup.defaults) private var typeface = Typeface.system

    let apps: [LaunchTarget]
    let label: String

    var body: some View {
        let background = HexColor(hex: backgroundHex)?.color ?? .black
        let text = HexColor(hex: textHex)?.color ?? .white

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ebb")
                    .font(.system(size: 30, weight: .thin))
                Spacer()
                Text(label)
                    .font(.caption.weight(.medium))
                    .opacity(0.6)
            }

            VStack(alignment: alignment.horizontal, spacing: textSize.points * 0.38) {
                if apps.isEmpty {
                    Text("Your apps will appear here")
                        .font(.system(size: textSize.points, weight: .light))
                        .opacity(0.5)
                } else {
                    ForEach(apps.prefix(AppWidgetList.capacity)) { target in
                        Text(target.name)
                            .font(.system(size: textSize.points, weight: .light))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment.frame)
        }
        .fontDesign(typeface.design)
        .foregroundStyle(text)
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 26).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.secondary.opacity(0.25)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of your Apps widget")
    }
}

/// Step-by-step instructions for adding Ebb's widgets to the Home Screen.
struct WidgetsGuideView: View {
    var body: some View {
        List {
            ExplainerHeader(icon: "square.grid.2x2", text: "The Apps widget is your new Home Screen: your apps as plain text, opening with one tap. Apps with a mindful pause go through Ebb first.")
            Section("Add the Apps widget") {
                StepRow(number: 1, title: "Clear a page",
                        detail: "Long-press the Home Screen, tap the page dots at the bottom, and keep one page checked. Your apps stay in the App Library.")
                StepRow(number: 2, title: "Add the widget",
                        detail: "Tap Edit › Add Widget, search for Ebb, and add the large Apps widget.")
                StepRow(number: 3, title: "Make it yours",
                        detail: "Long-press the widget › Edit Widget to choose its apps. Alignment and text size follow your Widget settings unless you change them there.")
            }
            Section("Extras") {
                StepRow(number: 4, title: "Add extras",
                        detail: "Clock, Year, Life, and Time Saved come in every size. Use a Spacer to leave calm, empty room between widgets.")
                StepRow(number: 5, title: "Lock Screen",
                        detail: "Add Open Ebb to your Lock Screen so Ebb is one tap away.")
                StepRow(number: 6, title: "Empty the Dock",
                        detail: "Drag apps out of the Dock for the calmest look.")
            }
        }
        .navigationTitle("How to add widgets")
        .navigationBarTitleDisplayMode(.inline)
    }
}
