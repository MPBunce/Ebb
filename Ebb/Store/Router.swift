//
//  Router.swift
//  Ebb
//

import Foundation
import ManagedSettings
import Observation

/// Sheets presented over the home screen.
enum HomeSheet: String, Identifiable, Codable {
    case settings, focus, insights
    var id: Self { self }
}

/// A blocked app the user wants to breathe through before using.
struct BreatherRequest: Identifiable {
    let id = UUID()
    let token: ApplicationToken
}

/// Screens pushed on the dashboard, restorable across launches.
enum DashboardRoute: String, Codable, Hashable {
    case widgets, apps, colors, wallpaper
}

@Observable
final class Router {
    var sheet: HomeSheet?
    var breather: BreatherRequest?

    /// Shows the breather if the block screen asked for one (via its notification).
    func checkForPendingBreather() {
        guard breather == nil, let token = ShieldController.pendingUnlock else { return }
        ShieldController.pendingUnlock = nil
        guard sheet != nil else {
            breather = BreatherRequest(token: token)
            return
        }
        sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            breather = BreatherRequest(token: token)
        }
    }

    func handle(_ link: DeepLink, store: LauncherStore) {
        switch link {
        case .home:
            // Opening Ebb from a widget picks up where you left off.
            break
        case .focus:
            sheet = .focus
        case .launch(let id):
            // Widget taps come through Ebb so the app always opens (and mindful pauses
            // and Insights see every launch). Wait a moment for Ebb to finish
            // activating; iOS won't open another app before then.
            let isMindful = store.target(id: id)?.isMindful ?? false
            if isMindful { sheet = nil }
            Task {
                try? await Task.sleep(for: .milliseconds(isMindful ? 400 : 150))
                store.requestLaunch(id: id)
            }
        }
    }
}
