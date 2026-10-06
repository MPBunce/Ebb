//
//  TimeAndLifeWidget.swift
//  EbbWidget
//
//  Ebb Plus: one large widget with the time Ebb has given back and the life you have
//  left. Sized for the Today View (swipe right on the first Home Screen page): large,
//  or extra large portrait from iOS 27, and extra large on iPad.
//

import SwiftUI
import WidgetKit

struct TimeAndLifeEntry: TimelineEntry {
    let date: Date
}

struct TimeAndLifeProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimeAndLifeEntry { TimeAndLifeEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (TimeAndLifeEntry) -> Void) {
        completion(TimeAndLifeEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimeAndLifeEntry>) -> Void) {
        // Ebb also reloads widgets whenever you let an app go or finish a focus session.
        completion(steppedEntries(step: 60 * 60) { TimeAndLifeEntry(date: $0) })
    }
}

struct TimeAndLifeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimeAndLifeEntry

    private var isExtraLarge: Bool { family == .systemExtraLarge }

    /// The tall iOS 27 size: same layout as Large, with more room.
    private var isTall: Bool {
        if #available(iOS 27.0, *) { return family == .systemExtraLargePortrait }
        return false
    }

    private var heroSize: CGFloat { isExtraLarge ? 84 : isTall ? 96 : 64 }

    var body: some View {
        Group {
            if !EbbPlus.isActive {
                PlusLocked(name: "Time & Life")
            } else if isExtraLarge {
                HStack(spacing: 28) {
                    timeSaved.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Rectangle().fill(.primary.opacity(0.15)).frame(width: 1)
                    life.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    timeSaved
                    Spacer(minLength: 12)
                    Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
                    Spacer(minLength: 12)
                    life
                }
            }
        }
        .padding(isExtraLarge || isTall ? 24 : 18)
        .ebbWidgetStyle()
        .widgetURL(DeepLink.home.url)
    }

    // MARK: Time saved

    private var timeSaved: some View {
        let saved = TimeSaved.load()
        let amount = Self.amount(minutes: saved.totalMinutes)
        return VStack(alignment: .leading, spacing: 4) {
            Caption(text: "time given back")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(amount.value)
                    .font(.system(size: heroSize, weight: .thin))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(amount.unit)
                    .font(.title3.weight(.light))
                    .lineLimit(1)
            }
            Caption(text: summary(saved))
            let letGoShare = saved.totalMinutes == 0 ? 1 : Double(saved.resistedMinutes) / Double(saved.totalMinutes)
            ThinBar(value: letGoShare, height: 8)
                .padding(.vertical, 6)
            HStack {
                Caption(text: "\(Self.short(saved.resistedMinutes)) at mindful pauses")
                Spacer()
                Caption(text: "\(Self.short(saved.blockedMinutes)) at the block screen")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "42 min" or "207 h", for the breakdown under the bar.
    static func short(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\((minutes / 60).formatted()) h"
    }

    private func summary(_ saved: TimeSaved) -> String {
        let sameYear = Calendar.current.isDate(saved.since, equalTo: entry.date, toGranularity: .year)
        let since = saved.since.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).year())
        let letGo = saved.resistedCount == 1 ? "1 app let go" : "\(saved.resistedCount.formatted()) apps let go"
        return "since \(since) · \(letGo)"
    }

    /// Minutes under an hour, then hours (one decimal under ten).
    static func amount(minutes: Int) -> (value: String, unit: String) {
        guard minutes >= 60 else { return (minutes.formatted(), minutes == 1 ? "minute" : "minutes") }
        let hours = Double(minutes) / 60
        let value = hours < 10 ? hours.formatted(.number.precision(.fractionLength(1))) : Int(hours).formatted()
        return (value, minutes == 60 ? "hour" : "hours")
    }

    // MARK: Life

    @ViewBuilder
    private var life: some View {
        if let life = LifeProgress.load() {
            let span = life.breakdown(remaining: true, at: entry.date)
            let lived = life.fraction(at: entry.date)
            VStack(alignment: .leading, spacing: 4) {
                Caption(text: span.isExtraTime ? "extra time" : "life left")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text((span.isExtraTime ? "+" : "") + span.years.formatted())
                        .font(.system(size: heroSize, weight: .thin))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text(span.years == 1 ? "year" : "years")
                        .font(.title3.weight(.light))
                    Spacer(minLength: 0)
                    Text("\(span.weeks.formatted()) weeks")
                        .font(.subheadline.weight(.light))
                        .monospacedDigit()
                        .opacity(0.7)
                        .lineLimit(1)
                }
                ThinBar(value: lived, height: 8)
                    .padding(.vertical, 6)
                HStack {
                    Caption(text: "\(percent(lived)) lived")
                    Spacer()
                    Caption(text: "age \(LifeProgress.age(birthDate: life.birthDate, now: entry.date)) of about \(Int(life.expectancyYears.rounded()))")
                }
                Spacer(minLength: 0)
                // "Remember that you will die": the Stoic reminder behind the Life widget.
                Text("memento mori")
                    .font(.system(.footnote, design: .serif).italic())
                    .opacity(0.5)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Memento mori: remember that you will die")
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Caption(text: "life left")
                Text("Add your birthday in Ebb › Widgets.")
                    .font(.subheadline)
                    .opacity(0.7)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TimeAndLifeWidget: Widget {
    /// Large on iPhone, plus the taller Extra Large Portrait from iOS 27 (drag the
    /// widget's corner down in the Today View); Extra Large on iPad.
    private static var families: [WidgetFamily] {
        if #available(iOS 27.0, *) {
            return [.systemLarge, .systemExtraLarge, .systemExtraLargePortrait]
        }
        return [.systemLarge, .systemExtraLarge]
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EbbTimeAndLife", provider: TimeAndLifeProvider()) { entry in
            TimeAndLifeWidgetView(entry: entry)
        }
        .configurationDisplayName("Time & Life")
        .description("Time Ebb has given back, and the life you have left. Made for the Today View. Ebb Plus.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }
}
