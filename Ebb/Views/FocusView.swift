//
//  FocusView.swift
//  Ebb
//
//  Screen Time blocking: focus sessions, nightly wind-down, and a daily limit.
//

import FamilyControls
import SwiftUI

struct FocusView: View {
    @Environment(FocusManager.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @State private var isPicking = false
    @State private var isPickingAllowed = false
    @State private var editingPeriod: WorkPeriod?
    @AppStorage(AppGroup.Key.shieldTitle, store: AppGroup.defaults) private var shieldTitle = ""
    @AppStorage(AppGroup.Key.shieldSubtitle, store: AppGroup.defaults) private var shieldSubtitle = ""

    var body: some View {
        @Bindable var focus = focus

        NavigationStack {
            Form {
                if !focus.isAuthorized {
                    Section {
                        VStack(spacing: 14) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 34))
                                .foregroundStyle(.indigo)
                                .frame(width: 64, height: 64)
                                .background(Circle().fill(.indigo.opacity(0.15)))
                            Text("Turn on blocking")
                                .font(.title3.weight(.semibold))
                            Text("Ebb uses Screen Time to block distracting apps during work and focus. Your choices stay private: Apple only gives Ebb anonymous tokens, never which apps you picked.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                Task { await focus.requestAuthorization() }
                            } label: {
                                Text("Allow Screen Time access")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(.indigo)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }

                workSection

                Section {
                    Button {
                        isPicking = true
                    } label: {
                        LabeledContent("Blocked apps", value: focus.selectionSummary)
                    }
                    .disabled(!focus.isAuthorized)
                } footer: {
                    Text("These apps are blocked during focus sessions, wind-down, and once you reach your daily limit.")
                }

                sessionSection

                Section {
                    Toggle("Nightly wind-down", isOn: $focus.nightlyEnabled)
                    if focus.nightlyEnabled {
                        DatePicker("From", selection: minutesBinding($focus.nightlyStart), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: minutesBinding($focus.nightlyEnd), displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Blocks your apps every night so your phone doesn't follow you to bed.")
                }
                .disabled(!focus.isAuthorized || !focus.hasSelection)

                Section {
                    Toggle("Daily limit", isOn: $focus.limitEnabled)
                    if focus.limitEnabled {
                        Stepper("\(focus.limitMinutes) minutes a day", value: $focus.limitMinutes, in: 5...240, step: 5)
                    }
                } footer: {
                    Text("Once you've used these apps for this long in total, they stay blocked until midnight.")
                }
                .disabled(!focus.isAuthorized || !focus.hasSelection)

                Section("Block screen message") {
                    TextField("Let it ebb.", text: $shieldTitle)
                    TextField("This app is resting right now…", text: $shieldSubtitle, axis: .vertical)
                }

                if let error = focus.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $isPicking, selection: $focus.selection)
            .familyActivityPicker(
                headerText: "Choose what stays open during work. Everything else is blocked.",
                isPresented: $isPickingAllowed,
                selection: $focus.allowedSelection
            )
            .sheet(item: $editingPeriod) { period in
                NavigationStack {
                    WorkPeriodEditor(period: period, isNew: !focus.workPeriods.contains { $0.id == period.id })
                }
                .ebbColorScheme()
            }
            .onAppear { focus.refresh() }
        }
    }

    @ViewBuilder
    private var workSection: some View {
        Section {
            if let current = focus.currentWorkPeriod, focus.isInWorkPeriod {
                Label("\(current.name) until \(WorkPeriod.format(current.end))", systemImage: "briefcase.fill")
            }
            ForEach(focus.workPeriods) { period in
                Button {
                    editingPeriod = period
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(period.name)
                                .foregroundStyle(.primary)
                            Text("\(period.daysDescription) · \(period.timeRange)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !period.isEnabled {
                            Text("Off").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Button {
                editingPeriod = WorkPeriod()
                Task { await focus.requestNotificationPermission() }
            } label: {
                Label("Add work time", systemImage: "plus")
            }
            Button {
                isPickingAllowed = true
            } label: {
                LabeledContent("Allowed during work", value: focus.allowedSummary)
            }
        } header: {
            Text("Work time")
        } footer: {
            Text("During work time, every app is blocked except the ones you allow. Phone and other essentials Apple protects stay available. Tip: allow Ebb too, so your launcher keeps working.")
        }
        .disabled(!focus.isAuthorized)
    }

    @ViewBuilder
    private var sessionSection: some View {
        @Bindable var focus = focus

        Section {
            if let end = focus.sessionEnd, end > .now {
                LabeledContent("Focusing until", value: end.formatted(date: .omitted, time: .shortened))
                if focus.canEndSession {
                    Button("End session", role: .destructive) { focus.endSession() }
                } else {
                    Text("Strict mode is on. This session can't be ended early.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(FocusManager.sessionLengths, id: \.self) { minutes in
                            Button(Self.label(minutes)) { focus.startSession(minutes: minutes) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .disabled(!focus.isAuthorized || !focus.hasSelection)
            }
            Toggle("Strict mode", isOn: $focus.strictSessions)
        } header: {
            Text("Focus now")
        } footer: {
            Text("Strict mode removes the End button, so a session can't be cut short.")
        }
    }

    private static func label(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    /// Bridges minutes-after-midnight to the Date a DatePicker needs.
    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                  minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

/// Create or edit a work period: name, hours, and days.
private struct WorkPeriodEditor: View {
    @Environment(FocusManager.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @State var period: WorkPeriod
    let isNew: Bool

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $period.name)
                Toggle("On", isOn: $period.isEnabled)
            }
            Section("Hours") {
                DatePicker("Starts", selection: minutes($period.start), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: minutes($period.end), displayedComponents: .hourAndMinute)
            }
            Section {
                WeekdayPicker(selection: $period.weekdays)
                    .padding(.vertical, 4)
            } header: {
                Text("Days")
            } footer: {
                Text("If it ends after midnight, it counts for the day it starts.")
            }
            if !isNew {
                Section {
                    Button("Delete work time", role: .destructive) {
                        focus.workPeriods.removeAll { $0.id == period.id }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New work time" : period.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    if let index = focus.workPeriods.firstIndex(where: { $0.id == period.id }) {
                        focus.workPeriods[index] = period
                    } else {
                        focus.workPeriods.append(period)
                    }
                    dismiss()
                }
                .disabled(period.weekdays.isEmpty || period.start == period.end || period.name.isEmpty)
            }
        }
    }

    private func minutes(_ value: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60,
                                  second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            value.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

/// Seven tappable day circles, starting on the locale's first weekday.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    private var days: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Circle().fill(isOn ? Color.primary : Color.secondary.opacity(0.15)))
                        .foregroundStyle(isOn ? Color(.systemBackground) : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
