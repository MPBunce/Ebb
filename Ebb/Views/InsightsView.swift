//
//  InsightsView.swift
//  Ebb
//

import Charts
import SwiftUI

struct InsightsView: View {
    @Environment(LauncherStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let insights = Insights(events: store.events)

        NavigationStack {
            List {
                Section {
                    HStack {
                        stat("\(insights.today.opened)", "opened today")
                        Spacer()
                        stat("\(insights.today.resisted)", "let go today")
                        Spacer()
                        stat("\(insights.resistStreak)", "day streak")
                    }
                    .padding(.vertical, 6)
                    let saved = TimeSaved.load()
                    LabeledContent("Time given back", value: "\(saved.formattedHours) h since \(saved.since.formatted(date: .abbreviated, time: .omitted))")
                } footer: {
                    Text("“Let go” counts the times you backed out during a mindful pause. The streak counts consecutive days with at least one.")
                }

                Section("Last 7 days") {
                    Chart(insights.week) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Opens", day.opened)
                        )
                        .foregroundStyle(by: .value("Kind", "Opened"))
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Opens", day.resisted)
                        )
                        .foregroundStyle(by: .value("Kind", "Let go"))
                    }
                    .chartForegroundStyleScale(["Opened": Color.primary.opacity(0.75), "Let go": Color.secondary.opacity(0.35)])
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                    .frame(height: 160)
                    .padding(.vertical, 8)
                }

                if !insights.topApps.isEmpty {
                    Section("Most opened this week") {
                        ForEach(insights.topApps) { app in
                            LabeledContent(app.name, value: "\(app.count)")
                        }
                    }
                }

                if !insights.recentIntentions.isEmpty {
                    Section("What you opened apps for") {
                        ForEach(insights.recentIntentions, id: \.self) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.intention ?? "")
                                Text("\(event.name) · \(event.date.formatted(.relative(presentation: .named)))\(event.outcome == .resisted ? " · let go" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Text("Only apps opened through Ebb are counted. Everything stays on this iPhone and is deleted after \(LauncherStore.historyDays) days.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: .thin))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
