//
//  InstalledApps.swift
//  Ebb
//
//  iPhone doesn't let apps list what's installed. It does let an app ask whether a
//  specific app is installed, for up to 50 apps declared in Info.plist
//  (LSApplicationQueriesSchemes). Ebb declares its catalog's third-party apps, so it
//  can find which of them are on this iPhone.
//

import SwiftUI
import UIKit

enum InstalledApps {
    /// Catalog apps that are on this iPhone. Built-in Apple apps are assumed present.
    static func detect() -> [CatalogApp] {
        AppCatalog.apps.filter { app in
            if app.category == .essentials { return true }
            guard let scheme = app.scheme, let url = URL(string: scheme) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }
}

/// A round initial, standing in for an app icon (iPhone doesn't share other apps' icons).
struct AppMonogram: View {
    let name: String

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(color.gradient))
            .accessibilityHidden(true)
    }

    /// A stable color per app name.
    private var color: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .cyan, .mint, .brown]
        let index = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[index % palette.count]
    }
}

/// A roomy app row: icon, name, plain-language detail, and an Open button.
struct AppRow: View {
    @Environment(LauncherStore.self) private var store
    let target: LaunchTarget
    var detail: String?

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(name: target.name, bundleID: target.iconBundleID)
            VStack(alignment: .leading, spacing: 3) {
                Text(target.name)
                    .font(.body)
                Text(detail ?? defaultDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                store.open(target, intention: nil)
            } label: {
                Text("Open")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityLabel("Open \(target.name)")
        }
        .padding(.vertical, 6)
    }

    private var defaultDetail: String {
        var parts: [String] = []
        let widgets = store.lists.filter { $0.appIDs.contains(target.id) }.map(\.name)
        parts.append(widgets.isEmpty ? "Not on a widget" : widgets.joined(separator: ", "))
        if target.isMindful { parts.append("Mindful pause") }
        if target.isHidden { parts.append("Hidden") }
        return parts.joined(separator: " · ")
    }
}
