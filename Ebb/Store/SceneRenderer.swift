//
//  SceneRenderer.swift
//  Ebb
//
//  Draws the scene wallpapers at the screen's exact size, and cuts the slice behind every
//  spot a widget can occupy so the widgets blend into the picture.
//

import Photos
import UIKit
import WidgetKit

enum SceneRenderer {
    // MARK: Applying

    /// Renders `scene` for this iPhone, saves the widget slices, and makes it the active look.
    @discardableResult
    static func apply(_ scene: SceneWallpaper, layout: IconLayout) -> UIImage {
        let (points, scale) = screenSize()
        let image = render(scene, size: CGSize(width: points.width * scale, height: points.height * scale))
        writeSlices(of: image, scale: scale, points: points, layout: layout)
        SceneWallpaper.current = scene
        IconLayout.current = layout
        AppGroup.defaults.set(scene.baseHex, forKey: AppGroup.Key.backgroundHex)
        AppGroup.defaults.set(scene.textHex, forKey: AppGroup.Key.textHex)
        WidgetCenter.shared.reloadAllTimelines()
        return image
    }

    /// Back to a flat color.
    static func clear() {
        SceneWallpaper.current = nil
        if let folder = SceneSlices.folder { try? FileManager.default.removeItem(at: folder) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Re-cuts the slices, e.g. after changing the icon size.
    static func refreshSlices() {
        guard let scene = SceneWallpaper.current else { return }
        apply(scene, layout: IconLayout.current)
    }

    static func screenSize() -> (points: CGSize, scale: CGFloat) {
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
        let points = screen?.bounds.size ?? CGSize(width: 402, height: 874)
        return (points, screen?.scale ?? 3)
    }

    private static func writeSlices(of image: UIImage, scale: CGFloat, points: CGSize, layout: IconLayout) {
        guard let folder = SceneSlices.folder, let cg = image.cgImage else { return }
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let grid = HomeGrid.for(screenWidth: points.width, height: points.height, layout: layout)
        for size in WidgetSize.allCases {
            for row in size.startRows {
                for right in size == .small ? [false, true] : [false] {
                    let spot = WidgetSpot(row: row, right: right)
                    let frame = grid.frame(size, at: spot)
                    let pixels = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                                        width: frame.width * scale, height: frame.height * scale).integral
                    guard let slice = cg.cropping(to: pixels),
                          let data = UIImage(cgImage: slice).pngData(),
                          let url = SceneSlices.url(for: size, at: spot) else { continue }
                    try? data.write(to: url)
                }
            }
        }
    }

    static func saveToPhotos(_ image: UIImage, name: String) async -> Wallpaper.SaveResult {
        guard let png = image.pngData() else { return .failed("The wallpaper image couldn't be created.") }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "Ebb \(name).png"
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: options)
            }
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Drawing

    static func render(_ scene: SceneWallpaper, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let painter = Painter(cg: context.cgContext, size: size)
            switch scene {
            case .night: painter.night()
            case .dusk: painter.dusk()
            case .aurora: painter.aurora()
            case .forest: painter.forest()
            case .dunes: painter.dunes()
            }
        }
    }

    /// A small preview of a scene for the picker.
    static func thumbnail(_ scene: SceneWallpaper) -> UIImage {
        render(scene, size: CGSize(width: 240, height: 520))
    }
}

/// Seeded random numbers, so a scene looks the same every time it's drawn.
private struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

private struct Painter {
    let cg: CGContext
    let size: CGSize
    var w: CGFloat { size.width }
    var h: CGFloat { size.height }

    private func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
        (HexColor(hex: hex) ?? HexColor(red: 0, green: 0, blue: 0)).uiColor.withAlphaComponent(alpha).cgColor
    }

    private func verticalGradient(_ stops: [(Double, String)]) {
        let colors = stops.map { color($0.1) } as CFArray
        let locations = stops.map { CGFloat($0.0) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors, locations: locations) else { return }
        cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    }

    private func glow(at center: CGPoint, radius: CGFloat, hex: String, alpha: CGFloat) {
        let colors = [color(hex, alpha), color(hex, 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors, locations: [0, 1]) else { return }
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                              endRadius: radius, options: [])
    }

    private func disc(at center: CGPoint, radius: CGFloat, hex: String, alpha: CGFloat = 1) {
        cg.setFillColor(color(hex, alpha))
        cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func stars(count: Int, seed: UInt64, maxY: CGFloat, brightness: ClosedRange<Double> = 0.25...0.9) {
        var rng = SeededRandom(seed)
        for _ in 0..<count {
            let x = rng.range(0, Double(w))
            let y = rng.range(0, Double(maxY)) * rng.range(0.4, 1)
            let r = rng.range(0.5, 1.7) * Double(w) / 1179
            let a = rng.range(brightness.lowerBound, brightness.upperBound) * (1 - y / Double(maxY) * 0.6)
            disc(at: CGPoint(x: x, y: y), radius: r, hex: "#FFFFFF", alpha: a)
            if r > 1.5 * Double(w) / 1179 { glow(at: CGPoint(x: x, y: y), radius: r * 5, hex: "#C9D6FF", alpha: a * 0.35) }
        }
    }

    /// A soft mountain ridge from `base` (fraction of height), filled to the bottom.
    private func ridge(base: Double, amplitude: Double, segments: Int, seed: UInt64, hex: String, alpha: CGFloat = 1) {
        var rng = SeededRandom(seed)
        var points: [CGPoint] = []
        var level = 0.0
        for i in 0...segments {
            level = level * 0.55 + rng.range(-1, 1)
            points.append(CGPoint(x: w * CGFloat(i) / CGFloat(segments),
                                  y: h * CGFloat(base) - h * CGFloat(amplitude) * CGFloat(level)))
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: points[0])
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            path.addQuadCurve(to: mid, control: points[i - 1])
        }
        path.addLine(to: points.last!)
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        cg.addPath(path)
        cg.setFillColor(color(hex, alpha))
        cg.fillPath()
    }

    /// A row of pine trees standing on a soft hill.
    private func pines(base: Double, height: Double, seed: UInt64, hex: String) {
        var rng = SeededRandom(seed)
        cg.setFillColor(color(hex))
        var x = -Double(w) * 0.02
        let path = CGMutablePath()
        while x < Double(w) * 1.02 {
            let treeH = Double(h) * height * rng.range(0.55, 1.15)
            let treeW = treeH * rng.range(0.28, 0.4)
            let ground = Double(h) * base + sin(x / Double(w) * 5 + Double(seed)) * Double(h) * 0.008
            path.move(to: CGPoint(x: x - treeW / 2, y: ground))
            path.addLine(to: CGPoint(x: x, y: ground - treeH))
            path.addLine(to: CGPoint(x: x + treeW / 2, y: ground))
            path.closeSubpath()
            x += treeW * rng.range(0.45, 0.8)
        }
        cg.addPath(path)
        cg.fillPath()
        cg.fill(CGRect(x: 0, y: h * CGFloat(base) - h * 0.006, width: w, height: h * (1 - CGFloat(base)) + h * 0.01))
    }

    private func band(y: Double, height: Double, hex: String, alpha: CGFloat) {
        let colors = [color(hex, 0), color(hex, alpha), color(hex, 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors, locations: [0, 0.5, 1]) else { return }
        let top = h * CGFloat(y - height / 2)
        cg.saveGState()
        cg.clip(to: CGRect(x: 0, y: top, width: w, height: h * CGFloat(height)))
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top),
                              end: CGPoint(x: 0, y: top + h * CGFloat(height)), options: [])
        cg.restoreGState()
    }

    // MARK: Scenes

    func night() {
        verticalGradient([(0, "#04060F"), (0.45, "#0F1735"), (0.8, "#22295A"), (1, "#2E3368")])
        stars(count: 260, seed: 7, maxY: h * 0.82)
        let moon = CGPoint(x: w * 0.74, y: h * 0.17)
        glow(at: moon, radius: w * 0.42, hex: "#9FB2FF", alpha: 0.18)
        glow(at: moon, radius: w * 0.16, hex: "#F7EEDB", alpha: 0.35)
        disc(at: moon, radius: w * 0.075, hex: "#F4ECDA")
        disc(at: CGPoint(x: moon.x - w * 0.02, y: moon.y - w * 0.015), radius: w * 0.016, hex: "#D9CFBC", alpha: 0.45)
        disc(at: CGPoint(x: moon.x + w * 0.025, y: moon.y + w * 0.02), radius: w * 0.011, hex: "#D9CFBC", alpha: 0.4)
        ridge(base: 0.84, amplitude: 0.035, segments: 14, seed: 3, hex: "#1A1F45")
        ridge(base: 0.9, amplitude: 0.03, segments: 18, seed: 5, hex: "#0B0E26")
    }

    func dusk() {
        verticalGradient([(0, "#1F1430"), (0.3, "#4E2A5C"), (0.55, "#B3566A"), (0.7, "#EE9A62"), (0.78, "#F7C78C")])
        let sun = CGPoint(x: w * 0.5, y: h * 0.74)
        glow(at: sun, radius: w * 0.6, hex: "#FFC98C", alpha: 0.35)
        disc(at: sun, radius: w * 0.09, hex: "#FFE3B5", alpha: 0.95)
        stars(count: 70, seed: 11, maxY: h * 0.35, brightness: 0.15...0.5)
        ridge(base: 0.74, amplitude: 0.04, segments: 10, seed: 21, hex: "#9A4E73")
        ridge(base: 0.79, amplitude: 0.035, segments: 13, seed: 22, hex: "#673462")
        ridge(base: 0.85, amplitude: 0.03, segments: 16, seed: 23, hex: "#3F214C")
        ridge(base: 0.92, amplitude: 0.025, segments: 20, seed: 24, hex: "#1E1029")
    }

    func aurora() {
        verticalGradient([(0, "#010409"), (0.5, "#05141F"), (1, "#0A2131")])
        stars(count: 180, seed: 31, maxY: h * 0.8)
        // Curtains of light: vertical strokes that fade upward from a wandering base.
        let curtains: [(base: Double, reach: Double, phase: Double, hex: String, alpha: CGFloat)] = [
            (0.46, 0.26, 0.0, "#3CF2A5", 0.42),
            (0.58, 0.22, 2.1, "#2FD0C9", 0.32),
            (0.38, 0.18, 4.0, "#9B6CF6", 0.22),
        ]
        for curtain in curtains {
            let step = max(w / 360, 1)
            var x: CGFloat = 0
            while x < w {
                let t = Double(x / w)
                let baseY = h * CGFloat(curtain.base + 0.06 * sin(t * 6 + curtain.phase) + 0.03 * sin(t * 15 + curtain.phase))
                let reach = h * CGFloat(curtain.reach * (0.6 + 0.4 * sin(t * 9 + curtain.phase * 1.7)))
                let colors = [color(curtain.hex, curtain.alpha), color(curtain.hex, 0)] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                             colors: colors, locations: [0, 1]) {
                    cg.saveGState()
                    cg.clip(to: CGRect(x: x, y: baseY - reach, width: step + 1, height: reach))
                    cg.drawLinearGradient(gradient, start: CGPoint(x: x, y: baseY),
                                          end: CGPoint(x: x, y: baseY - reach), options: [])
                    cg.restoreGState()
                }
                x += step
            }
            glow(at: CGPoint(x: w * 0.5, y: h * CGFloat(curtain.base)), radius: w * 0.7, hex: curtain.hex, alpha: curtain.alpha * 0.25)
        }
        ridge(base: 0.88, amplitude: 0.04, segments: 16, seed: 37, hex: "#03080D")
    }

    func forest() {
        verticalGradient([(0, "#132422"), (0.35, "#2C4842"), (0.6, "#6F8E84"), (0.72, "#A9BEB4")])
        glow(at: CGPoint(x: w * 0.3, y: h * 0.2), radius: w * 0.5, hex: "#E7F0E9", alpha: 0.12)
        pines(base: 0.68, height: 0.07, seed: 41, hex: "#7D998E")
        band(y: 0.69, height: 0.06, hex: "#DCE6E0", alpha: 0.35)
        pines(base: 0.75, height: 0.09, seed: 42, hex: "#55736A")
        band(y: 0.76, height: 0.05, hex: "#DCE6E0", alpha: 0.25)
        pines(base: 0.84, height: 0.12, seed: 43, hex: "#2F4A42")
        pines(base: 0.94, height: 0.15, seed: 44, hex: "#15241F")
    }

    func dunes() {
        verticalGradient([(0, "#F8EAD6"), (0.5, "#F3D9B2"), (0.7, "#EEC795")])
        let sun = CGPoint(x: w * 0.28, y: h * 0.16)
        glow(at: sun, radius: w * 0.5, hex: "#FFF6E6", alpha: 0.6)
        disc(at: sun, radius: w * 0.06, hex: "#FFF8EC", alpha: 0.9)
        ridge(base: 0.72, amplitude: 0.025, segments: 5, seed: 51, hex: "#EBC08B")
        ridge(base: 0.79, amplitude: 0.03, segments: 6, seed: 52, hex: "#E2AF77")
        ridge(base: 0.87, amplitude: 0.03, segments: 7, seed: 53, hex: "#D69C64")
        ridge(base: 0.94, amplitude: 0.025, segments: 8, seed: 54, hex: "#C98A55")
    }
}
