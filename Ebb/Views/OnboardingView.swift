//
//  OnboardingView.swift
//  Ebb
//
//  A guided walkthrough that explains how Ebb works on iPhone and sets it up step by
//  step: apps, colors, wallpaper, widgets, mindful pause, and focus. Replayable from Settings.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKey.hasOnboarded) private var hasOnboarded = false

    /// True when replayed from Settings, which shows a close button and skips seeding apps.
    var isReplay = false

    @State private var step = Step.welcome

    enum Step: Int, CaseIterable {
        case welcome, howItWorks, apps, look, wallpaper, widgets, pause, focus, done
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $step) {
                ForEach(Step.allCases, id: \.self) { step in
                    page(for: step)
                        .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            footer
        }
        .background(Color(.systemBackground))
        .onAppear {
            if !isReplay { seedStarterApps() }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                .tint(.primary)
                .frame(maxWidth: 160)
            Spacer()
            if step != .done {
                Button(isReplay ? "Close" : "Skip") { finish() }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button {
                    move(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 22, height: 22)
                        .padding(14)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Back")
            }
            Button {
                step == .done ? finish() : move(1)
            } label: {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(.systemBackground))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .apps: "Continue with \(store.targets.count) apps"
        case .done: "Go to Ebb"
        default: "Next"
        }
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func finish() {
        hasOnboarded = true
        if isReplay { dismiss() }
    }

    private func seedStarterApps() {
        guard store.targets.isEmpty else { return }
        for app in AppCatalog.apps where AppCatalog.starterNames.contains(app.name) {
            let target = app.makeTarget()
            store.add(target)
            store.addToFirstOpenList(target.id)
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func page(for step: Step) -> some View {
        switch step {
        case .welcome: WelcomePage()
        case .howItWorks: HowItWorksPage()
        case .apps: AppsPage()
        case .look: LookPage()
        case .wallpaper: WallpaperPage()
        case .widgets: WidgetsPage()
        case .pause: PausePage()
        case .focus: FocusPage()
        case .done: DonePage()
        }
    }
}

// MARK: - Page building blocks

/// Title, explanation, and optional content for one walkthrough page.
private struct WalkthroughPage<Content: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .thin))
                    .padding(.top, 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.weight(.light))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

extension WalkthroughPage where Content == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// A numbered instruction.
struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .frame(width: 26, height: 26)
                .background(Circle().fill(.quaternary))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short "why" callout.
private struct Note: View {
    let text: String
    var body: some View {
        Label {
            Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .foregroundStyle(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.5)))
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        WalkthroughPage(
            symbol: "water.waves",
            title: "Welcome to Ebb",
            message: "A quieter iPhone. Just the apps you need as plain text, a breath before the ones that pull you in, and nothing else competing for your attention."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Plain-text widgets that open your apps", systemImage: "textformat")
                Label("A wallpaper that makes widgets disappear", systemImage: "rectangle.on.rectangle")
                Label("A mindful pause before distracting apps", systemImage: "hourglass")
                Label("Focus sessions and daily limits", systemImage: "moon")
            }
            .font(.callout)
            Text("Setup takes about two minutes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }
}

private struct HowItWorksPage: View {
    var body: some View {
        WalkthroughPage(
            symbol: "iphone",
            title: "How Ebb works",
            message: "Apple doesn't let apps replace the iPhone Home Screen. Instead, Ebb gives you widgets that show your apps as text and open them with a tap, right from your real Home Screen."
        ) {
            HStack(alignment: .top, spacing: 16) {
                PhoneMock()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Widgets can't be see-through, so Ebb colors them to match your wallpaper exactly. The edges vanish and only the app names show.")
                    Text("This app is where you set it all up: your apps, colors, widgets, and focus.")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// A tiny illustration of an Ebb home screen in the current colors.
private struct PhoneMock: View {
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults)
    private var backgroundHex = Appearance.defaultBackground
    @AppStorage(AppGroup.Key.textHex, store: AppGroup.defaults)
    private var textHex = Appearance.defaultText

    var body: some View {
        WallpaperCard(
            title: "",
            background: HexColor(hex: backgroundHex) ?? HexColor(red: 0, green: 0, blue: 0),
            text: HexColor(hex: textHex) ?? HexColor(red: 1, green: 1, blue: 1),
            isSelected: false
        ) {}
        .frame(width: 110)
        .allowsHitTesting(false)
    }
}

private struct AppsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose your apps")
                    .font(.largeTitle.weight(.light))
                Text("Tap to add. We've started you with a few essentials. Apps not listed can be added later with a Shortcut, which works for any app.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            CatalogPicker(addsToHome: true)
        }
    }
}

private struct LookPage: View {
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults)
    private var backgroundHex = Appearance.defaultBackground
    @AppStorage(AppGroup.Key.textHex, store: AppGroup.defaults)
    private var textHex = Appearance.defaultText

    var body: some View {
        WalkthroughPage(
            symbol: "paintpalette",
            title: "Pick your colors",
            message: "This color is used by the Ebb app, every widget, and your wallpaper. Midnight and Paper are the two built-in wallpapers. You can choose any color later in Settings."
        ) {
            HStack(spacing: 16) {
                ForEach(Appearance.wallpaperPresets) { preset in
                    WallpaperCard(
                        title: preset.name,
                        background: HexColor(hex: preset.background)!,
                        text: HexColor(hex: preset.text)!,
                        isSelected: backgroundHex == preset.background
                    ) {
                        backgroundHex = preset.background
                        textHex = preset.text
                    }
                }
            }
            Note(text: "Dark wallpapers are easiest on the eyes and battery. Paper feels like a page of a book.")
        }
    }
}

private struct WallpaperPage: View {
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults)
    private var backgroundHex = Appearance.defaultBackground

    var body: some View {
        WalkthroughPage(
            symbol: "photo.on.rectangle",
            title: "Set your wallpaper",
            message: "iPhone doesn't let apps change your wallpaper, so Ebb saves a matching one to Photos and shows you how to set it. It takes about 20 seconds."
        ) {
            WallpaperSaveFlow(background: HexColor(hex: backgroundHex) ?? HexColor(red: 0, green: 0, blue: 0))
            Note(text: "If the wallpaper editor offers Depth or a zoom, turn them off so the color matches the widgets exactly.")
        }
    }
}

private struct WidgetsPage: View {
    var body: some View {
        WalkthroughPage(
            symbol: "square.grid.2x2",
            title: "Add Ebb widgets",
            message: "Widgets open your apps directly, with no stop in Ebb in between. Apps with a mindful pause are the exception: they go through Ebb so you get a moment to think."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                StepRow(number: 1, title: "Clear a page",
                        detail: "Long-press the Home Screen, tap the page dots at the bottom, and keep only one page checked. Your apps stay safe in the App Library.")
                StepRow(number: 2, title: "Add the Apps widget",
                        detail: "Tap Edit › Add Widget, search for Ebb, and add the medium or large Apps widget. It shows your first app widget.")
                StepRow(number: 3, title: "Pick apps per widget",
                        detail: "Long-press a widget › Edit Widget to choose its apps, alignment, text size, and clock. Stack two medium widgets for more room.")
                StepRow(number: 4, title: "Add a few extras",
                        detail: "Clock, Year, Life, and Time Saved come in every size, and a Spacer leaves calm, empty room between them.")
                StepRow(number: 5, title: "Empty the Dock",
                        detail: "Drag apps out of the Dock, or keep only Ebb there.")
            }
            Note(text: "Tip: in Home Screen edit mode, tap Edit › Customize › Large to hide app labels, or choose Dark for darker icons.")
        }
    }
}

private struct PausePage: View {
    @Environment(LauncherStore.self) private var store

    var body: some View {
        WalkthroughPage(
            symbol: "hourglass",
            title: "A breath before scrolling",
            message: "Apps with a mindful pause show a short breathing countdown and ask what you're opening them for. Backing out counts as time given back in Insights."
        ) {
            if store.targets.isEmpty {
                Text("Add apps first, then choose which ones get a pause.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.library(matching: "")) { target in
                        Toggle(target.name, isOn: Binding(
                            get: { target.isMindful },
                            set: { newValue in
                                var updated = target
                                updated.isMindful = newValue
                                store.update(updated)
                            }
                        ))
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            Note(text: "Social apps are turned on for you. You can change this anytime in Apps.")
        }
    }
}

private struct FocusPage: View {
    @Environment(FocusManager.self) private var focus

    var body: some View {
        WalkthroughPage(
            symbol: "moon",
            title: "Block when it matters",
            message: "Ebb can use Screen Time to block apps during focus sessions, overnight, or after a daily limit. Apple keeps your choices private: Ebb never sees which apps you pick."
        ) {
            if focus.isAuthorized {
                Label("Screen Time is allowed. Set up blocking from the moon icon on Ebb's home.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await focus.requestAuthorization() }
                } label: {
                    Text("Allow Screen Time")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                if let error = focus.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Note(text: "This step is optional. You can skip it and turn it on later in Settings › Focus & blocking.")
        }
    }
}

private struct DonePage: View {
    var body: some View {
        WalkthroughPage(
            symbol: "checkmark.circle",
            title: "You're set",
            message: "From here on, your Home Screen widgets are how you use Ebb. This app is where you set them up and check in."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Label("The checklist on Ebb's main screen tracks anything left to set up.", systemImage: "checklist")
                Label("Change apps, colors, and widget style anytime.", systemImage: "slider.horizontal.3")
                Label("Focus is where you set work time and blocking.", systemImage: "moon")
                Label("Replay this walkthrough from Settings.", systemImage: "arrow.counterclockwise")
            }
            .font(.callout)
        }
    }
}

/// The widget setup steps on their own, for Settings.
struct SetupGuideView: View {
    var body: some View {
        List {
            Section {
                Text("Apple doesn't let apps replace the Home Screen, so Ebb uses widgets in the same color as your wallpaper. Here's the full setup.")
                    .foregroundStyle(.secondary)
            }
            Section("Wallpaper") {
                StepRow(number: 1, title: "Save a wallpaper", detail: "Settings › Colors & wallpaper › Save wallpaper to Photos.")
                StepRow(number: 2, title: "Set it", detail: "In Photos, open the wallpaper and tap Share › Use as Wallpaper › Add › Set as Wallpaper Pair.")
            }
            Section("Widgets") {
                StepRow(number: 3, title: "Clear a page", detail: "Long-press the Home Screen, tap the page dots, and keep one page checked.")
                StepRow(number: 4, title: "Add the Apps widget", detail: "Edit › Add Widget › Ebb › Apps (large).")
                StepRow(number: 5, title: "Configure it", detail: "Long-press › Edit Widget to choose apps, alignment, text size, and clock.")
                StepRow(number: 6, title: "Add extras", detail: "Clock, Year, Life, and Time Saved widgets, plus Open Ebb on the Lock Screen.")
            }
            Section("Optional") {
                StepRow(number: 7, title: "Grayscale", detail: "Settings › Accessibility › Display & Text Size › Color Filters › Grayscale.")
                StepRow(number: 8, title: "Empty the Dock", detail: "Drag apps out, or keep only Ebb.")
            }
        }
        .navigationTitle("Home Screen setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}
