import SwiftUI

/// The "Just Me" tab of the live climb session: a vertical summit progress rail
/// alongside a 2x2 grid of live stats (elapsed, steps, pace, rank) that fills the
/// available space. Pace updates in real time in its own card.
struct LiveClimbJustMeView: View {
    let viewModel: LiveClimbSessionViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            LiveClimbProgressRail(
                progress: viewModel.totalProgressFraction,
                summitSteps: viewModel.mode.targetStepCount
            )
            .frame(width: 64)
            .frame(maxHeight: .infinity)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    statCard(value: viewModel.elapsedClock, label: "ELAPSED")
                    statCard(value: viewModel.totalRecordedSteps.formatted(), label: "STEPS")
                }

                HStack(spacing: 12) {
                    statCard(value: viewModel.currentStepsPerMinute.formatted(), label: "PACE · SPM")
                    statCard(value: viewModel.currentRankDisplay, label: "CURRENT RANK")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.montserratBold(size: 38))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(label)
                .font(.montserratBold(size: 11))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }
}

/// Vertical progress rail running from START (bottom) to SUMMIT (top) with a
/// halfway marker and a glowing dot at the climber's current progress.
private struct LiveClimbProgressRail: View {
    let progress: Double
    let summitSteps: Int?
    var tint: Color = .accent

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text("SUMMIT")
                    .font(.montserratBold(size: 8))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))

                if let summitSteps {
                    Text(summitSteps.formatted())
                        .font(.montserratBold(size: 9))
                        .foregroundStyle(.white.opacity(0.62))
                        .monospacedDigit()
                }
            }

            track
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("START")
                .font(.montserratBold(size: 8))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let centerX = proxy.size.width / 2
            let clamped = min(max(progress, 0), 1)
            let fillHeight = height * clamped

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(width: 6, height: height)
                    .position(x: centerX, y: height / 2)

                Capsule()
                    .fill(tint)
                    .frame(width: 6, height: fillHeight)
                    .position(x: centerX, y: height - fillHeight / 2)

                Rectangle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 14, height: 2)
                    .position(x: centerX, y: height / 2)

                Text("HALF")
                    .font(.montserratBold(size: 7.5))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.5))
                    .position(x: centerX, y: height / 2 - 10)

                Circle()
                    .fill(tint)
                    .frame(width: 14, height: 14)
                    .shadow(color: tint.opacity(0.9), radius: 8)
                    .position(x: centerX, y: height - fillHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}
