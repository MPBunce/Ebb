//
//  Scenes.swift
//  Shared between Ebb and its widgets.
//
//  Scene wallpapers: pictures instead of a flat color. iOS widgets can't be see-through, so
//  each widget draws the exact slice of the wallpaper that sits behind it. Ebb renders the
//  wallpaper at the screen's size, cuts a slice for every spot a widget can occupy, and the
//  widgets show the slice for the spot set in Edit Widget › Position.
//

import CoreGraphics
import Foundation

/// A picture wallpaper with widgets cut to match.
nonisolated enum SceneWallpaper: String, CaseIterable, Identifiable {
    case night, dusk, aurora, forest, dunes

    var id: Self { self }

    var name: String {
        switch self {
        case .night: "Night"
        case .dusk: "Dusk"
        case .aurora: "Aurora"
        case .forest: "Forest"
        case .dunes: "Dunes"
        }
    }

    /// Text on widgets over this scene.
    var textHex: String {
        switch self {
        case .dunes: "#3A2614"
        default: "#F4F1EC"
        }
    }

    /// The scene's main tone, used for Ebb's own screens while it's active.
    var baseHex: String {
        switch self {
        case .night: "#0D1328"
        case .dusk: "#3B2346"
        case .aurora: "#06121A"
        case .forest: "#1F3530"
        case .dunes: "#EDD3AE"
        }
    }

    /// The active scene, or nil for a flat color.
    static var current: SceneWallpaper? {
        get { AppGroup.defaults.string(forKey: key).flatMap(SceneWallpaper.init(rawValue:)) }
        set { AppGroup.defaults.set(newValue?.rawValue, forKey: key) }
    }

    private static let key = "sceneWallpaper"
}

/// Home Screen icon size (Home Screen › Edit › Customize). It moves where widgets sit.
nonisolated enum IconLayout: String, CaseIterable, Identifiable {
    case small, large

    var id: Self { self }

    var label: String {
        switch self {
        case .small: "Small, with names"
        case .large: "Large, no names"
        }
    }

    static var current: IconLayout {
        get { AppGroup.defaults.string(forKey: key).flatMap(IconLayout.init(rawValue:)) ?? .small }
        set { AppGroup.defaults.set(newValue.rawValue, forKey: key) }
    }

    private static let key = "homeIconLayout"
}

nonisolated enum WidgetSize: String, CaseIterable {
    case small, medium, large

    /// Rows a widget of this size can start on (it covers two rows, or four for large).
    var startRows: Range<Int> { self == .large ? 0..<3 : 0..<5 }
}

/// Where a widget sits: the icon row its top edge is on, and for small widgets, the side.
nonisolated struct WidgetSpot: Hashable {
    var row: Int
    var right: Bool

    func fileName(for size: WidgetSize) -> String {
        switch size {
        case .small: "small-r\(row)-\(right ? "right" : "left").png"
        case .medium, .large: "\(size.rawValue)-r\(row).png"
        }
    }
}

/// Where iOS places widgets on the Home Screen, in points.
nonisolated struct HomeGrid: Equatable {
    var left: Double
    var rightSmallX: Double
    var small: Double
    var top: Double
    var rowPitch: Double

    var mediumWidth: Double { rightSmallX + small - left }
    var largeHeight: Double { small + 2 * rowPitch }

    func frame(_ size: WidgetSize, at spot: WidgetSpot) -> CGRect {
        let row = min(max(spot.row, size.startRows.lowerBound), size.startRows.upperBound - 1)
        let y = top + Double(row) * rowPitch
        switch size {
        case .small: return CGRect(x: spot.right ? rightSmallX : left, y: y, width: small, height: small)
        case .medium: return CGRect(x: left, y: y, width: mediumWidth, height: small)
        case .large: return CGRect(x: left, y: y, width: mediumWidth, height: largeHeight)
        }
    }

    /// Measured on iOS 26 Home Screens; other sizes are scaled from the closest one.
    private static let measured: [(width: Double, height: Double, layout: IconLayout, grid: HomeGrid)] = [
        // iPhone 17 Pro / 16 Pro (402 × 874), large icons.
        (402, 874, .large, HomeGrid(left: 21.333, rightSmallX: 211.333, small: 169.667, top: 89.667, rowPitch: 94.75)),
        // iPhone 15 Pro / 16 (393 × 852), small icons with names.
        (393, 852, .small, HomeGrid(left: 24.667, rightSmallX: 206.667, small: 162, top: 80.333, rowPitch: 98.5)),
    ]

    static func `for`(screenWidth width: Double, height: Double, layout: IconLayout) -> HomeGrid {
        let candidates = measured.filter { $0.layout == layout }
        let pool = candidates.isEmpty ? measured : candidates
        let ref = pool.min { abs($0.width - width) < abs($1.width - width) }!
        let sx = width / ref.width
        let sy = height / ref.height
        let g = ref.grid
        return HomeGrid(left: g.left * sx, rightSmallX: g.rightSmallX * sx, small: g.small * sx,
                        top: g.top * sy, rowPitch: g.rowPitch * sy)
    }
}

/// The wallpaper slices behind each widget spot, saved in the App Group.
nonisolated enum SceneSlices {
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("Scenes", isDirectory: true)
    }

    static func url(for size: WidgetSize, at spot: WidgetSpot) -> URL? {
        folder?.appendingPathComponent(spot.fileName(for: size))
    }

    /// The slice for this widget, if a scene is active.
    static func data(for size: WidgetSize, at spot: WidgetSpot) -> Data? {
        guard SceneWallpaper.current != nil, let url = url(for: size, at: spot) else { return nil }
        return try? Data(contentsOf: url)
    }
}
