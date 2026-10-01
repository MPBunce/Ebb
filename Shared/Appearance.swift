//
//  Appearance.swift
//  Shared between Ebb and its widgets.
//
//  iOS widgets can't be transparent, so Ebb makes them "invisible" instead: the widgets,
//  the app, and the wallpaper all share one background color.
//

import SwiftUI

/// A color stored as `#RRGGBB` so it can live in shared defaults.
nonisolated struct HexColor: Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        red = Double(resolved.red)
        green = Double(resolved.green)
        blue = Double(resolved.blue)
    }

    var hex: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

    /// Relative luminance (WCAG), used to pick a readable text color and color scheme.
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    var isDark: Bool { luminance < 0.4 }
}

nonisolated struct ColorPreset: Identifiable, Hashable {
    var name: String
    var background: String
    var text: String
    var id: String { name }
}

nonisolated enum Appearance {
    static let defaultBackground = "#000000"
    static let defaultText = "#F2F2F2"

    /// Background/text pairs that read well. The first two ship as Ebb's default wallpapers.
    static let presets: [ColorPreset] = [
        ColorPreset(name: "Midnight", background: "#000000", text: "#F2F2F2"),
        ColorPreset(name: "Paper", background: "#F3EFE6", text: "#1F1D1A"),
        ColorPreset(name: "Slate", background: "#1C2024", text: "#E6E8EA"),
        ColorPreset(name: "Sage", background: "#DDE3D5", text: "#22291F"),
        ColorPreset(name: "Dusk", background: "#2A2233", text: "#EDE6F2"),
        ColorPreset(name: "Sand", background: "#E8DCC8", text: "#2E2618"),
    ]

    static var wallpaperPresets: [ColorPreset] { Array(presets.prefix(2)) }

    static var background: HexColor {
        HexColor(hex: AppGroup.defaults.string(forKey: AppGroup.Key.backgroundHex) ?? defaultBackground)
            ?? HexColor(red: 0, green: 0, blue: 0)
    }

    /// The color widgets draw with: the background color, tuned to match how this
    /// iPhone actually renders the matching wallpaper.
    static var widgetBackground: HexColor {
        WidgetTuning.widgetColor(for: background)
    }

    static var text: HexColor {
        HexColor(hex: AppGroup.defaults.string(forKey: AppGroup.Key.textHex) ?? defaultText)
            ?? HexColor(red: 0.95, green: 0.95, blue: 0.95)
    }
}

// MARK: - Widget style

/// How app names line up in the Apps widget.
nonisolated enum ListAlignment: String, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: Self { self }

    var label: String {
        switch self {
        case .leading: "Left"
        case .center: "Center"
        case .trailing: "Right"
        }
    }

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var text: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

nonisolated enum ListTextSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: Self { self }
    var label: String { rawValue.capitalized }

    var points: CGFloat {
        switch self {
        case .small: 17
        case .medium: 21
        case .large: 26
        }
    }
}

nonisolated enum Typeface: String, CaseIterable, Identifiable {
    case system, serif, rounded, mono

    var id: Self { self }

    var label: String {
        switch self {
        case .system: "Default"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .mono: "Mono"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }
}

/// Style defaults set in Ebb and used by every widget unless a widget overrides them.
nonisolated enum WidgetStyle {
    static var alignment: ListAlignment {
        AppGroup.defaults.string(forKey: AppGroup.Key.listAlignment).flatMap(ListAlignment.init(rawValue:)) ?? .leading
    }

    static var textSize: ListTextSize {
        AppGroup.defaults.string(forKey: AppGroup.Key.listTextSize).flatMap(ListTextSize.init(rawValue:)) ?? .medium
    }

    static var typeface: Typeface {
        AppGroup.defaults.string(forKey: AppGroup.Key.typeface).flatMap(Typeface.init(rawValue:)) ?? .system
    }
}

/// Widget colors tuned to blend into the wallpaper on this iPhone, keyed by background color.
/// iOS renders photo wallpapers a little differently from widget backgrounds (most visibly
/// on light colors), so the widgets are adjusted to match what's really on screen.
nonisolated enum WidgetTuning {
    private static let key = "widgetTuning"

    static func widgetColor(for background: HexColor) -> HexColor {
        let stored = AppGroup.defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return stored[background.hex].flatMap(HexColor.init(hex:)) ?? background
    }

    static func setWidgetColor(_ color: HexColor?, for background: HexColor) {
        var stored = AppGroup.defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        stored[background.hex] = color?.hex
        AppGroup.defaults.set(stored, forKey: key)
    }
}
