//
//  MindfulPauseView.swift
//  Ebb
//
//  A short breathing pause before opening an app marked as mindful. Backing out is
//  celebrated and counted in Insights.
//

import SwiftUI

struct MindfulPauseView: View {
    @Environment(LauncherStore.self) private var store
    @AppStorage(PrefKey.pauseSeconds) private var pauseSeconds = 5
    @AppStorage(PrefKey.askWhy) private var askWhy = true

    let target: LaunchTarget

    @State private var remaining = 0
    @State private var breatheIn = false
    @State private var intention = ""
    @FocusState private var intentionFocused: Bool

    private var opensToday: Int {
        let start = Calendar.current.startOfDay(for: .now)
        return store.events.count { $0.targetID == target.id && $0.outcome == .opened && $0.date >= start }
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Circle()
                .stroke(.secondary, lineWidth: 1)
                .frame(width: 160, height: 160)
                .scaleEffect(breatheIn ? 1.0 : 0.55)
                .opacity(breatheIn ? 0.9 : 0.4)
                .overlay {
                    Text(remaining > 0 ? "\(remaining)" : "")
                        .font(.system(size: 32, weight: .thin))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(remaining > 0 ? "Breathe" : "Still want \(target.name)?")
                    .font(.title2.weight(.light))
                Text(opensCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if askWhy {
                TextField("What are you opening it for?", text: $intention)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($intentionFocused)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Divider() }
                    .padding(.horizontal, 48)
                    .submitLabel(.done)
            }

            Spacer()

            VStack(spacing: 14) {
                Button {
                    store.open(target, intention: intention)
                } label: {
                    Text("Open \(target.name)")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .disabled(remaining > 0)

                Button("Never mind") {
                    store.resist(target, intention: intention)
                }
                .font(.body.weight(.medium))
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task {
            remaining = max(pauseSeconds, 1)
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breatheIn = true
            }
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                withAnimation { remaining -= 1 }
            }
        }
    }

    private var opensCaption: String {
        switch opensToday {
        case 0: "First time today."
        case 1: "You've opened it once today."
        default: "You've opened it \(opensToday) times today."
        }
    }
}
