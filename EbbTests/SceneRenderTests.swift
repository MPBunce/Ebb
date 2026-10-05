//
//  SceneRenderTests.swift
//  EbbTests
//

import Foundation
import Testing
import UIKit
@testable import Ebb

@MainActor
struct SceneRenderTests {
    @Test func everySceneRendersAtFullSize() throws {
        for scene in SceneWallpaper.allCases {
            let image = SceneRenderer.render(scene, size: CGSize(width: 1179, height: 2556))
            #expect(image.size == CGSize(width: 1179, height: 2556))
            if let folder = ProcessInfo.processInfo.environment["EBB_SCENE_PREVIEW_DIR"] {
                try image.pngData()?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(scene.rawValue).png"))
            }
        }
    }

    @Test func gridFramesMatchMeasuredHomeScreens() {
        let grid = HomeGrid.for(screenWidth: 393, height: 852, layout: .small)
        let small = grid.frame(.small, at: WidgetSpot(row: 0, right: true))
        #expect(abs(small.minX - 206.667) < 0.01)
        #expect(abs(small.width - 162) < 0.01)
        let large = HomeGrid.for(screenWidth: 402, height: 874, layout: .large).frame(.large, at: WidgetSpot(row: 0, right: false))
        #expect(abs(large.height - 359.17) < 0.5)
        #expect(abs(large.width - 359.67) < 0.01)
    }
}
