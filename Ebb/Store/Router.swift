//
//  Router.swift
//  Ebb
//

import Foundation
import ManagedSettings
import Observation

/// Sheets presented over the home screen.
enum HomeSheet: String, Identifiable {
    case settings, focus, insights
    var id: Self { self }
}

/// A blocked app the user wants to breathe through before using.
struct BreatherRequest: Identifiable {
    let id = UUID()
    let token: ApplicationToken
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
            sheet = nil
        case .focus:
            sheet = .focus
        case .launch(let id):
            guard sheet != nil else {
                store.requestLaunch(id: id)
                return
            }
            // Let the sheet finish dismissing before a mindful pause covers the screen.
            sheet = nil
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                store.requestLaunch(id: id)
            }
        }
    }
}
