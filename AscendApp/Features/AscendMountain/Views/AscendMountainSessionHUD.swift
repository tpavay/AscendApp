import SwiftUI

/// The live Ascend Mountain read-out over the 3D world: the step count large enough to read
/// from a stair-stepper console, and one row of pace, time and heart rate (spec 4, 20, 43).
///
/// Every number is the session's own - `LiveClimbSessionViewModel` stays the authority - so
/// this screen can never disagree with Classic. The phase-1 prototype carries no rank; the
/// designed HUD with rank and ghosts replaces this once the feel is approved.
struct AscendMountainSessionHUD: View {
    let viewModel: LiveClimbSessionViewModel
    let debugState: MountainDebugState?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepsHero

#if DEBUG
            if let debugState {
                AscendMountainDebugOverlay(state: debugState)
            }
#endif

            Spacer(minLength: 0)

            statRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stepsHero: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(viewModel.totalRecordedSteps.formatted())
                    .font(.montserratBold(size: 60))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("STEPS")
                    .font(.montserratBold(size: 16))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let goalLine {
                Text(goalLine)
                    .font(.montserratBold(size: 14))
                    .tracking(0.6)
                    .foregroundStyle(Color.accent)
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
        .accessibilityElement(children: .combine)
    }

    /// What is left of the goal, when there is one; an open climb has no line at all.
    private var goalLine: String? {
        if let target = viewModel.mode.targetStepCount {
            let remaining = max(target - viewModel.totalRecordedSteps, 0)
            return "\(remaining.formatted()) TO GO"
        }
        if let targetClock = viewModel.targetDurationClock {
            return "GOAL \(targetClock)"
        }
        return nil
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            stat(value: viewModel.currentPaceDisplay, label: "SPM")
            stat(value: viewModel.elapsedClock, label: "ELAPSED")
            if let heartRate = viewModel.liveHeartRateStatus, case .connected(let beatsPerMinute, _) = heartRate {
                stat(value: beatsPerMinute.formatted(), label: "BPM")
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.montserratBold(size: 30))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.montserratBold(size: 11))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
