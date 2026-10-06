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
        let env = ProcessInfo.processInfo.environment
        let size = CGSize(width: Double(env["EBB_SCENE_PREVIEW_WIDTH"] ?? "") ?? 1179,
                          height: Double(env["EBB_SCENE_PREVIEW_HEIGHT"] ?? "") ?? 2556)
        for scene in SceneWallpaper.allCases {
            let image = SceneRenderer.render(scene, size: size)
            #expect(image.size == size)
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

    @Test func matchesAnEmptyHomeScreenScreenshot() throws {
        let (points, scale) = SceneRenderer.screenSize()
        let size = CGSize(width: points.width * scale, height: points.height * scale)
        let screenshot = SceneRenderer.render(.forest, size: size)
        let result = SceneRenderer.matchScreenshot(screenshot, layout: .small)
        #expect((try? result.get()) != nil)
        #expect(SceneSlices.fromScreenshot)
        #expect(SceneSlices.data(for: .large, at: WidgetSpot(row: 2, right: false)) != nil)
        SceneRenderer.clear()
        #expect(!SceneSlices.fromScreenshot)
    }

    @Test func rejectsScreenshotsFromOtherScreens() {
        let image = SceneRenderer.render(.dunes, size: CGSize(width: 1000, height: 2000))
        guard case .failure(.wrongSize) = SceneRenderer.matchScreenshot(image, layout: .small) else {
            Issue.record("Expected a wrong-size failure")
            return
        }
    }

    @Test func rejectsScreenshotsWithIconsOnThem() {
        let (points, scale) = SceneRenderer.screenSize()
        let size = CGSize(width: points.width * scale, height: points.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let busy = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.1, green: 0.2, blue: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            // A grid of app-icon-like squares.
            for row in 0..<6 {
                for col in 0..<4 {
                    ctx.fill(CGRect(x: 80 + col * 270, y: 260 + row * 290, width: 190, height: 190))
                }
            }
        }
        guard case .failure(.looksBusy) = SceneRenderer.matchScreenshot(busy, layout: .small) else {
            Issue.record("Expected a busy-screenshot failure")
            return
        }
    }

    @Test func findsMeasuringColorsInAScreenshot() {
        let (points, scale) = SceneRenderer.screenSize()
        let size = CGSize(width: points.width * scale, height: points.height * scale)
        let grid = HomeGrid.for(screenWidth: points.width, height: points.height, layout: .large)
        let frame = grid.frame(.medium, at: WidgetSpot(row: 2, right: false))
        let index = 5
        let c = WidgetPlacement.palette[index]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let shot = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1).setFill()
            let px = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            UIBezierPath(roundedRect: px, cornerRadius: 23 * scale).fill()
        }
        let found = PlacementDetector.frames(in: shot.cgImage!, scale: scale)
        let f = try! #require(found[index])
        #expect(abs(f.minX - frame.minX) < 1.5 && abs(f.minY - frame.minY) < 1.5)
        #expect(abs(f.width - frame.width) < 2 && abs(f.height - frame.height) < 2)
        #expect(found.count == 1)
    }
}
