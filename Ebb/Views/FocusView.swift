//
//  FocusView.swift
//  Ebb
//
//  Screen Time blocking: scheduled focuses, quick focus sessions, and a daily limit.
//

import FamilyControls
import SwiftUI

struct FocusView: View {
    @Environment(FocusManager.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @State private var isPicking = false
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

                manageSection
                focusesSection
                sessionSection

                Section {
                    Toggle("Daily limit", isOn: $focus.limitEnabled)
                    if focus.limitEnabled {
                        Stepper("\(focus.limitMinutes) minutes a day", value: $focus.limitMinutes, in: 5...240, step: 5)
                    }
                } footer: {
                    Text("Once you've used your Focus now apps for this long in total, they stay blocked until midnight.")
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
            .sheet(item: $editingPeriod) { period in
                NavigationStack {
                    FocusEditor(period: period, isNew: !focus.workPeriods.contains { $0.id == period.id })
                }
                .ebbColorScheme()
            }
            .onAppear { focus.refresh() }
        }
    }

    private var manageSection: some View {
        Section {
            Button {
                editingPeriod = WorkPeriod(name: "Focus")
                Task { await focus.requestNotificationPermission() }
            } label: {
                Label("New focus", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.indigo)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Manage focus")
        } footer: {
            Text("A focus blocks the apps you choose on the days and hours you set, like work, study, or wind-down.")
        }
        .disabled(!focus.isAuthorized)
    }

    @ViewBuilder
    private var focusesSection: some View {
        if !focus.workPeriods.isEmpty {
            Section {
                ForEach(focus.workPeriods) { period in
                    Button {
                        editingPeriod = period
                    } label: {
                        FocusRow(period: period, isRunning: focus.isRunning(period))
                    }
                }
                .onDelete { focus.workPeriods.remove(atOffsets: $0) }
            } header: {
                Text("Your focuses")
            } footer: {
                Text("Tap a focus to change it. Swipe left to delete.")
            }
            .disabled(!focus.isAuthorized)
        }
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
            Button {
                isPicking = true
            } label: {
                LabeledContent("Apps to block", value: focus.selectionSummary)
            }
            .disabled(!focus.isAuthorized)
            Toggle("Strict mode", isOn: $focus.strictSessions)
        } header: {
            Text("Focus now")
        } footer: {
            Text("Block these apps right away for a set time. Strict mode removes the End button, so a session can't be cut short.")
        }
    }

    private static func label(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }
}

/// One focus in the list: name, schedule, apps, and whether it's blocking now.
private struct FocusRow: View {
    let period: WorkPeriod
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: period.mode == .allowOnly ? "lock.fill" : "moon.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.indigo.gradient))
                .opacity(period.isEnabled ? 1 : 0.4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(period.name)
                    .foregroundStyle(period.isEnabled ? .primary : .secondary)
                Text("\(period.daysDescription) · \(period.timeRange)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(period.appsSummary)
                    .font(.caption)
                    .foregroundStyle(period.hasApps || period.mode == .allowOnly ? Color.secondary : Color.orange)
            }
            Spacer(minLength: 8)
            if isRunning {
                Text("Now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.green))
            } else if !period.isEnabled {
                Text("Off").font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Create or edit a focus: name, hours, days, and its apps.
struct FocusEditor: View {
    @Environment(FocusManager.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @State var period: WorkPeriod
    let isNew: Bool
    @State private var isPicking = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $period.name)
                Toggle("On", isOn: $period.isEnabled)
            }
            Section {
                Picker("Mode", selection: $period.mode) {
                    ForEach(FocusBlockMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Button {
                    isPicking = true
                } label: {
                    LabeledContent(period.mode == .allowOnly ? "Apps to allow" : "Apps to block") {
                        Text(period.hasApps ? period.appsSummary : "Choose")
                    }
                }
            } header: {
                Text("Apps")
            } footer: {
                Text(period.mode == .allowOnly
                     ? "Everything is blocked except the apps you choose. Phone and other essentials stay available. Allow Ebb too, so your launcher widgets keep working."
                     : "Only the apps you choose are blocked. Everything else stays open.")
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
                    Button("Delete focus", role: .destructive) {
                        focus.workPeriods.removeAll { $0.id == period.id }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New focus" : period.name)
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(
            headerText: period.mode == .allowOnly
                ? "Choose what stays open. Everything else is blocked."
                : "Choose what to block during this focus.",
            isPresented: $isPicking,
            selection: $period.selection
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let index = focus.workPeriods.firstIndex(where: { $0.id == period.id }) {
                        focus.workPeriods[index] = period
                    } else {
                        focus.workPeriods.append(period)
                    }
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        !period.weekdays.isEmpty && period.start != period.end
            && !period.name.trimmingCharacters(in: .whitespaces).isEmpty
            && (period.hasApps || period.mode == .allowOnly)
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
