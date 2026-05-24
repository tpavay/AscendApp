//
//  LeaderboardCelebrationScreen.swift
//  AscendApp
//

import SwiftUI

struct LeaderboardCelebrationScreen: View {
    let snapshot: LeaderboardCelebrationSnapshot
    let onDone: () -> Void

    @State private var hasStarted = false
    @State private var titleOpacity: Double = 0
    @State private var valueOpacity: Double = 0
    @State private var valueProgress: Double = 0
    @State private var listOpacity: Double = 0
    @State private var userRowOffset: CGFloat = 24
    @State private var buttonOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            VStack(spacing: 8) {
                Text("WEEKLY LEADERBOARD")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)

                Text(snapshot.metricDisplayName)
                    .font(.montserratBold(size: 30))
                    .foregroundStyle(.white)

                HStack(alignment: .center, spacing: 12) {
                    Text(snapshot.formattedPreviousValue)
                        .font(.montserratMedium(size: 16))
                        .foregroundStyle(.secondary)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.accent)

                    Text(formattedAnimatedValue)
                        .font(.montserratBold(size: 28))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
            .opacity(titleOpacity)
            .padding(.horizontal, 24)

            VStack(spacing: 8) {
                ForEach(Array(snapshot.nearbyEntries.enumerated()), id: \.element.id) { index, entry in
                    CelebrationLeaderboardRow(entry: entry)
                        .offset(y: entry.isCurrentUser ? userRowOffset : 0)
                        .opacity(listOpacity)
                        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: userRowOffset)
                        .animation(.easeIn(duration: 0.25).delay(Double(index) * 0.04), value: listOpacity)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .opacity(valueOpacity)

            Spacer()

            Button {
                TelemetryManager.shared.log(.celebrationScreen2Completed)
                TelemetryManager.shared.log(.celebrationDismissed)
                onDone()
            } label: {
                Text("Done")
                    .font(.montserratSemiBold(size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(.accent)
                    )
            }
            .opacity(buttonOpacity)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await runSequence()
        }
    }

    private var formattedAnimatedValue: String {
        let currentValue = snapshot.previousValue + ((snapshot.newValue - snapshot.previousValue) * valueProgress)
        switch snapshot.bestMetric {
        case .climb, .workouts:
            return currentValue.formatted(.number.precision(.fractionLength(0)))
        case .duration:
            let totalSeconds = Int(currentValue.rounded())
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        case .pace:
            let formatted = currentValue.formatted(.number.precision(.fractionLength(1)))
            return "\(formatted) steps/min"
        }
    }

    @MainActor
    private func runSequence() async {
        let haptics = HapticsManager.shared
        let sounds = CelebrationSoundManager.shared

        withAnimation(.easeIn(duration: 0.24)) {
            titleOpacity = 1
            valueOpacity = 1
        }

        try? await Task.sleep(for: .milliseconds(180))

        withAnimation(.easeInOut(duration: 0.9)) {
            valueProgress = 1
        }
        await animateValueTicks(haptics: haptics, sounds: sounds, duration: 0.9)

        haptics.trigger(.mediumImpact)
        sounds.playStatLand()

        try? await Task.sleep(for: .milliseconds(140))

        withAnimation(.easeIn(duration: 0.24)) {
            listOpacity = 1
        }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
            userRowOffset = 0
        }
        haptics.trigger(.success)

        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.easeIn(duration: 0.22)) {
            buttonOpacity = 1
        }
    }

    @MainActor
    private func animateValueTicks(
        haptics: HapticsManager,
        sounds: CelebrationSoundManager,
        duration: Double
    ) async {
        let tickCount = 6
        let interval = max(40, Int((duration / Double(tickCount)) * 1000))
        for index in 0..<tickCount {
            haptics.trigger(.lightImpact)
            if index.isMultiple(of: 2) {
                sounds.playCountTick()
            }
            if index < tickCount - 1 {
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }
}
