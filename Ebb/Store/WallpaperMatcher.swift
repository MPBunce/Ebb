//
//  WallpaperMatcher.swift
//  Ebb
//
//  iOS doesn't draw a photo wallpaper and a widget background identically, so a
//  wallpaper in the exact widget color can still show faint widget edges, especially
//  on light colors. This measures both in a Home Screen screenshot and works out a
//  wallpaper color that renders the same as the widgets.
//

import CoreGraphics
import Foundation

struct WallpaperMatcher {
    struct Measurement: Equatable {
        /// How the widgets actually render.
        var widget: HexColor
        /// How the current wallpaper actually renders.
        var wallpaper: HexColor

        /// 0 means a perfect match. Roughly, 1 is one step of 255 in the most different channel.
        var difference: Double {
            max(abs(widget.red - wallpaper.red), abs(widget.green - wallpaper.green), abs(widget.blue - wallpaper.blue)) * 255
        }
    }

    enum Failure: Error, Equatable {
        /// No area close to the widget color was found.
        case noWidget
        /// The widget color was found but no wallpaper of a similar color around it.
        case noWallpaper
    }

    /// Finds the widget and wallpaper colors in a screenshot.
    /// - Parameter target: the widget color set in Ebb.
    static func measure(_ image: CGImage, target: HexColor) -> Result<Measurement, Failure> {
        let pixels = samplePixels(image)
        guard !pixels.isEmpty else { return .failure(.noWidget) }

        // Bucket colors (2 values per bucket per channel) and count them.
        var counts: [Int: (count: Int, sum: (Double, Double, Double))] = [:]
        for (r, g, b) in pixels {
            let key = (Int(r) / 2) << 16 | (Int(g) / 2) << 8 | (Int(b) / 2)
            var entry = counts[key] ?? (0, (0, 0, 0))
            entry.count += 1
            entry.sum = (entry.sum.0 + Double(r), entry.sum.1 + Double(g), entry.sum.2 + Double(b))
            counts[key] = entry
        }
        let clusters = counts.values
            .map { (count: $0.count, color: HexColor(red: $0.sum.0 / Double($0.count) / 255,
                                                     green: $0.sum.1 / Double($0.count) / 255,
                                                     blue: $0.sum.2 / Double($0.count) / 255)) }
            .sorted { $0.count > $1.count }

        let minimumArea = max(pixels.count / 100, 20)

        // The widget renders very close to the color Ebb asked for: take the large area
        // closest to it (the wallpaper may be close too, and bigger).
        guard let widget = clusters
            .filter({ $0.count >= minimumArea && distance($0.color, target) <= 12 })
            .min(by: { distance($0.color, target) < distance($1.color, target) })
        else {
            return .failure(.noWidget)
        }
        // The wallpaper is the next big area of a similar, but not identical, color.
        // If it's identical, the match is already perfect.
        let wallpaper = clusters.first(where: {
            $0.count >= minimumArea && distance($0.color, widget.color) > 1.5 && distance($0.color, target) <= 40
        })
        guard let wallpaper else {
            // Nothing similar besides the widget itself: either a perfect match or no wallpaper visible.
            let hasOtherLargeArea = clusters.contains { $0.count >= minimumArea * 5 && distance($0.color, widget.color) > 40 }
            return hasOtherLargeArea ? .failure(.noWallpaper) : .success(Measurement(widget: widget.color, wallpaper: widget.color))
        }
        return .success(Measurement(widget: widget.color, wallpaper: wallpaper.color))
    }

    /// The wallpaper color to save so it renders like the widget, given the color the
    /// wallpaper was saved in and how it measured.
    static func corrected(saved: HexColor, measurement: Measurement) -> HexColor {
        func channel(_ saved: Double, _ widget: Double, _ wallpaper: Double) -> Double {
            // Wallpaper rendering mostly scales colors, so scale by the ratio; fall back to an
            // offset for near-black channels where a ratio is unstable.
            let adjusted = wallpaper > 0.05 ? saved * widget / wallpaper : saved + (widget - wallpaper)
            return min(max(adjusted, 0), 1)
        }
        return HexColor(
            red: channel(saved.red, measurement.widget.red, measurement.wallpaper.red),
            green: channel(saved.green, measurement.widget.green, measurement.wallpaper.green),
            blue: channel(saved.blue, measurement.widget.blue, measurement.wallpaper.blue)
        )
    }

    /// Nudges a color lighter (positive) or darker (negative) by `steps` of 1/255.
    static func nudge(_ color: HexColor, steps: Int) -> HexColor {
        let delta = Double(steps) / 255
        return HexColor(red: min(max(color.red + delta, 0), 1),
                        green: min(max(color.green + delta, 0), 1),
                        blue: min(max(color.blue + delta, 0), 1))
    }

    /// Distance in 0–255 units: the largest per-channel difference.
    private static func distance(_ a: HexColor, _ b: HexColor) -> Double {
        max(abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue)) * 255
    }

    /// Draws the image small, in sRGB, and returns its pixels.
    private static func samplePixels(_ image: CGImage) -> [(UInt8, UInt8, UInt8)] {
        let width = 150
        let height = max(Int(Double(image.height) / Double(max(image.width, 1)) * Double(width)), 1)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return [] }
        // No smoothing, so widget edges don't blend into the wallpaper.
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: data.count, by: 4).map { (data[$0], data[$0 + 1], data[$0 + 2]) }
    }
}

/// Wallpaper colors tuned to match the widget color on this iPhone, keyed by widget color.
enum WallpaperTuning {
    private static let key = "wallpaperTuning"

    static func wallpaperColor(for background: HexColor) -> HexColor {
        let stored = AppGroup.defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return stored[background.hex].flatMap(HexColor.init(hex:)) ?? background
    }

    static func setWallpaperColor(_ color: HexColor?, for background: HexColor) {
        var stored = AppGroup.defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[background.hex] = color?.hex
        AppGroup.defaults.set(stored, forKey: key)
    }
}
