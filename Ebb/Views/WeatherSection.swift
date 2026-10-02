//
//  WeatherSection.swift
//  Ebb
//
//  The Weather widget's settings: location permission, what the widget will show, and
//  the Apple Weather attribution WeatherKit requires.
//

import CoreLocation
import SwiftUI
import WeatherKit
import WidgetKit

struct WeatherSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var location = OneShotLocation()
    @State private var status: CLAuthorizationStatus = .notDetermined
    @State private var weather: WeatherSnapshot? = WeatherStore.cached
    @State private var isLoading = false
    @State private var failed = false
    @State private var attribution: WeatherAttribution?

    var body: some View {
        Section {
            switch status {
            case .notDetermined:
                Button {
                    location.requestPermission()
                } label: {
                    Label("Use my location", systemImage: "location")
                }
            case .denied, .restricted:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Turn on location in Settings", systemImage: "location.slash")
                }
            default:
                current
            }
            if let attribution {
                Link(destination: attribution.legalPageURL) {
                    HStack(spacing: 6) {
                        AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Text(attribution.serviceName)
                        }
                        .frame(height: 12)
                        Text("Data sources")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Weather widget")
        } footer: {
            Text("Shows the weather where you are. Choose **While Using the App or Widgets** so the widget can follow you; otherwise it uses the last place Ebb saw. Your location only goes to Apple Weather.")
        }
        .task {
            location.onAuthorizationChange = { Task { await refresh() } }
            await refresh()
            attribution = try? await WeatherService.shared.attribution
        }
    }

    @ViewBuilder
    private var current: some View {
        if let weather {
            HStack(spacing: 12) {
                Image(systemName: weather.symbol)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(TemperatureUnit.local.format(weather.temperature)) \(weather.condition)")
                    Text([weather.place, "Updated \(weather.fetched.formatted(.relative(presentation: .named)))"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading { ProgressView() }
            }
        } else if isLoading {
            HStack {
                Text("Finding the weather…")
                Spacer()
                ProgressView()
            }
        } else if failed {
            Button("Weather isn't available. Try again") { Task { await refresh(force: true) } }
        }
    }

    private func refresh(force: Bool = false) async {
        status = location.authorization
        guard location.isAuthorized else { return }
        if let weather, !weather.isStale, !force { return }
        isLoading = true
        defer { isLoading = false }
        guard let here = await location.current() ?? WeatherStore.lastLocation,
              let fresh = try? await WeatherStore.fetch(for: here) else {
            failed = weather == nil
            return
        }
        weather = fresh
        failed = false
        WidgetCenter.shared.reloadTimelines(ofKind: "EbbWeather")
    }
}
