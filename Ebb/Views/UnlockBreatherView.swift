//
//  UnlockBreatherView.swift
//  Ebb
//
//  Reached from the block screen's "Take a breath" button. A short breathing pause,
//  then the user chooses how many minutes of use they need before the app is blocked again.
//

import FamilyControls
import ManagedSettings
import SwiftUI

struct UnlockBreatherView: View {
    @Environment(FocusManager.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKey.pauseSeconds) private var pauseSeconds = 5

    let token: ApplicationToken

    @State private var remaining = 0
    @State private var breatheIn = false
    @State private var grantedMinutes: Int?

    static let choices = [5, 10, 15, 30]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(2.2)
                .frame(height: 70)

            if let grantedMinutes {
                granted(minutes: grantedMinutes)
            } else if remaining > 0 {
                breathing
            } else {
                chooser
            }

            Spacer()

            if grantedMinutes == nil {
                Button("Never mind") {
                    TimeSaved.recordResist()
                    dismiss()
                }
                .font(.body.weight(.medium))
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task {
            remaining = max(pauseSeconds, 3)
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

    private var breathing: some View {
        VStack(spacing: 20) {
            Circle()
                .stroke(.secondary, lineWidth: 1)
                .frame(width: 150, height: 150)
                .scaleEffect(breatheIn ? 1 : 0.55)
                .opacity(breatheIn ? 0.9 : 0.4)
                .overlay {
                    Text("\(remaining)")
                        .font(.system(size: 30, weight: .thin))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
                .accessibilityHidden(true)
            Text("Breathe")
                .font(.title2.weight(.light))
            Text("This app is blocked right now. Take a moment before deciding.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var chooser: some View {
        VStack(spacing: 18) {
            Text("How long do you need?")
                .font(.title2.weight(.light))
            Text("It unlocks for this much use, then blocks again. Unused time ends at midnight.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Self.choices, id: \.self) { minutes in
                    Button {
                        focus.grantAllowance(for: token, minutes: minutes)
                        withAnimation { grantedMinutes = minutes }
                    } label: {
                        Text("\(minutes) min")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 6)
            if let error = focus.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func granted(minutes: Int) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .thin))
            Text("Unlocked for \(minutes) minutes of use")
                .font(.title3.weight(.light))
                .multilineTextAlignment(.center)
            Text("Go back to the app when you're ready. It blocks again once the time is used.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
    }
}
