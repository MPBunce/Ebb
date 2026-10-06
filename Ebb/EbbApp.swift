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
                .task { PlusStore.shared.start(launcher: store) }
                #if DEBUG
                .task { Self.applyDebugScene() }
                #endif
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

    #if DEBUG
    /// Development builds: `EBB_SCENE=aurora EBB_ICONS=large` applies a scene at launch and
    /// saves its wallpaper to Photos, for testing scenes without tapping through Ebb.
    @MainActor
    private static func applyDebugScene() {
        let env = ProcessInfo.processInfo.environment
        // EBB_MEASURE=start, EBB_MEASURE_FILE / EBB_MATCH_FILE = screenshot paths.
        if env["EBB_MEASURE"] == "start" { SceneRenderer.startMeasuring() }
        if let path = env["EBB_MATCH_FILE"], let image = UIImage(contentsOfFile: path) {
            print("EBB match:", SceneRenderer.matchScreenshot(image, layout: IconLayout.current))
        }
        if let path = env["EBB_MEASURE_FILE"], let image = UIImage(contentsOfFile: path) {
            print("EBB measure:", SceneRenderer.measure(image), WidgetPlacement.frames)
        }
        guard let raw = env["EBB_SCENE"], let scene = SceneWallpaper(rawValue: raw) else { return }
        let layout = env["EBB_ICONS"].flatMap(IconLayout.init(rawValue:)) ?? IconLayout.current
        let image = SceneRenderer.apply(scene, layout: layout)
        Task { _ = await SceneRenderer.saveToPhotos(image, name: scene.name) }
    }
    #endif
}
