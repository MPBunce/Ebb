//
//  ProgressWidgets.swift
//  EbbWidget
//
//  Quiet progress widgets, each in small, medium, and large with styles to choose from:
//  Year (or any period), Life, and Time Saved. Long-press › Edit Widget to change them.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Shared pieces

private func percent(_ value: Double, digits: Int = 0) -> String {
    (value * 100).formatted(.number.precision(.fractionLength(digits))) + "%"
}

/// Entries every `step` for the next day; views compute everything from the date.
private func steppedEntries<Entry>(step: TimeInterval, make: (Date) -> Entry) -> Timeline<Entry> {
    let now = Date.now
    let count = max(Int((24 * 60 * 60) / step), 1)
    return Timeline(entries: (0...count).map { make(now.addingTimeInterval(Double($0) * step)) }, policy: .atEnd)
}

private struct ThinBar: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.18))
                Capsule().fill(.primary).frame(width: max(proxy.size.width * value, height))
            }
        }
        .frame(height: height)
    }
}

private struct Ring<Center: View>: View {
    let value: Double
    var lineWidth: CGFloat = 5
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
    }
}

/// A grid of dots, filled up to `filled`, with the current one highlighted.
private struct DotGrid: View {
    let total: Int
    let filled: Int
    let columns: Int

    var body: some View {
        Canvas { context, size in
            let rows = Int((Double(total) / Double(columns)).rounded(.up))
            let cell = min(size.width / CGFloat(columns), size.height / CGFloat(max(rows, 1)))
            let dot = cell * 0.66
            let xOffset = (size.width - cell * CGFloat(columns)) / 2
            for index in 0..<total {
                let rect = CGRect(
                    x: xOffset + CGFloat(index % columns) * cell + (cell - dot) / 2,
                    y: CGFloat(index / columns) * cell + (cell - dot) / 2,
                    width: dot, height: dot
                )
                let opacity: Double = index + 1 == filled ? 1 : (index < filled ? 0.7 : 0.16)
                context.fill(Path(ellipseIn: rect), with: .color(Appearance.text.color.opacity(opacity)))
            }
        }
    }
}

private struct Caption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .opacity(0.6)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Shown in place of a Plus style for free users.
private struct PlusLocked: View {
    let name: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock")
            Text(name).font(.headline)
            Text("Part of Ebb Plus").font(.caption).opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension WidgetFamily {
    var isAccessory: Bool { [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(self) }

    /// Big-number size for each family.
    var heroSize: CGFloat {
        switch self {
        case .systemSmall: 42
        case .systemMedium: 52
        case .systemLarge: 76
        default: 30
        }
    }
}

// MARK: - Year (and other periods)

enum ProgressPeriod: String, AppEnum {
    case day, week, month, year

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [ProgressPeriod: DisplayRepresentation] = [
        .day: "Today", .week: "This Week", .month: "This Month", .year: "This Year",
    ]

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    func title(at date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.weekday(.wide))
        case .week: "This week"
        case .month: date.formatted(.dateTime.month(.wide))
        case .year: date.formatted(.dateTime.year())
        }
    }

    /// What's left as a number and a unit, e.g. ("91", "days left").
    func remaining(at date: Date, calendar: Calendar = .current) -> (number: String, unit: String) {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return ("", "") }
        let seconds = interval.end.timeIntervalSince(date)
        if self == .day {
            let hours = Int(seconds / 3600)
            if hours >= 1 { return ("\(hours)", hours == 1 ? "hour left" : "hours left") }
            return ("\(Int(seconds / 60))", "minutes left")
        }
        let days = Int((seconds / 86400).rounded(.up))
        return ("\(days)", days == 1 ? "day left" : "days left")
    }

    func remainingText(at date: Date) -> String {
        let left = remaining(at: date)
        return "\(left.number) \(left.unit)"
    }

    /// Units for the dots style: hours of the day, days of the week, month, or year.
    func units(at date: Date, calendar: Calendar = .current) -> (total: Int, current: Int) {
        switch self {
        case .day:
            return (24, calendar.component(.hour, from: date) + 1)
        case .week:
            return (calendar.range(of: .weekday, in: .weekOfYear, for: date)?.count ?? 7,
                    calendar.ordinality(of: .weekday, in: .weekOfYear, for: date) ?? 1)
        case .month:
            return (calendar.range(of: .day, in: .month, for: date)?.count ?? 30,
                    calendar.component(.day, from: date))
        case .year:
            return (calendar.range(of: .day, in: .year, for: date)?.count ?? 365,
                    calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        }
    }
}

enum ProgressStyle: String, AppEnum {
    case percent, bar, dots, ring, countdown

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [ProgressStyle: DisplayRepresentation] = [
        .percent: "Percent",
        .bar: "Bar",
        .dots: "Dots",
        .ring: "Ring (Plus)",
        .countdown: "Countdown (Plus)",
    ]

    var isPlus: Bool { self == .ring || self == .countdown }

    var name: String {
        switch self {
        case .percent: "Percent"
        case .bar: "Bar"
        case .dots: "Dots"
        case .ring: "Ring"
        case .countdown: "Countdown"
        }
    }
}

struct YearConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Year"
    static let description = IntentDescription("How much of the year, month, week, or day has passed.")

    @Parameter(title: "Period", default: .year)
    var period: ProgressPeriod

    @Parameter(title: "Style", default: .percent)
    var style: ProgressStyle

    @Parameter(title: "Show Details", default: true)
    var showDetails: Bool

    @Parameter(title: "Show Progress Bar", default: true)
    var showBar: Bool
    @Parameter(title: "Alignment", default: .automatic)
    var alignment: LauncherAlignment
}

struct YearEntry: TimelineEntry {
    let date: Date
    let configuration: YearConfigurationIntent
}

struct YearProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> YearEntry {
        YearEntry(date: .now, configuration: YearConfigurationIntent())
    }

    func snapshot(for configuration: YearConfigurationIntent, in context: Context) async -> YearEntry {
        YearEntry(date: .now, configuration: configuration)
    }

    func timeline(for configuration: YearConfigurationIntent, in context: Context) async -> Timeline<YearEntry> {
        // A day moves fast enough to need frequent updates; longer periods don't.
        let step: TimeInterval = configuration.period == .day ? 15 * 60 : 60 * 60
        return steppedEntries(step: step) { YearEntry(date: $0, configuration: configuration) }
    }
}

struct YearWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: YearEntry

    private var align: ListAlignment { entry.configuration.alignment.resolved }

    private var period: ProgressPeriod { entry.configuration.period }
    private var style: ProgressStyle { entry.configuration.style }
    private var details: Bool { entry.configuration.showDetails }
    private var value: Double { TimeProgress.fraction(of: period.component, at: entry.date) }
    private var title: String { period.title(at: entry.date) }

    var body: some View {
        Group {
            if family.isAccessory {
                accessory
            } else if style.isPlus && !EbbPlus.isActive {
                PlusLocked(name: style.name)
            } else {
                switch style {
                case .percent: percentView
                case .bar: barView
                case .dots: dotsView
                case .ring: ringView
                case .countdown: countdownView
                }
            }
        }
        .padding(family.isAccessory ? 0 : 16)
        .ebbWidgetStyle()
        .widgetURL(DeepLink.home.url)
    }

    @ViewBuilder
    private var accessory: some View {
        if family == .accessoryCircular {
            Gauge(value: value) { Text(title) } currentValueLabel: { Text("\(Int(value * 100))") }
                .gaugeStyle(.accessoryCircularCapacity)
        } else {
            VStack(alignment: align.horizontal, spacing: 4) {
                Text("\(title) · \(percent(value))").font(.headline)
                Gauge(value: value) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                Text(period.remainingText(at: entry.date)).font(.caption)
            }
        }
    }

    private var percentView: some View {
        VStack(alignment: align.horizontal, spacing: 6) {
            Caption(text: title)
            Spacer(minLength: 0)
            Text(percent(value, digits: family == .systemLarge ? 1 : 0))
                .font(.system(size: family.heroSize, weight: .thin))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if entry.configuration.showBar {
                ThinBar(value: value, height: family == .systemLarge ? 8 : 5).padding(.vertical, 6)
            }
            if details {
                Caption(text: period.remainingText(at: entry.date))
            }
        }
        .frame(maxWidth: .infinity, alignment: align.frame)
    }

    private var barView: some View {
        VStack(alignment: align.horizontal, spacing: family == .systemSmall ? 8 : 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline.weight(.regular))
                Spacer()
                Text(percent(value)).font(.headline.weight(.light)).monospacedDigit()
            }
            Spacer(minLength: 0)
            ThinBar(value: value, height: family == .systemLarge ? 14 : 8)
            if details {
                Caption(text: period.remainingText(at: entry.date))
            }
        }
    }

    private var dotsView: some View {
        let units = period.units(at: entry.date)
        let columns: Int = switch (period, family) {
        case (.year, .systemSmall): 19
        case (.year, .systemMedium): 37
        case (.year, _): 21
        case (.month, _), (.week, _): 7
        case (.day, .systemMedium): 12
        case (.day, _): 6
        }
        return VStack(alignment: align.horizontal, spacing: 8) {
            if details {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.caption.weight(.medium))
                    Spacer()
                    Text(percent(value)).font(.caption).monospacedDigit().opacity(0.7)
                }
            }
            DotGrid(total: units.total, filled: units.current, columns: columns)
            if entry.configuration.showBar && family != .systemSmall {
                ThinBar(value: value, height: family == .systemLarge ? 8 : 5)
            }
        }
    }

    private var ringView: some View {
        HStack(spacing: 16) {
            Ring(value: value, lineWidth: family == .systemLarge ? 10 : 6) {
                Text(percent(value))
                    .font(.system(size: family == .systemLarge ? 34 : 20, weight: .light))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            }
            if family == .systemMedium && details {
                VStack(alignment: align.horizontal, spacing: 4) {
                    Text(title).font(.headline.weight(.regular))
                    Caption(text: period.remainingText(at: entry.date))
                }
                .frame(maxWidth: .infinity, alignment: align.frame)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countdownView: some View {
        let left = period.remaining(at: entry.date)
        return VStack(alignment: align.horizontal, spacing: 2) {
            Caption(text: title)
            Spacer(minLength: 0)
            Text(left.number)
                .font(.system(size: family.heroSize * 1.1, weight: .thin))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Text(left.unit).font(.subheadline.weight(.light))
            if entry.configuration.showBar {
                ThinBar(value: value, height: family == .systemLarge ? 8 : 5).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: align.frame)
    }
}

struct YearWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbYear", intent: YearConfigurationIntent.self, provider: YearProvider()) { entry in
            YearWidgetView(entry: entry)
        }
        .configurationDisplayName("Year")
        .description("How much of the year has passed. Edit to show the month, week, or day, and pick a style.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Life

enum LifeStyle: String, AppEnum {
    case breakdown, percent, bar, years, ring, countdown

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [LifeStyle: DisplayRepresentation] = [
        .breakdown: "Years, Weeks & Days",
        .percent: "Percent",
        .bar: "Bar",
        .years: "Years as Dots",
        .ring: "Ring (Plus)",
        .countdown: "Weeks Left (Plus)",
    ]

    var isPlus: Bool { self == .ring || self == .countdown }

    var name: String {
        switch self {
        case .breakdown: "Years, weeks & days"
        case .percent: "Percent"
        case .bar: "Bar"
        case .years: "Years"
        case .ring: "Ring"
        case .countdown: "Weeks left"
        }
    }
}

enum LifeFraming: String, AppEnum {
    case lived, remaining

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static let caseDisplayRepresentations: [LifeFraming: DisplayRepresentation] = [
        .lived: "Life Lived", .remaining: "Life Remaining",
    ]
}

struct LifeConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Life"
    static let description = IntentDescription("How much of an average life you've lived.")

    @Parameter(title: "Style", default: .breakdown)
    var style: LifeStyle

    @Parameter(title: "Show", default: .remaining)
    var framing: LifeFraming

    @Parameter(title: "Show Progress Bar", default: true)
    var showBar: Bool
    @Parameter(title: "Alignment", default: .automatic)
    var alignment: LauncherAlignment
}

struct LifeEntry: TimelineEntry {
    let date: Date
    let configuration: LifeConfigurationIntent
}

struct LifeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LifeEntry {
        LifeEntry(date: .now, configuration: LifeConfigurationIntent())
    }

    func snapshot(for configuration: LifeConfigurationIntent, in context: Context) async -> LifeEntry {
        LifeEntry(date: .now, configuration: configuration)
    }

    func timeline(for configuration: LifeConfigurationIntent, in context: Context) async -> Timeline<LifeEntry> {
        steppedEntries(step: 6 * 60 * 60) { LifeEntry(date: $0, configuration: configuration) }
    }
}

struct LifeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LifeEntry

    var align: ListAlignment { entry.configuration.alignment.resolved }

    var body: some View {
        Group {
            if let life = LifeProgress.load() {
                if family == .systemLarge || family == .systemMedium {
                    VStack(spacing: family == .systemLarge ? 14 : 6) {
                        content(life)
                        // "Remember that you will die": the Stoic reminder behind this widget.
                        Text("memento mori")
                            .font(.system(.footnote, design: .serif).italic())
                            .opacity(0.5)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Memento mori: remember that you will die")
                    }
                } else {
                    content(life)
                }
            } else {
                VStack(alignment: align.horizontal, spacing: 4) {
                    Text("Life").font(.headline)
                    Text("Add your age in Ebb › Widgets.").font(.caption).opacity(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align.frame)
            }
        }
        .padding(family.isAccessory ? 0 : 16)
        .ebbWidgetStyle()
        .widgetURL(DeepLink.home.url)
    }

    @ViewBuilder
    private func content(_ life: LifeProgress) -> some View {
        let lived = life.fraction(at: entry.date)
        let showsRemaining = entry.configuration.framing == .remaining
        let value = showsRemaining ? 1 - lived : lived
        let label = showsRemaining ? "life remaining" : "life lived"
        let weeks = life.weeksRemaining(at: entry.date).formatted()
        let style = entry.configuration.style

        if family == .accessoryCircular {
            Gauge(value: lived) { Text("life") } currentValueLabel: { Text("\(Int(value * 100))") }
                .gaugeStyle(.accessoryCircularCapacity)
        } else if family == .accessoryRectangular {
            VStack(alignment: align.horizontal, spacing: 4) {
                Text("Life · \(percent(value, digits: 1))").font(.headline)
                Gauge(value: lived) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                Text(life.isInExtraTime(at: entry.date)
                     ? "Extra time: +\(life.breakdown(remaining: true, at: entry.date).weeks.formatted()) weeks"
                     : "\(weeks) weeks left").font(.caption)
            }
        } else if style.isPlus && !EbbPlus.isActive {
            PlusLocked(name: style.name)
        } else {
            switch style {
            case .breakdown:
                let span = life.breakdown(remaining: showsRemaining, at: entry.date)
                breakdownView(span,
                              title: span.isExtraTime ? "extra time" : (showsRemaining ? "life remaining" : "life lived"),
                              value: span.isExtraTime ? 1 : lived)
            case .percent:
                VStack(alignment: align.horizontal, spacing: 6) {
                    Caption(text: label)
                    Spacer(minLength: 0)
                    Text(percent(value, digits: 1))
                        .font(.system(size: family.heroSize, weight: .thin))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if entry.configuration.showBar {
                        ThinBar(value: lived, height: family == .systemLarge ? 8 : 5).padding(.vertical, 6)
                    }
                    Caption(text: life.isInExtraTime(at: entry.date) ? "in extra time" : "\(weeks) weeks to go")
                }
                .frame(maxWidth: .infinity, alignment: align.frame)
            case .bar:
                VStack(alignment: align.horizontal, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(label.capitalized).font(.headline.weight(.regular))
                        Spacer()
                        Text(percent(value, digits: 1)).font(.headline.weight(.light)).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    ThinBar(value: lived, height: family == .systemLarge ? 14 : 8)
                    Caption(text: "\(LifeProgress.age(birthDate: life.birthDate, now: entry.date)) of about \(Int(life.expectancyYears.rounded())) years")
                }
            case .years:
                let total = Int(life.expectancyYears.rounded())
                let current = min(LifeProgress.age(birthDate: life.birthDate, now: entry.date) + 1, total)
                VStack(alignment: align.horizontal, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("one dot per year").font(.caption.weight(.medium))
                        Spacer()
                        Text(percent(lived)).font(.caption).monospacedDigit().opacity(0.7)
                    }
                    DotGrid(total: total, filled: current, columns: family == .systemMedium ? 20 : 10)
                    if entry.configuration.showBar && family != .systemSmall {
                        ThinBar(value: lived, height: family == .systemLarge ? 8 : 5)
                    }
                }
            case .ring:
                HStack(spacing: 16) {
                    Ring(value: lived, lineWidth: family == .systemLarge ? 10 : 6) {
                        Text(percent(value))
                            .font(.system(size: family == .systemLarge ? 34 : 20, weight: .light))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                    }
                    if family == .systemMedium {
                        VStack(alignment: align.horizontal, spacing: 4) {
                            Text(label.capitalized).font(.headline.weight(.regular))
                            Caption(text: "\(weeks) weeks to go")
                        }
                        .frame(maxWidth: .infinity, alignment: align.frame)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .countdown:
                let span = life.breakdown(remaining: true, at: entry.date)
                VStack(alignment: align.horizontal, spacing: 2) {
                    Caption(text: span.isExtraTime ? "extra time" : "make them count")
                    Spacer(minLength: 0)
                    Text(span.isExtraTime ? "+\(span.weeks.formatted())" : weeks)
                        .font(.system(size: family.heroSize, weight: .thin))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(span.isExtraTime ? "weeks of extra time" : "weeks left").font(.subheadline.weight(.light))
                    if entry.configuration.showBar {
                        ThinBar(value: lived, height: family == .systemLarge ? 8 : 5).padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: align.frame)
            }
        }
    }
}

private extension LifeWidgetView {
    /// The same span in years, weeks, and days, each rounded.
    @ViewBuilder
    func breakdownView(_ span: LifeProgress.Breakdown, title: String, value: Double) -> some View {
        let sign = span.isExtraTime ? "+" : ""
        let rows = [
            (sign + span.years.formatted(), span.years == 1 ? "year" : "years"),
            (sign + span.weeks.formatted(), span.weeks == 1 ? "week" : "weeks"),
            (sign + span.days.formatted(), span.days == 1 ? "day" : "days"),
        ]
        if family == .systemMedium {
            VStack(alignment: align.horizontal, spacing: 10) {
                Caption(text: title)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    ForEach(rows, id: \.1) { number, unit in
                        VStack(alignment: align.horizontal, spacing: 0) {
                            Text(number)
                                .font(.system(size: 30, weight: .thin))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text(unit).font(.caption).opacity(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: align.frame)
                    }
                }
                if entry.configuration.showBar {
                    ThinBar(value: value, height: 5)
                }
            }
        } else {
            let size: CGFloat = family == .systemLarge ? 44 : 22
            VStack(alignment: align.horizontal, spacing: family == .systemLarge ? 10 : 2) {
                Caption(text: title)
                Spacer(minLength: 0)
                ForEach(rows, id: \.1) { number, unit in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(number)
                            .font(.system(size: size, weight: .thin))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(unit)
                            .font(family == .systemLarge ? .title3.weight(.light) : .caption)
                            .opacity(0.7)
                    }
                }
                if entry.configuration.showBar {
                    ThinBar(value: value, height: family == .systemLarge ? 8 : 4)
                        .padding(.top, family == .systemLarge ? 8 : 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: align.frame)
        }
    }
}

struct LifeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbLife", intent: LifeConfigurationIntent.self, provider: LifeProvider()) { entry in
            LifeWidgetView(entry: entry)
        }
        .configurationDisplayName("Life")
        .description("A gentle memento mori: the time you have left, in years, weeks, and days. Edit to change style or show time lived.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Time saved

enum SavedStyle: String, AppEnum {
    case number, big, breakdown, equivalents

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [SavedStyle: DisplayRepresentation] = [
        .number: "Number",
        .big: "Big",
        .breakdown: "Breakdown",
        .equivalents: "What It Adds Up To (Plus)",
    ]

    var isPlus: Bool { self == .equivalents }
}

enum SavedUnit: String, AppEnum {
    case hours, minutes, days

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Unit"
    static let caseDisplayRepresentations: [SavedUnit: DisplayRepresentation] = [
        .hours: "Hours", .minutes: "Minutes", .days: "Days",
    ]
}

struct SavedConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Time Saved"
    static let description = IntentDescription("Time Ebb has given back.")

    @Parameter(title: "Style", default: .number)
    var style: SavedStyle

    @Parameter(title: "Unit", default: .hours)
    var unit: SavedUnit
    @Parameter(title: "Alignment", default: .automatic)
    var alignment: LauncherAlignment
}

struct SavedEntry: TimelineEntry {
    let date: Date
    let configuration: SavedConfigurationIntent
}

struct SavedProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SavedEntry {
        SavedEntry(date: .now, configuration: SavedConfigurationIntent())
    }

    func snapshot(for configuration: SavedConfigurationIntent, in context: Context) async -> SavedEntry {
        SavedEntry(date: .now, configuration: configuration)
    }

    func timeline(for configuration: SavedConfigurationIntent, in context: Context) async -> Timeline<SavedEntry> {
        // Ebb also reloads this whenever you let an app go or start a focus session.
        steppedEntries(step: 6 * 60 * 60) { SavedEntry(date: $0, configuration: configuration) }
    }
}

struct TimeSavedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SavedEntry

    private var align: ListAlignment { entry.configuration.alignment.resolved }

    var body: some View {
        let saved = TimeSaved.load()
        let style = entry.configuration.style

        Group {
            if family.isAccessory {
                accessory(saved)
            } else if style.isPlus && !EbbPlus.isActive {
                PlusLocked(name: "What it adds up to")
            } else {
                switch style {
                case .number: number(saved)
                case .big: big(saved)
                case .breakdown: breakdown(saved)
                case .equivalents: equivalents(saved)
                }
            }
        }
        .padding(family.isAccessory ? 0 : 16)
        .ebbWidgetStyle()
        .widgetURL(DeepLink.home.url)
    }

    private func amount(_ minutes: Int) -> (value: String, unit: String) {
        switch entry.configuration.unit {
        case .minutes:
            return (minutes.formatted(), minutes == 1 ? "minute" : "minutes")
        case .hours:
            let hours = Double(minutes) / 60
            let text = hours < 10 ? hours.formatted(.number.precision(.fractionLength(1))) : Int(hours).formatted()
            return (text, minutes == 60 ? "hour" : "hours")
        case .days:
            let days = Double(minutes) / (60 * 24)
            return (days.formatted(.number.precision(.fractionLength(days < 10 ? 2 : 1))), "days")
        }
    }

    private func since(_ saved: TimeSaved) -> String {
        "since \(saved.since.formatted(.dateTime.month(.abbreviated).day()))"
    }

    @ViewBuilder
    private func accessory(_ saved: TimeSaved) -> some View {
        let total = amount(saved.totalMinutes)
        if family == .accessoryCircular {
            VStack(spacing: 0) {
                Text(total.value).font(.title3.weight(.semibold)).minimumScaleFactor(0.5)
                Text(shortUnit).font(.caption2)
            }
        } else {
            VStack(alignment: align.horizontal) {
                Text("\(total.value) \(total.unit) saved").font(.headline)
                Text("with Ebb \(since(saved))").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: align.frame)
        }
    }

    private var shortUnit: String {
        switch entry.configuration.unit {
        case .minutes: "min"
        case .hours: "hrs"
        case .days: "days"
        }
    }

    private func number(_ saved: TimeSaved) -> some View {
        let total = amount(saved.totalMinutes)
        return VStack(alignment: align.horizontal, spacing: 4) {
            Caption(text: "time given back")
            Spacer(minLength: 0)
            Text(total.value)
                .font(.system(size: family.heroSize * 1.1, weight: .thin))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(total.unit) saved").font(.subheadline.weight(.light))
            Caption(text: since(saved))
        }
        .frame(maxWidth: .infinity, alignment: align.frame)
    }

    /// The number as large as the widget allows.
    private func big(_ saved: TimeSaved) -> some View {
        let total = amount(saved.totalMinutes)
        return VStack(alignment: align.horizontal, spacing: 0) {
            Caption(text: "time given back")
            Spacer(minLength: 0)
            Text(total.value)
                .font(.system(size: 400, weight: .ultraLight))
                .monospacedDigit()
                .minimumScaleFactor(0.05)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: align.frame)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline) {
                Text("\(total.unit) saved").font(family == .systemLarge ? .title2.weight(.light) : .subheadline.weight(.light))
                Spacer()
                Caption(text: since(saved))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align.frame)
    }

    private func breakdown(_ saved: TimeSaved) -> some View {
        let letGoMinutes = saved.resistedCount * saved.minutesPerResist
        let total = amount(saved.totalMinutes)
        let letGo = amount(letGoMinutes)
        let focus = amount(saved.focusMinutes)
        let letGoShare = saved.totalMinutes == 0 ? 0 : Double(letGoMinutes) / Double(saved.totalMinutes)

        return VStack(alignment: align.horizontal, spacing: family == .systemSmall ? 6 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(total.value)
                    .font(.system(size: family == .systemSmall ? 34 : 44, weight: .thin))
                    .monospacedDigit()
                Text(total.unit).font(.subheadline.weight(.light))
                Spacer()
            }
            Spacer(minLength: 0)
            // A split bar: let-gos, then focus time.
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule().fill(.primary).frame(width: proxy.size.width * letGoShare)
                    Capsule().fill(.primary.opacity(0.35))
                }
            }
            .frame(height: 8)
            row("Apps let go", detail: "\(saved.resistedCount)×", value: "\(letGo.value) \(letGo.unit)", strong: true)
            row("Focus sessions", detail: nil, value: "\(focus.value) \(focus.unit)", strong: false)
            if family == .systemLarge {
                Spacer(minLength: 0)
                Caption(text: "Counting \(saved.minutesPerResist) min per app let go, \(since(saved)).")
            }
        }
    }

    private func row(_ title: String, detail: String?, value: String, strong: Bool) -> some View {
        HStack {
            Circle().fill(.primary.opacity(strong ? 1 : 0.35)).frame(width: 6, height: 6)
            Text(title).font(.caption)
            if let detail { Text(detail).font(.caption).opacity(0.6) }
            Spacer()
            Text(value).font(.caption).monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func equivalents(_ saved: TimeSaved) -> some View {
        let minutes = Double(saved.totalMinutes)
        // (icon, minutes each, singular, plural). Anything that rounds down to zero is skipped.
        let ideas: [(String, Double, String, String)] = [
            ("music.note", 4, "song", "songs"),
            ("cup.and.saucer", 20, "coffee with a friend", "coffees with a friend"),
            ("figure.walk", 30, "half-hour walk", "half-hour walks"),
            ("film", 120, "film", "films"),
            ("book.closed", 360, "book read", "books read"),
            ("bed.double", 480, "night of sleep", "nights of sleep"),
        ]
        let items: [(icon: String, text: String)] = ideas.compactMap { icon, each, one, many in
            let count = Int(minutes / each)
            guard count >= 1 else { return nil }
            return (icon, "\(count.formatted()) \(count == 1 ? one : many)")
        }
        .reversed()
        let count = family == .systemSmall ? 2 : (family == .systemMedium ? 3 : 6)
        let total = amount(saved.totalMinutes)

        return VStack(alignment: align.horizontal, spacing: family == .systemLarge ? 12 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(total.value)
                    .font(.system(size: family == .systemLarge ? 44 : 28, weight: .thin))
                    .monospacedDigit()
                Text("\(total.unit) is enough for").font(.caption).opacity(0.7)
            }
            if items.isEmpty {
                Caption(text: "Let a few apps go and this fills up.")
            }
            ForEach(items.prefix(count), id: \.text) { item in
                Label(item.text, systemImage: item.icon)
                    .font(family == .systemLarge ? .body : .caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: align.frame)
    }
}

struct TimeSavedWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbTimeSaved", intent: SavedConfigurationIntent.self, provider: SavedProvider()) { entry in
            TimeSavedWidgetView(entry: entry)
        }
        .configurationDisplayName("Time Saved")
        .description("Time Ebb has given back, from apps you let go and focus sessions. Edit to change style and units.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

#Preview("Year", as: .systemMedium) {
    YearWidget()
} timeline: {
    YearEntry(date: .now, configuration: YearConfigurationIntent())
}
