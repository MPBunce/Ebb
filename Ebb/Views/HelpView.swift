//
//  HelpView.swift
//  Ebb
//
//  Help & Setup: the setup checklist, guides, and answers to common questions, in one place.
//

import SwiftUI
import WidgetKit

struct HelpView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(FocusManager.self) private var focus
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults) private var backgroundHex: String?
    @AppStorage(AppGroup.Key.wallpaperSet, store: AppGroup.defaults) private var wallpaperSet = false

    @State private var widgetsAdded = false
    @State private var showWalkthrough = false
    @State private var query = ""

    private var checklist: SetupChecklist {
        SetupChecklist(store: store, focus: focus, backgroundHex: backgroundHex,
                       wallpaperSet: wallpaperSet, widgetsAdded: widgetsAdded)
    }

    private var questions: [CommonQuestion] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return CommonQuestion.all }
        return CommonQuestion.all.filter {
            $0.question.localizedCaseInsensitiveContains(trimmed) || $0.answer.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        List {
            if query.isEmpty {
                checklistSection
                guidesSection
            }

            Section {
                ForEach(questions) { item in
                    DisclosureGroup {
                        Text(.init(item.answer))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                    } label: {
                        Label(item.question, systemImage: item.icon)
                    }
                }
                if questions.isEmpty {
                    Text("No questions match \u{201C}\(query)\u{201D}.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Common questions")
            }
        }
        .navigationTitle("Help & Setup")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search questions")
        .task { widgetsAdded = await SetupChecklist.isAppsWidgetAdded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { widgetsAdded = await SetupChecklist.isAppsWidgetAdded() } }
        }
        .fullScreenCover(isPresented: $showWalkthrough) {
            OnboardingView(isReplay: true)
                .ebbColorScheme()
        }
    }

    private var checklistSection: some View {
        let checklist = checklist
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(checklist.requiredDone), total: Double(checklist.requiredTotal))
                    .tint(.green)
                Text(checklist.isSetUp ? "All set" : "\(checklist.requiredDone) of \(checklist.requiredTotal) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            ForEach(Array(checklist.steps.enumerated()), id: \.element.id) { index, step in
                switch step.id {
                case .screenTime:
                    Button { router.sheet = .focus } label: {
                        SetupStepRow(number: index + 1, step: step, showsChevron: true)
                    }
                default:
                    NavigationLink {
                        destination(for: step.id)
                    } label: {
                        SetupStepRow(number: index + 1, step: step)
                    }
                }
            }
        } header: {
            Text("Setup checklist")
        } footer: {
            Text("iPhone doesn't let apps replace the Home Screen, so Ebb builds yours from widgets on a matching wallpaper.")
        }
    }

    private var guidesSection: some View {
        Section {
            Button { showWalkthrough = true } label: {
                SettingsRow(icon: "sparkles", tint: .indigo, title: "Walkthrough",
                            subtitle: "Step-by-step setup with explanations", showsChevron: true)
            }
            NavigationLink { SetupGuideView() } label: {
                SettingsRow(icon: "iphone", tint: .gray, title: "Home Screen setup",
                            subtitle: "Wallpaper and widget steps for reference")
            }
            NavigationLink { WidgetsGuideView() } label: {
                SettingsRow(icon: "square.grid.2x2.fill", tint: .blue, title: "Adding widgets",
                            subtitle: "Put Ebb's widgets on your Home Screen and Lock Screen")
            }
        } header: {
            Text("Guides")
        }
    }

    @ViewBuilder
    private func destination(for step: SetupStep.ID) -> some View {
        switch step {
        case .apps, .widgets, .screenTime: WidgetsView()
        case .colors: AppearanceView()
        case .wallpaper: WallpaperStepView()
        }
    }
}

// MARK: - Setup checklist

struct SetupStep: Identifiable {
    enum ID { case apps, colors, wallpaper, widgets, screenTime }

    let id: ID
    let title: String
    let detail: String
    let isDone: Bool
    var isOptional = false
}

/// What's left to set up, shared by Help & Setup and the main screen's progress row.
struct SetupChecklist {
    let steps: [SetupStep]

    init(store: LauncherStore, focus: FocusManager, backgroundHex: String?, wallpaperSet: Bool, widgetsAdded: Bool) {
        steps = [
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

    var requiredDone: Int { steps.filter { !$0.isOptional && $0.isDone }.count }
    var requiredTotal: Int { steps.filter { !$0.isOptional }.count }
    var isSetUp: Bool { requiredDone == requiredTotal }

    static func isAppsWidgetAdded() async -> Bool {
        let configurations = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        return configurations.contains { $0.kind == "EbbLauncher.apps" }
    }
}

struct SetupStepRow: View {
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

struct WallpaperStepView: View {
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

// MARK: - Common questions

struct CommonQuestion: Identifiable {
    let icon: String
    let question: String
    /// Markdown.
    let answer: String
    var id: String { question }

    static let all: [CommonQuestion] = [
        CommonQuestion(
            icon: "arrow.up.forward.app",
            question: "Why does iPhone ask to open an app the first time?",
            answer: "Widget taps go through Ebb, which then opens your app. iPhone asks once per app (\u{201C}Ebb wants to open…\u{201D}). Tap **Open** and it won't ask again for that app."
        ),
        CommonQuestion(
            icon: "magnifyingglass",
            question: "Why isn't one of my apps in Find apps?",
            answer: "iPhone only lets an app check for a limited list of other apps, so Ebb can detect about 60 popular ones. For anything else, search for it in **Add apps**. Results from the App Store are included. You can also add it by link or with a Shortcut, which can open any app."
        ),
        CommonQuestion(
            icon: "square.dashed",
            question: "I can see the edges of my widgets.",
            answer: "The widgets and wallpaper need the same color. Save Ebb's wallpaper from **Colors & wallpaper** and set it on your Home Screen. In light mode, use **Match widgets to my wallpaper** to fine-tune. If the wallpaper looks dimmed in dark mode, turn off **Dark Appearance Dims Wallpaper** in iPhone Settings › Wallpaper."
        ),
        CommonQuestion(
            icon: "square.grid.2x2",
            question: "How do I change which apps a widget shows?",
            answer: "Long-press the widget › **Edit Widget** › **App Widget**, and pick which of your app widgets it shows. Edit the apps themselves in Ebb under **Widgets**."
        ),
        CommonQuestion(
            icon: "rectangle.stack",
            question: "How do I hide my other apps?",
            answer: "Long-press the Home Screen, tap the page dots at the bottom, and uncheck the pages you don't want. Your apps stay in the App Library (swipe left past your last page), so nothing is deleted."
        ),
        CommonQuestion(
            icon: "clock",
            question: "Why is the clock widget sometimes a little behind?",
            answer: "iPhone decides when widgets redraw. Ebb gives the clock a new time every minute. Usually it's exact, but iPhone may pause updates briefly in Low Power Mode or while the screen is off."
        ),
        CommonQuestion(
            icon: "cloud.sun",
            question: "How does the Weather widget know where I am?",
            answer: "Turn on location in **Widgets › Weather widget** and choose **While Using the App or Widgets**. The widget then follows you. Otherwise it uses the last place Ebb saw. Your location is only sent to Apple Weather."
        ),
        CommonQuestion(
            icon: "hand.raised",
            question: "How does blocking work? Can Ebb see what I use?",
            answer: "Ebb uses Apple's Screen Time. You pick apps in Apple's own picker, and Ebb only gets private tokens, so it can block those apps without learning which ones they are."
        ),
        CommonQuestion(
            icon: "wind",
            question: "Why does the block screen send a notification?",
            answer: "iPhone doesn't let the block screen open apps. When you tap **Take a breath**, Ebb sends a notification. Tap it to start the breather, and the app unlocks for a while afterwards."
        ),
        CommonQuestion(
            icon: "leaf",
            question: "How is Time Saved counted?",
            answer: "iPhone doesn't share real Screen Time totals with apps, so it's an estimate: a few minutes (you choose how many in **Widgets**) for each app you let go during a mindful pause, plus your time in focus sessions."
        ),
        CommonQuestion(
            icon: "hourglass",
            question: "Where do the Life widget's numbers come from?",
            answer: "US life expectancy averages from the CDC (2023), based on the birthday and sex you enter in **Widgets**. They're averages, not predictions, and if you outlive one the widget counts your extra time with a +."
        ),
        CommonQuestion(
            icon: "sparkles",
            question: "What's in Ebb Plus?",
            answer: "A one-time purchase, not a subscription. It adds up to \(EbbPlus.plusAppWidgets) app widgets (\(EbbPlus.freeAppWidgets) are free), extra clock styles, and the large Time & Life widget for the Today View. Everything else is free."
        ),
        CommonQuestion(
            icon: "lock.shield",
            question: "What data does Ebb collect?",
            answer: "None. Your apps, settings, age, and history stay on this iPhone. Ebb only goes online to fetch app icons from the App Store and, if you use the Weather widget, the forecast from Apple Weather."
        ),
    ]
}
