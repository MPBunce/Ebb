//
//  SettingsView.swift
//  Ebb
//
//  Settings, grouped like iOS Settings. Every screen starts with a short explanation
//  of what it does and why.
//

import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var showWalkthrough = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(appCount: store.targets.count, homeCount: store.widgetAppIDs.count) {
                        showWalkthrough = true
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Set up") {
                    Button { showWalkthrough = true } label: {
                        SettingsRow(icon: "sparkles", tint: .indigo, title: "Walkthrough",
                                    subtitle: "Step-by-step setup with explanations")
                    }
                    NavigationLink { SetupGuideView() } label: {
                        SettingsRow(icon: "iphone", tint: .gray, title: "Home Screen setup",
                                    subtitle: "Wallpaper and widget steps for reference")
                    }
                }

                Section("Your apps") {
                    NavigationLink { ManageAppsView() } label: {
                        SettingsRow(icon: "square.stack", tint: .blue, title: "Apps",
                                    subtitle: "\(store.targets.count) added · edit links, hide, or remove")
                    }
                }

                Section("Home Screen") {
                    NavigationLink { WidgetsView() } label: {
                        SettingsRow(icon: "square.grid.2x2.fill", tint: .indigo, title: "Widgets",
                                    subtitle: "Apps widget, style, colors, Life, and Time Saved")
                    }
                    NavigationLink { AppearanceView() } label: {
                        SettingsRow(icon: "paintpalette", tint: .orange, title: "Colors & wallpaper",
                                    subtitle: "One color for Ebb, widgets, and wallpaper")
                    }
                }

                Section("Wellbeing") {
                    NavigationLink { PauseSettingsView() } label: {
                        SettingsRow(icon: "hourglass", tint: .mint, title: "Mindful pause",
                                    subtitle: "A breath before distracting apps")
                    }
                    Button { switchTo(.focus) } label: {
                        SettingsRow(icon: "moon.fill", tint: .indigo, title: "Focus & blocking",
                                    subtitle: "Sessions, wind-down, daily limits", showsChevron: true)
                    }
                    Button { switchTo(.insights) } label: {
                        SettingsRow(icon: "chart.bar.fill", tint: .green, title: "Insights",
                                    subtitle: "Opens, let-gos, and time given back", showsChevron: true)
                    }
                }

                Section {
                    NavigationLink { EbbPlusView() } label: {
                        SettingsRow(icon: "sparkles", tint: .yellow, title: "Ebb Plus",
                                    subtitle: "More app widgets and clock styles. Coming soon")
                    }
                }

                Section {
                    NavigationLink { PrivacySettingsView() } label: {
                        SettingsRow(icon: "hand.raised.fill", tint: .blue, title: "Privacy & data",
                                    subtitle: "Everything stays on this iPhone")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showWalkthrough) {
                OnboardingView(isReplay: true)
                    .ebbColorScheme()
            }
        }
    }

    private func switchTo(_ sheet: HomeSheet) {
        router.sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            router.sheet = sheet
        }
    }
}

// MARK: - Building blocks

/// An iOS Settings–style row: tinted icon, title, and a one-line explanation.
struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    /// Buttons don't get a disclosure chevron automatically.
    var showsChevron = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(tint.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// The intro paragraph at the top of each settings screen.
struct ExplainerHeader: View {
    let icon: String
    let text: String

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SummaryCard: View {
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults)
    private var backgroundHex = Appearance.defaultBackground
    @AppStorage(AppGroup.Key.textHex, store: AppGroup.defaults)
    private var textHex = Appearance.defaultText

    let appCount: Int
    let homeCount: Int
    let onWalkthrough: () -> Void

    var body: some View {
        let background = HexColor(hex: backgroundHex) ?? HexColor(red: 0, green: 0, blue: 0)
        let text = HexColor(hex: textHex) ?? HexColor(red: 1, green: 1, blue: 1)

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ebb")
                    .font(.system(size: 34, weight: .thin))
                Text("\(appCount) apps · \(homeCount) on widgets")
                    .font(.footnote)
                    .opacity(0.7)
                Button("Replay walkthrough", action: onWalkthrough)
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.bordered)
                    .tint(text.color)
                    .padding(.top, 4)
            }
            Spacer()
            Image(systemName: "water.waves")
                .font(.system(size: 44, weight: .thin))
                .opacity(0.8)
        }
        .foregroundStyle(text.color)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22).fill(background.color))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.secondary.opacity(0.25)))
    }
}

// MARK: - Apps

struct ManageAppsView: View {
    @Environment(LauncherStore.self) private var store
    @State private var isAdding = false
    @State private var isScanning = false

    private var apps: [LaunchTarget] {
        store.targets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Button {
                    isScanning = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.blue.gradient))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Find apps on this iPhone")
                                .foregroundStyle(.primary)
                            Text("Add the apps you have in one tap")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
                Button {
                    isAdding = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.gray.gradient))
                        Text("Browse all apps")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
            }

            Section {
                ForEach(apps) { target in
                    NavigationLink {
                        TargetEditor(target: target)
                    } label: {
                        AppRow(target: target)
                    }
                }
                .onDelete { offsets in
                    offsets.map { apps[$0] }.forEach(store.remove)
                }
            } header: {
                Text("Your apps · \(apps.count)")
            } footer: {
                Text("Tap an app to rename it, change how it opens, or add a mindful pause. Swipe to remove.")
            }
        }
        .navigationTitle("Apps")
        .sheet(isPresented: $isAdding) { AddAppsView() }
        .sheet(isPresented: $isScanning) {
            NavigationStack { InstalledAppsView() }
        }
    }
}

/// Apps Ebb found on this iPhone that aren't added yet, ready to add in one tap.
struct InstalledAppsView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var found: [CatalogApp] = []
    @State private var selected: Set<String> = []

    var body: some View {
        List {
            if found.isEmpty {
                ContentUnavailableView("You're all set", systemImage: "checkmark.circle",
                                       description: Text("Every app Ebb can find on this iPhone is already added."))
            } else {
                Section {
                    ForEach(found) { app in
                        Button {
                            if selected.contains(app.id) { selected.remove(app.id) } else { selected.insert(app.id) }
                        } label: {
                            HStack(spacing: 14) {
                                AppMonogram(name: app.name)
                                Text(app.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selected.contains(app.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selected.contains(app.id) ? Color.accentColor : Color.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(selected.contains(app.id) ? .isSelected : [])
                    }
                } header: {
                    Text("Found \(found.count) app\(found.count == 1 ? "" : "s")")
                } footer: {
                    Text("iPhone only lets Ebb check for apps it knows about, so a few of yours may be missing. Add those from Browse all apps with a Shortcut.")
                }
            }
        }
        .navigationTitle("On this iPhone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add \(selected.count)") {
                    for app in found where selected.contains(app.id) {
                        let target = app.makeTarget()
                        store.add(target)
                        store.addToFirstOpenList(target.id)
                    }
                    dismiss()
                }
                .disabled(selected.isEmpty)
            }
            if !found.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(selected.count == found.count ? "Deselect all" : "Select all") {
                        selected = selected.count == found.count ? [] : Set(found.map(\.id))
                    }
                }
            }
        }
        .onAppear {
            found = InstalledApps.detect().filter { !store.contains(catalogApp: $0) }
            // Third-party apps are pre-selected; built-in ones are opt-in.
            selected = Set(found.filter { $0.category != .essentials }.map(\.id))
        }
    }
}

// MARK: - Look

// MARK: - Wellbeing

private struct PauseSettingsView: View {
    @Environment(LauncherStore.self) private var store
    @AppStorage(PrefKey.pauseSeconds) private var pauseSeconds = 5
    @AppStorage(PrefKey.askWhy) private var askWhy = true

    var body: some View {
        Form {
            ExplainerHeader(icon: "hourglass", text: "Before a mindful app opens, Ebb shows a short breathing countdown. Most urges pass in a few seconds. Backing out is counted as time given back.")
            Section {
                Stepper("Pause for \(pauseSeconds) seconds", value: $pauseSeconds, in: 3...30)
                Toggle("Ask what it's for", isOn: $askWhy)
            } footer: {
                Text("Your answers show up in Insights, so you can see what you actually reach for your phone to do.")
            }
            Section {
                ForEach(store.targets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { target in
                    Toggle(target.name, isOn: Binding(
                        get: { target.isMindful },
                        set: { newValue in
                            var updated = target
                            updated.isMindful = newValue
                            store.update(updated)
                        }
                    ))
                }
            } header: {
                Text("Apps with a pause")
            } footer: {
                Text("Widget taps on these apps go through Ebb for the pause. All other apps open directly.")
            }
        }
        .navigationTitle("Mindful pause")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Widgets

// MARK: - Privacy

private struct PrivacySettingsView: View {
    @Environment(LauncherStore.self) private var store
    @State private var confirmClear = false

    var body: some View {
        Form {
            ExplainerHeader(icon: "hand.raised", text: "Ebb has no accounts, no ads, no analytics, and no servers. Your apps, history, and settings are stored only on this iPhone.")
            Section {
                LabeledContent("Launch history", value: "\(store.events.count) entries")
                LabeledContent("Kept for", value: "\(LauncherStore.historyDays) days")
                Button("Clear launch history", role: .destructive) { confirmClear = true }
            } footer: {
                Text("History powers Insights. It only includes apps opened through Ebb itself, including mindful-pause apps opened from widgets.")
            }
            Section {
                Text("Screen Time blocking uses Apple's private tokens. Ebb can block the apps you pick, but it never learns which apps they are.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Screen Time")
            }
        }
        .navigationTitle("Privacy & data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear all launch history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { store.clearHistory() }
        }
    }
}
