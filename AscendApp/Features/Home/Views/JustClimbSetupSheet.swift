import SwiftUI

struct JustClimbSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onStart: (JustClimbGoal) -> Void

    @State private var selectedKind: JustClimbGoalKind = .open
    @State private var durationMinutes = JustClimbGoal.defaultDurationMinutes
    @State private var stepCount = JustClimbGoal.defaultStepCount

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            goalPicker
            goalControls

            Spacer(minLength: 0)

            Button {
                onStart(
                    JustClimbGoal(
                        kind: selectedKind,
                        durationMinutes: durationMinutes,
                        stepCount: stepCount
                    )
                )
                dismiss()
            } label: {
                Text("START")
                    .font(.montserratBold(size: 14))
                    .tracking(1.1)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("JUST CLIMB")
                .font(.montserratBold(size: 24))
                .foregroundStyle(.white)

            Text("Set a goal or climb open.")
                .font(.montserratMedium(size: 14))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var goalPicker: some View {
        HStack(spacing: 6) {
            ForEach(JustClimbGoalKind.allCases) { kind in
                Button {
                    withAnimation(.smooth(duration: 0.18)) {
                        selectedKind = kind
                    }
                } label: {
                    Text(kind.title.uppercased())
                        .font(.montserratBold(size: 11))
                        .tracking(0.9)
                        .foregroundStyle(selectedKind == kind ? .black : .white.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if selectedKind == kind {
                                Capsule(style: .continuous)
                                    .fill(Color.accent)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.07), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var goalControls: some View {
        switch selectedKind {
        case .open:
            openGoalRow
        case .duration:
            numericGoalRow(
                title: "DURATION",
                value: "\(durationMinutes)",
                unit: "MIN",
                decrementDisabled: durationMinutes <= JustClimbGoal.minimumDurationMinutes,
                incrementDisabled: durationMinutes >= JustClimbGoal.maximumDurationMinutes,
                decrement: { durationMinutes = max(JustClimbGoal.minimumDurationMinutes, durationMinutes - 5) },
                increment: { durationMinutes = min(JustClimbGoal.maximumDurationMinutes, durationMinutes + 5) }
            )
        case .steps:
            numericGoalRow(
                title: "STEPS",
                value: stepCount.formatted(),
                unit: "STEPS",
                decrementDisabled: stepCount <= JustClimbGoal.minimumStepCount,
                incrementDisabled: stepCount >= JustClimbGoal.maximumStepCount,
                decrement: { stepCount = max(JustClimbGoal.minimumStepCount, stepCount - 100) },
                increment: { stepCount = min(JustClimbGoal.maximumStepCount, stepCount + 100) }
            )
        }
    }

    private var openGoalRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "infinity")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.accent)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.white.opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text("NO GOAL")
                    .font(.montserratBold(size: 13))
                    .foregroundStyle(.white)

                Text("Climb until you stop.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    private func numericGoalRow(
        title: String,
        value: String,
        unit: String,
        decrementDisabled: Bool,
        incrementDisabled: Bool,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.montserratBold(size: 12))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.48))

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(value)
                        .font(.montserratBold(size: 34))
                        .foregroundStyle(.white)
                        .monospacedDigit()

                    Text(unit)
                        .font(.montserratBold(size: 11))
                        .tracking(0.8)
                        .foregroundStyle(Color.accent)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                stepperButton(systemName: "minus", disabled: decrementDisabled, action: decrement)
                stepperButton(systemName: "plus", disabled: incrementDisabled, action: increment)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    private func stepperButton(
        systemName: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(disabled ? .white.opacity(0.22) : .white)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(.white.opacity(disabled ? 0.04 : 0.12))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

#Preview {
    JustClimbSetupSheet { _ in }
}
