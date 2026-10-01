//
//  RootView.swift
//  Ebb
//

import SwiftUI

struct RootView: View {
    @Environment(FocusManager.self) private var focus
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PrefKey.hasOnboarded) private var hasOnboarded = false

    var body: some View {
        Group {
            if hasOnboarded {
                DashboardView()
            } else {
                OnboardingView()
            }
        }
        .ebbColorScheme()
        .tint(.primary)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                focus.refresh()
                router.checkForPendingBreather()
            }
        }
    }
}

/// Light or dark system chrome to match the user's background color, so text stays readable.
/// Applied to presented sheets too, which don't pick up changes from the window while open.
private struct EbbColorScheme: ViewModifier {
    @AppStorage(AppGroup.Key.backgroundHex, store: AppGroup.defaults)
    private var backgroundHex = Appearance.defaultBackground

    func body(content: Content) -> some View {
        content.preferredColorScheme((HexColor(hex: backgroundHex)?.isDark ?? true) ? .dark : .light)
    }
}

extension View {
    func ebbColorScheme() -> some View { modifier(EbbColorScheme()) }
}
