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

    private var apps: [LaunchTarget] {
        store.targets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            ExplainerHeader(icon: "link", text: "iPhone doesn't let apps see what's installed, so each app here has a link Ebb uses to open it. Most use a URL scheme. For anything else, make a Shortcut with the “Open App” action and link to it.")
            Section {
                ForEach(apps) { target in
                    NavigationLink {
                        TargetEditor(target: target)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(target.name)
                                if store.widgetAppIDs.contains(target.id) { Image(systemName: "square.grid.2x2").font(.caption) }
                                if target.isMindful { Image(systemName: "hourglass").font(.caption) }
                                if target.isHidden { Image(systemName: "eye.slash").font(.caption) }
                            }
                            Text(target.methodDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { apps[$0] }.forEach(store.remove)
                }
            } footer: {
                Text("Grid: on an app widget. Hourglass: mindful pause. Eye: hidden from lists.")
            }
        }
        .navigationTitle("Apps")
        .toolbar {
            Button("Add", systemImage: "plus") { isAdding = true }
        }
        .sheet(isPresented: $isAdding) { AddAppsView() }
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
