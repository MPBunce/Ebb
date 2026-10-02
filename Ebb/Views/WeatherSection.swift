//
//  WeatherSection.swift
//  Ebb
//
//  The Weather widget's settings: where to show weather for (the iPhone's location or a
//  chosen place), what the widget will show, and the Apple Weather attribution WeatherKit requires.
//

import CoreLocation
import MapKit
import SwiftUI
import WeatherKit
import WidgetKit

struct WeatherSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var location = OneShotLocation()
    @State private var status: CLAuthorizationStatus = .notDetermined
    @State private var place: WeatherPlace? = WeatherStore.chosenPlace
    @State private var weather: WeatherSnapshot? = WeatherStore.cached
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var attribution: WeatherAttribution?

    var body: some View {
        Section {
            NavigationLink {
                WeatherPlacePicker(place: $place)
            } label: {
                LabeledContent("Location", value: place?.name ?? "Current location")
            }

            if place == nil {
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
                    EmptyView()
                }
            }

            current

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
            Text("Pick a place, or use your current location and choose **While Using the App or Widgets** so the widget can follow you. Your location only goes to Apple Weather.")
        }
        .task {
            location.onAuthorizationChange = { Task { await refresh() } }
            await refresh()
            attribution = try? await WeatherService.shared.attribution
        }
        .onChange(of: place) {
            weather = nil
            Task { await refresh(force: true) }
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
        } else if let errorText {
            VStack(alignment: .leading, spacing: 4) {
                Button("Couldn't get the weather. Try again") { Task { await refresh(force: true) } }
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refresh(force: Bool = false) async {
        status = location.authorization
        if let weather, !weather.isStale, !force { return }
        isLoading = true
        defer { isLoading = false }
        guard let target = await WeatherStore.location(using: location) else {
            errorText = place == nil && location.isAuthorized ? "Your location isn't available. Pick a place instead." : nil
            return
        }
        do {
            weather = try await WeatherStore.fetch(for: target.location, placeName: target.name)
            errorText = nil
            WidgetCenter.shared.reloadTimelines(ofKind: "EbbWeather")
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Choose "Current location" or search for a town.
struct WeatherPlacePicker: View {
    @Binding var place: WeatherPlace?
    @Environment(\.dismiss) private var dismiss

    @State private var search = PlaceSearch()
    @State private var query = ""
    @State private var isResolving = false

    var body: some View {
        List {
            Section {
                Button {
                    place = nil
                    WeatherStore.chosenPlace = nil
                    dismiss()
                } label: {
                    HStack {
                        Label("Current location", systemImage: "location.fill")
                        Spacer()
                        if place == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                if let place {
                    HStack {
                        Label(place.name, systemImage: "mappin")
                        Spacer()
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }

            if !search.results.isEmpty {
                Section("Places") {
                    ForEach(search.results, id: \.self) { result in
                        Button {
                            Task { await choose(result) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(isResolving)
                    }
                }
            }
        }
        .navigationTitle("Weather Location")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a city")
        .onChange(of: query) { _, text in search.update(text) }
        .overlay {
            if isResolving { ProgressView() }
        }
    }

    private func choose(_ result: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: result)).start()
        guard let item = response?.mapItems.first else { return }
        let coordinate = item.location.coordinate
        let chosen = WeatherPlace(name: result.title, latitude: coordinate.latitude, longitude: coordinate.longitude)
        WeatherStore.chosenPlace = chosen
        place = chosen
        dismiss()
    }
}

/// Town and city suggestions as you type.
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: .locality)
    }

    func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            results = []
            completer.cancel()
        } else {
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}
