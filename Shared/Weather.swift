//
//  Weather.swift
//  Shared between Ebb and its widgets.
//
//  The Weather widget shows Apple Weather (WeatherKit) for wherever the iPhone is. Ebb asks
//  for location once; after that the widget finds its own location when iOS allows it, and
//  falls back to the last place Ebb saw. The last forecast is cached so the widget always has
//  something to show.
//

import CoreLocation
import Foundation
import MapKit
import WeatherKit

/// A forecast saved to the App Group. Temperatures are in Celsius.
nonisolated struct WeatherSnapshot: Codable, Equatable {
    struct Hour: Codable, Equatable {
        var date: Date
        var temperature: Double
        var symbol: String
        var precipitationChance: Double
    }

    struct Day: Codable, Equatable {
        var date: Date
        var low: Double
        var high: Double
        var symbol: String
        var precipitationChance: Double
    }

    var fetched: Date
    var place: String?
    var temperature: Double
    var feelsLike: Double
    var condition: String
    var symbol: String
    var high: Double
    var low: Double
    var hours: [Hour]
    var days: [Day]

    /// Hours from the start of the hour containing `date`.
    func hours(from date: Date, count: Int) -> [Hour] {
        let start = date.addingTimeInterval(-3600)
        return Array(hours.filter { $0.date > start }.prefix(count))
    }

    /// Days from the day containing `date`.
    func days(from date: Date, count: Int, calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: date)
        return Array(days.filter { $0.date >= today }.prefix(count))
    }

    var isStale: Bool { Date.now.timeIntervalSince(fetched) > 30 * 60 }

    static let sample: WeatherSnapshot = {
        let hourStart = Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now
        let today = Calendar.current.startOfDay(for: .now)
        var hours: [Hour] = []
        for offset in 0..<12 {
            let temperature: Double = 18 + sin(Double(offset) / 2) * 3
            hours.append(Hour(date: hourStart.addingTimeInterval(Double(offset) * 3600), temperature: temperature,
                              symbol: offset < 5 ? "sun.max" : "moon", precipitationChance: 0))
        }
        let symbols = ["sun.max", "cloud.sun", "cloud.rain"]
        var days: [Day] = []
        for offset in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
            days.append(Day(date: date, low: 10 + Double(offset % 3), high: 19 + Double(offset % 4),
                            symbol: symbols[offset % 3], precipitationChance: offset % 3 == 2 ? 0.6 : 0.1))
        }
        return WeatherSnapshot(fetched: .now, place: "Cupertino", temperature: 18, feelsLike: 17,
                               condition: "Mostly Clear", symbol: "cloud.sun", high: 21, low: 12, hours: hours, days: days)
    }()
}

nonisolated enum TemperatureUnit: String, CaseIterable {
    case celsius, fahrenheit

    static var local: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// "18°" from a Celsius value.
    func format(_ celsius: Double) -> String {
        let value = self == .celsius ? celsius : celsius * 9 / 5 + 32
        let rounded = Int(value.rounded())
        return "\(rounded == 0 ? 0 : rounded)°"
    }
}

/// A place chosen in Ebb instead of following the iPhone's location.
nonisolated struct WeatherPlace: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

nonisolated enum WeatherStore {
    private static let snapshotKey = "weatherSnapshot"
    private static let placeKey = "weatherPlace"
    private static let latitudeKey = "weatherLatitude"
    private static let longitudeKey = "weatherLongitude"

    static var cached: WeatherSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    static func save(_ snapshot: WeatherSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            AppGroup.defaults.set(data, forKey: snapshotKey)
        }
    }

    /// The chosen place, or nil to use the iPhone's location.
    static var chosenPlace: WeatherPlace? {
        get {
            guard let data = AppGroup.defaults.data(forKey: placeKey) else { return nil }
            return try? JSONDecoder().decode(WeatherPlace.self, from: data)
        }
        set {
            AppGroup.defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: placeKey)
            // The cached forecast is for the old place.
            AppGroup.defaults.removeObject(forKey: snapshotKey)
        }
    }

    /// Where to get weather for: the chosen place, or the iPhone's location.
    static func location(using finder: OneShotLocation) async -> (location: CLLocation, name: String?)? {
        if let place = chosenPlace { return (place.location, place.name) }
        guard let here = await finder.current() ?? lastLocation else { return nil }
        return (here, nil)
    }

    /// The last location Ebb or the widget found.
    static var lastLocation: CLLocation? {
        guard AppGroup.defaults.object(forKey: latitudeKey) != nil else { return nil }
        return CLLocation(latitude: AppGroup.defaults.double(forKey: latitudeKey),
                          longitude: AppGroup.defaults.double(forKey: longitudeKey))
    }

    static func remember(_ location: CLLocation) {
        AppGroup.defaults.set(location.coordinate.latitude, forKey: latitudeKey)
        AppGroup.defaults.set(location.coordinate.longitude, forKey: longitudeKey)
    }

    /// Fetches a fresh forecast for `location` and caches it.
    static func fetch(for location: CLLocation, placeName: String? = nil) async throws -> WeatherSnapshot {
        let (current, hourly, daily) = try await WeatherService.shared.weather(
            for: location, including: .current, .hourly, .daily)
        let today = daily.first
        var resolvedName = placeName
        if resolvedName == nil { resolvedName = await self.placeName(for: location) }
        let snapshot = WeatherSnapshot(
            fetched: .now,
            place: resolvedName,
            temperature: current.temperature.converted(to: .celsius).value,
            feelsLike: current.apparentTemperature.converted(to: .celsius).value,
            condition: current.condition.description,
            symbol: current.symbolName,
            high: today?.highTemperature.converted(to: .celsius).value ?? current.temperature.converted(to: .celsius).value,
            low: today?.lowTemperature.converted(to: .celsius).value ?? current.temperature.converted(to: .celsius).value,
            hours: hourly.forecast.prefix(30).map {
                .init(date: $0.date, temperature: $0.temperature.converted(to: .celsius).value,
                      symbol: $0.symbolName, precipitationChance: $0.precipitationChance)
            },
            days: daily.forecast.prefix(10).map {
                .init(date: $0.date, low: $0.lowTemperature.converted(to: .celsius).value,
                      high: $0.highTemperature.converted(to: .celsius).value,
                      symbol: $0.symbolName, precipitationChance: $0.precipitationChance)
            }
        )
        save(snapshot)
        return snapshot
    }

    /// The town name, reusing the last one while the iPhone hasn't moved far.
    private static func placeName(for location: CLLocation) async -> String? {
        if let cached, let last = lastPlaceLocation, let place = cached.place,
           last.distance(from: location) < 3000 {
            return place
        }
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return cached?.place }
        AppGroup.defaults.set([location.coordinate.latitude, location.coordinate.longitude], forKey: "weatherPlaceLocation")
        return item.addressRepresentations?.cityName ?? item.name
    }

    private static var lastPlaceLocation: CLLocation? {
        guard let pair = AppGroup.defaults.array(forKey: "weatherPlaceLocation") as? [Double], pair.count == 2 else { return nil }
        return CLLocation(latitude: pair[0], longitude: pair[1])
    }
}

/// Finds the iPhone's location once.
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    /// Called when the person answers the location prompt or changes it in Settings.
    var onAuthorizationChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    /// Asks for When In Use permission (which also covers widgets).
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// A recent location, or nil if location is off or takes too long.
    func current(timeout: Duration = .seconds(10)) async -> CLLocation? {
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -15 * 60 {
            WeatherStore.remember(recent)
            return recent
        }
        guard isAuthorized || manager.isAuthorizedForWidgetUpdates else { return nil }
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        let location = await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            Task {
                try? await Task.sleep(for: timeout)
                self.finish(nil)
            }
        }
        if let location { WeatherStore.remember(location) }
        return location ?? manager.location
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onAuthorizationChange?() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
