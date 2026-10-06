//
//  WeatherWidget.swift
//  EbbWidget
//
//  Weather where you are, in Ebb's quiet style: now in small, the next hours in medium,
//  and the week in large. Long-press › Edit Widget for units, forecast, icons, alignment.
//

import AppIntents
import SwiftUI
import WidgetKit

enum WeatherUnitOption: String, AppEnum {
    case automatic, celsius, fahrenheit

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Units"
    static let caseDisplayRepresentations: [WeatherUnitOption: DisplayRepresentation] = [
        .automatic: "Match iPhone", .celsius: "Celsius", .fahrenheit: "Fahrenheit",
    ]

    var resolved: TemperatureUnit {
        switch self {
        case .automatic: .local
        case .celsius: .celsius
        case .fahrenheit: .fahrenheit
        }
    }
}

enum WeatherForecast: String, AppEnum {
    case automatic, hourly, daily, none

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Forecast"
    static let caseDisplayRepresentations: [WeatherForecast: DisplayRepresentation] = [
        .automatic: "By Size", .hourly: "Next Hours", .daily: "Next Days", .none: "Just Now",
    ]
}

struct WeatherConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Weather"
    static let description = IntentDescription("The weather where you are.")

    @Parameter(title: "Units", default: .automatic)
    var units: WeatherUnitOption

    @Parameter(title: "Forecast", default: .automatic)
    var forecast: WeatherForecast

    @Parameter(title: "Show Icons", default: true)
    var showIcons: Bool

    @Parameter(title: "Show Place", default: true)
    var showPlace: Bool

    @Parameter(title: "Alignment", default: .automatic)
    var alignment: LauncherAlignment

    @Parameter(title: "Row", default: .row1)
    var row: WidgetRowOption

    @Parameter(title: "Side", default: .left)
    var side: WidgetSideOption
}

struct WeatherEntry: TimelineEntry {
    enum Content {
        case weather(WeatherSnapshot)
        /// Ebb hasn't been given location yet and there's nothing cached.
        case needsLocation
        case unavailable
    }

    let date: Date
    let content: Content
    let configuration: WeatherConfigurationIntent
}

struct WeatherProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, content: .weather(.sample), configuration: WeatherConfigurationIntent())
    }

    func snapshot(for configuration: WeatherConfigurationIntent, in context: Context) async -> WeatherEntry {
        let content: WeatherEntry.Content = context.isPreview
            ? .weather(WeatherStore.cached ?? .sample)
            : await load()
        return WeatherEntry(date: .now, content: content, configuration: configuration)
    }

    func timeline(for configuration: WeatherConfigurationIntent, in context: Context) async -> Timeline<WeatherEntry> {
        let content = await load()
        // Entries move the hourly list along; a fresh forecast comes every half hour or so.
        let entries = (0...2).map {
            WeatherEntry(date: .now.addingTimeInterval(Double($0) * 15 * 60), content: content, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func load() async -> WeatherEntry.Content {
        let cached = WeatherStore.cached
        if let cached, !cached.isStale { return .weather(cached) }
        guard let target = await WeatherStore.location(using: OneShotLocation()) else {
            return cached.map { .weather($0) } ?? .needsLocation
        }
        if let fresh = try? await WeatherStore.fetch(for: target.location, placeName: target.name) { return .weather(fresh) }
        return cached.map { .weather($0) } ?? .unavailable
    }
}

struct WeatherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    private var config: WeatherConfigurationIntent { entry.configuration }
    private var align: ListAlignment { config.alignment.resolved }
    private var unit: TemperatureUnit { config.units.resolved }

    private var forecast: WeatherForecast {
        guard config.forecast == .automatic else { return config.forecast }
        switch family {
        case .systemMedium: return .hourly
        case .systemLarge: return .daily
        default: return .none
        }
    }

    var body: some View {
        Group {
            switch entry.content {
            case .weather(let weather):
                if family.isAccessory {
                    accessory(weather)
                } else {
                    content(weather)
                }
            case .needsLocation:
                message("Open Ebb › Widgets to set your weather location.")
            case .unavailable:
                message("Weather isn't available right now.")
            }
        }
        .padding(family.isAccessory ? 0 : 16)
        .ebbWidgetStyle(spot: WidgetSpot(row: config.row, side: config.side), identity: "weather")
        .widgetURL(isReady ? DeepLink.weather.url : DeepLink.home.url)
    }

    private var isReady: Bool {
        if case .weather = entry.content { true } else { false }
    }

    private func message(_ text: String) -> some View {
        VStack(alignment: align.horizontal, spacing: 6) {
            Image(systemName: "location")
            Text(text).font(.footnote).multilineTextAlignment(align.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align.frame)
    }

    // MARK: Home Screen

    @ViewBuilder
    private func content(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: align.horizontal, spacing: 0) {
            now(weather)
            switch forecast {
            case .hourly:
                Spacer(minLength: 8)
                hourly(weather)
            case .daily:
                Spacer(minLength: 8)
                if family == .systemLarge {
                    hourly(weather)
                    Spacer(minLength: 12)
                }
                daily(weather)
            default:
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: align.horizontal, vertical: .top))
    }

    private func now(_ weather: WeatherSnapshot) -> some View {
        let isSmall = family == .systemSmall
        let showsDetailsBeside = forecast == .none && !isSmall
        return VStack(alignment: align.horizontal, spacing: 2) {
            if config.showPlace, let place = weather.place {
                HStack(spacing: 4) {
                    Text(place)
                    Image(systemName: "location.fill").font(.system(size: 8))
                }
                .font(.caption)
                .opacity(0.6)
                .lineLimit(1)
            }
            if isSmall || forecast == .none {
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(unit.format(weather.temperature))
                    .font(.system(size: heroSize, weight: .thin))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !isSmall && forecast != .none {
                    summary(weather)
                }
            }
            if isSmall || showsDetailsBeside || forecast == .none {
                summary(weather)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: forecast == .none || isSmall ? .infinity : nil, alignment: align.frame)
    }

    private var heroSize: CGFloat {
        switch (family, forecast) {
        case (.systemSmall, _): 52
        case (_, .none): family == .systemLarge ? 110 : 64
        default: 44
        }
    }

    private func summary(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: align.horizontal, spacing: 1) {
            HStack(spacing: 4) {
                if config.showIcons {
                    Image(systemName: weather.symbol).symbolRenderingMode(.monochrome)
                }
                Text(weather.condition).lineLimit(1)
            }
            .font(.footnote)
            Text("H \(unit.format(weather.high))  L \(unit.format(weather.low))")
                .font(.caption)
                .monospacedDigit()
                .opacity(0.6)
        }
        .minimumScaleFactor(0.7)
    }

    private func hourly(_ weather: WeatherSnapshot) -> some View {
        let count = family == .systemSmall ? 3 : 6
        let hours = weather.hours(from: entry.date, count: count)
        return HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                VStack(spacing: 4) {
                    Text(index == 0 ? "Now" : hour.date.formatted(.dateTime.hour()))
                        .font(.caption2)
                        .opacity(0.6)
                    if config.showIcons {
                        Image(systemName: hour.symbol)
                            .font(.footnote)
                            .frame(height: 16)
                    }
                    Text(unit.format(hour.temperature))
                        .font(.footnote)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func daily(_ weather: WeatherSnapshot) -> some View {
        let count = family == .systemLarge ? 5 : (family == .systemMedium ? 3 : 2)
        let days = weather.days(from: entry.date, count: count)
        let low = days.map(\.low).min() ?? 0
        let high = days.map(\.high).max() ?? 1
        return VStack(spacing: family == .systemLarge ? 10 : 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                HStack(spacing: 8) {
                    Text(index == 0 ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .frame(width: 46, alignment: .leading)
                    if config.showIcons {
                        Image(systemName: day.symbol)
                            .frame(width: 22)
                    }
                    if family != .systemSmall {
                        Text(unit.format(day.low))
                            .opacity(0.6)
                            .frame(width: 34, alignment: .trailing)
                        TemperatureRange(low: day.low, high: day.high, weekLow: low, weekHigh: high)
                    } else {
                        Spacer(minLength: 0)
                    }
                    Text(unit.format(day.high))
                        .frame(width: 34, alignment: .trailing)
                }
                .font(.footnote)
                .monospacedDigit()
                .lineLimit(1)
            }
        }
    }

    // MARK: Lock Screen

    @ViewBuilder
    private func accessory(_ weather: WeatherSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: weather.temperature, in: min(weather.low, weather.temperature)...max(weather.high, weather.temperature, weather.low + 0.1)) {
                Image(systemName: weather.symbol)
            } currentValueLabel: {
                Text(unit.format(weather.temperature))
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryInline:
            Label("\(unit.format(weather.temperature)) \(weather.condition)", systemImage: weather.symbol)
        default:
            VStack(alignment: align.horizontal, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: weather.symbol)
                    Text(unit.format(weather.temperature)).font(.headline)
                    Text(weather.condition).lineLimit(1)
                }
                Text("H \(unit.format(weather.high))  L \(unit.format(weather.low))").font(.caption)
                if let place = weather.place {
                    Text(place).font(.caption).opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: align.frame)
        }
    }
}

/// A day's low-to-high span within the week's range, like Apple Weather's bars.
private struct TemperatureRange: View {
    let low: Double
    let high: Double
    let weekLow: Double
    let weekHigh: Double

    var body: some View {
        GeometryReader { proxy in
            let span = max(weekHigh - weekLow, 1)
            let start = (low - weekLow) / span
            let end = (high - weekLow) / span
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.18))
                Capsule()
                    .fill(.primary)
                    .frame(width: max(proxy.size.width * (end - start), 4))
                    .offset(x: proxy.size.width * start)
            }
        }
        .frame(height: 4)
    }
}

struct WeatherWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbWeather", intent: WeatherConfigurationIntent.self, provider: WeatherProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("Weather")
        .description("The weather where you are. Edit to change units, the forecast, or icons.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}
