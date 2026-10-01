//
//  EbbApp.swift
//  Ebb
//
//  Created by Matthew Bunce on 2026-10-01.
//

import SwiftUI
import UIKit

@main
struct EbbApp: App {
    @State private var store = LauncherStore()
    @State private var focus = FocusManager()
    @State private var router = Router()
    @State private var icons = AppIcons()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(focus)
                .environment(router)
                .environment(icons)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) {
                        router.handle(link, store: store)
                    } else if url.scheme != DeepLink.scheme {
                        // A widget link to another app that iOS routed through Ebb: pass it on.
                        UIApplication.shared.open(url)
                    }
                }
        }
    }
}
