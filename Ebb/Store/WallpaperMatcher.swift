//
//  WallpaperMatcher.swift
//  Ebb
//
//  iOS doesn't draw a photo wallpaper and a widget background identically, so a
//  wallpaper in the exact widget color can still show faint widget edges, especially
//  on light colors. This measures both in a Home Screen screenshot and works out a
//  widget color that renders the same as the wallpaper. Tuning the widgets (not the
//  wallpaper) works for every color, even white, which can't be brightened further.
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
        /// No large area close to the chosen color: the Ebb wallpaper isn't showing.
        case noWallpaper
    }

    /// Finds how the wallpaper and widgets render in a Home Screen screenshot.
    /// - Parameters:
    ///   - base: the background color chosen in Ebb (the wallpaper was saved in it).
    ///   - widgetColor: the color widgets currently draw with.
    static func measure(_ image: CGImage, base: HexColor, widgetColor: HexColor) -> Result<Measurement, Failure> {
        let pixels = samplePixels(image)
        guard !pixels.isEmpty else { return .failure(.noWallpaper) }

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

        // The wallpaper fills most of the screen, in roughly the chosen color.
        guard let wallpaper = clusters.first(where: { $0.count >= minimumArea && distance($0.color, base) <= 40 }) else {
            return .failure(.noWallpaper)
        }
        // An Ebb widget, if one is showing, renders close to its own color.
        let widget = clusters
            .filter { $0.count >= minimumArea && distance($0.color, wallpaper.color) > 1.5 && distance($0.color, widgetColor) <= 12 }
            .min { distance($0.color, widgetColor) < distance($1.color, widgetColor) }
        // With no widget visible, assume widgets draw their color faithfully.
        return .success(Measurement(widget: widget?.color ?? widgetColor, wallpaper: wallpaper.color))
    }

    /// The widget color that will render the same as the wallpaper, given the color
    /// widgets currently use and how they measured.
    static func widgetColor(current: HexColor, measurement: Measurement) -> HexColor {
        func channel(_ current: Double, _ widget: Double, _ wallpaper: Double) -> Double {
            // Rendering mostly scales colors, so scale by the ratio; fall back to an
            // offset for near-black channels where a ratio is unstable.
            let adjusted = widget > 0.05 ? current * wallpaper / widget : current + (wallpaper - widget)
            return min(max(adjusted, 0), 1)
        }
        return HexColor(
            red: channel(current.red, measurement.widget.red, measurement.wallpaper.red),
            green: channel(current.green, measurement.widget.green, measurement.wallpaper.green),
            blue: channel(current.blue, measurement.widget.blue, measurement.wallpaper.blue)
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
