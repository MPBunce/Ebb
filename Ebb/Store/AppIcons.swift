//
//  AppIcons.swift
//  Ebb
//
//  iPhone doesn't let apps read other apps' icons, but Apple's public App Store lookup
//  returns each app's official artwork. Ebb fetches an icon once per app (by bundle ID,
//  so it's always the right app) and caches it on the device.
//

import Observation
import SwiftUI
import UIKit

@Observable
final class AppIcons {
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private let directory = AppGroup.containerURL.appending(path: "Icons", directoryHint: .isDirectory)

    init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for bundleID: String) -> UIImage? {
        if let image = images[bundleID] { return image }
        load(bundleID)
        return nil
    }

    private func fileURL(_ bundleID: String) -> URL { directory.appending(path: bundleID + ".png") }

    private func load(_ bundleID: String) {
        guard !requested.contains(bundleID) else { return }
        requested.insert(bundleID)

        if let data = try? Data(contentsOf: fileURL(bundleID)), let image = UIImage(data: data) {
            images[bundleID] = image
            return
        }
        Task { await fetch(bundleID) }
    }

    private func fetch(_ bundleID: String) async {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [URLQueryItem(name: "bundleId", value: bundleID), URLQueryItem(name: "country", value: "us")]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let lookup = try? JSONDecoder().decode(Lookup.self, from: data),
              let artwork = lookup.results.first?.artworkUrl100,
              let artworkURL = URL(string: artwork),
              let (imageData, _) = try? await URLSession.shared.data(from: artworkURL),
              let image = UIImage(data: imageData)
        else {
            // Try again next launch.
            requested.remove(bundleID)
            return
        }
        try? imageData.write(to: fileURL(bundleID), options: .atomic)
        images[bundleID] = image
    }

    private struct Lookup: Decodable {
        struct Result: Decodable { let artworkUrl100: String? }
        let results: [Result]
    }
}

/// An app's real icon when Ebb knows it, otherwise a colored initial.
struct AppIconView: View {
    @Environment(AppIcons.self) private var icons
    let name: String
    var bundleID: String?
    var size: CGFloat = 34

    var body: some View {
        if let bundleID = bundleID ?? AppCatalog.bundleID(forName: name), let image = icons.image(for: bundleID) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.primary.opacity(0.08)))
                .accessibilityHidden(true)
        } else if let symbol = Self.builtInSymbols[name] {
            // Apple apps that aren't on the App Store, so have no icon to fetch.
            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(Color.gray.gradient))
                .accessibilityHidden(true)
        } else {
            AppMonogram(name: name)
        }
    }

    private static let builtInSymbols = [
        "Camera": "camera.fill",
        "Clock": "clock.fill",
        "Calculator": "plus.forwardslash.minus",
        "Settings": "gearshape.fill",
    ]
}
