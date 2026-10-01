//
//  ClockWidget.swift
//  EbbWidget
//
//  A clock in several styles. Digital and Analog are free; the rest are Ebb Plus.
//

import AppIntents
import SwiftUI
import WidgetKit

extension ClockStyle: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Clock Style"
    static let caseDisplayRepresentations: [ClockStyle: DisplayRepresentation] = [
        .digital: "Digital",
        .analog: "Analog",
        .stacked: "Stacked (Plus)",
        .words: "Words (Plus)",
        .dayRing: "Day ring (Plus)",
    ]
}

struct ClockConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Clock"
    static let description = IntentDescription("Choose a clock style.")

    @Parameter(title: "Style", default: .digital)
    var style: ClockStyle

    @Parameter(title: "Show Date", default: true)
    var showDate: Bool

    @Parameter(title: "Show Progress Bar", default: true)
    var showProgress: Bool
}

struct ClockEntry: TimelineEntry {
    let date: Date
    let style: ClockStyle
    var showDate = true
    var showProgress = true
}

struct ClockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClockEntry {
        ClockEntry(date: .now, style: .digital)
    }

    func snapshot(for configuration: ClockConfigurationIntent, in context: Context) async -> ClockEntry {
        ClockEntry(date: .now, style: configuration.style, showDate: configuration.showDate, showProgress: configuration.showProgress)
    }

    func timeline(for configuration: ClockConfigurationIntent, in context: Context) async -> Timeline<ClockEntry> {
        let style = configuration.style
        let now = Date.now
        if style == .digital {
            // Digital text ticks by itself; entries keep the day bar moving.
            let entries = (0...96).map { ClockEntry(date: now.addingTimeInterval(Double($0) * 900), style: style, showDate: configuration.showDate, showProgress: configuration.showProgress) }
            return Timeline(entries: entries, policy: .atEnd)
        }
        // Drawn styles need an entry for every minute.
        let calendar = Calendar.current
        let startOfMinute = calendar.date(bySetting: .second, value: 0, of: now).map {
            $0 > now ? $0.addingTimeInterval(-60) : $0
        } ?? now
        let entries = (0..<120).map { ClockEntry(date: startOfMinute.addingTimeInterval(Double($0) * 60), style: style, showDate: configuration.showDate, showProgress: configuration.showProgress) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct ClockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClockEntry

    var body: some View {
        Group {
            if !entry.style.isUnlocked {
                locked
            } else if family == .accessoryRectangular {
                accessory
            } else {
                switch entry.style {
                case .digital: digital
                case .analog:
                    if family == .systemMedium {
                        // Face on the left, date and day bar beside it.
                        HStack(spacing: 20) {
                            AnalogFace(date: entry.date)
                                .aspectRatio(1, contentMode: .fit)
                            VStack(alignment: .leading, spacing: 8) {
                                Spacer(minLength: 0)
                                if entry.showDate {
                                    Text(dateLine).font(.subheadline).opacity(0.7)
                                }
                                if entry.showProgress {
                                    dayBar
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            AnalogFace(date: entry.date)
                            if entry.showDate && family != .systemSmall {
                                Text(dateLine).font(.caption).opacity(0.6)
                            }
                            if entry.showProgress {
                                dayBar
                            }
                        }
                    }
                case .stacked: stacked
                case .words: words
                case .dayRing: dayRing
                }
            }
        }
        .padding(family == .accessoryRectangular ? 0 : 16)
        .ebbWidgetStyle()
        .widgetURL(DeepLink.home.url)
    }

    /// Scales the big text with the widget size.
    private var scale: CGFloat {
        switch family {
        case .systemMedium: 1.3
        case .systemLarge: 2
        default: 1
        }
    }

    private var dateLine: String {
        entry.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var digital: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            Text(entry.date, style: .time)
                .font(.system(size: 40 * scale, weight: .thin))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if entry.showDate {
                Text(dateLine)
                    .font(family == .systemLarge ? .title3 : .caption)
                    .opacity(0.6)
            }
            if entry.showProgress {
                dayBar.padding(.top, family == .systemLarge ? 16 : 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stacked: some View {
        let hour = entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
        let minute = entry.date.formatted(.dateTime.minute(.twoDigits))
        return VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: -10) {
                Text(hour)
                Text(minute).opacity(0.55)
            }
            .font(.system(size: 56 * scale, weight: .thin))
            .monospacedDigit()
            Spacer()
            if entry.showDate {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated)).lowercased())
                    .font(.caption)
                    .opacity(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            if entry.showProgress {
                dayBar
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text("it’s")
                .font(.caption)
                .opacity(0.6)
            Text(TimeInWords.phrase(for: entry.date))
                .font(.system(size: 24 * scale, weight: .light, design: .serif))
                .minimumScaleFactor(0.6)
                .lineLimit(3)
            Spacer(minLength: 0)
            if entry.showDate {
                Text(dateLine).font(.caption).opacity(0.6)
            }
            if entry.showProgress {
                dayBar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How much of today has passed, as a bar on its own.
    private var dayBar: some View {
        let day = TimeProgress.fraction(of: .day, at: entry.date)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.18))
                Capsule().fill(.primary).frame(width: max(proxy.size.width * day, 4))
            }
        }
        .frame(height: family == .systemLarge ? 6 : 4)
        .accessibilityElement()
        .accessibilityLabel("\(Int(day * 100)) percent of today has passed")
    }

    private var dayRing: some View {
        let progress = TimeProgress.fraction(of: .day, at: entry.date)
        return ZStack {
            Circle().stroke(.primary.opacity(0.15), lineWidth: 4 * scale)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.primary, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(entry.date, style: .time)
                .font(.system(size: 22 * scale, weight: .light))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(12)
        }
        .padding(4)
    }

    private var accessory: some View {
        VStack(alignment: .leading) {
            if entry.style == .words {
                Text(TimeInWords.phrase(for: entry.date))
                    .font(.headline)
                    .minimumScaleFactor(0.6)
            } else {
                Text(entry.date, style: .time)
                    .font(.system(size: 30, weight: .light))
            }
            Text(entry.date.formatted(.dateTime.weekday(.wide).day()))
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var locked: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock")
            Text(entry.style.name)
                .font(.headline)
            Text("Part of Ebb Plus")
                .font(.caption)
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A minimal analog face: tick marks at the quarters and two thin hands.
private struct AnalogFace: View {
    let date: Date

    var body: some View {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = Double(parts.minute ?? 0)
        let hour = Double((parts.hour ?? 0) % 12) + minute / 60

        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            ZStack {
                ForEach(0..<12) { tick in
                    Capsule()
                        .fill(.primary.opacity(tick % 3 == 0 ? 0.8 : 0.25))
                        .frame(width: tick % 3 == 0 ? 2.5 : 1.5, height: tick % 3 == 0 ? radius * 0.14 : radius * 0.08)
                        .offset(y: -radius * 0.88)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                hand(length: radius * 0.5, width: 3.5, degrees: hour * 30)
                hand(length: radius * 0.78, width: 2, degrees: minute * 6)
                Circle().fill(.primary).frame(width: 6, height: 6)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityElement()
        .accessibilityLabel(date.formatted(date: .omitted, time: .shortened))
    }

    private func hand(length: CGFloat, width: CGFloat, degrees: Double) -> some View {
        Capsule()
            .fill(.primary)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }
}

struct ClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "EbbClock", intent: ClockConfigurationIntent.self, provider: ClockProvider()) { entry in
            ClockWidgetView(entry: entry)
        }
        .configurationDisplayName("Clock")
        .description("Digital, Analog, and more styles with Ebb Plus. Long-press › Edit Widget to change style.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    ClockWidget()
} timeline: {
    ClockEntry(date: .now, style: .digital)
    ClockEntry(date: .now, style: .analog)
}
