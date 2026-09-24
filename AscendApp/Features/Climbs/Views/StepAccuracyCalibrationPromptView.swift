import SwiftUI

/// Optional, skippable prompt shown after a climb completes, inviting the climber to enter what
/// their stair-stepper machine displayed. It never blocks saving the climb - the workout is
/// already saved by the time this can appear - and the entered count is stored alongside the
/// climb purely to improve the step-counting algorithm; the saved step count itself never
/// changes because of it.
struct StepAccuracyCalibrationPromptView: View {
    let appSteps: Int
    let onSubmit: (Int) -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var themeManager = ThemeManager.shared
    @State private var machineStepsText = ""

    private var effectiveColorScheme: ColorScheme {
        themeManager.effectiveColorScheme(for: colorScheme)
    }

    private var primaryTextStyle: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextStyle: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.68) : .black.opacity(0.58)
    }

    private var enteredSteps: Int? {
        Int(machineStepsText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sharpen the Count")
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(primaryTextStyle)

                Text(
                    "Enter what your machine showed. It helps Ascend improve step tracking - " +
                    "this climb's \(appSteps.formatted()) steps stay exactly as recorded."
                )
                .font(.montserratRegular(size: 14))
                .foregroundStyle(secondaryTextStyle)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                TextField("0", text: $machineStepsText)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.montserratBold(size: 34))
                    .foregroundStyle(primaryTextStyle)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .keyboardDoneToolbar()

                Text("steps")
                    .font(.montserratSemiBold(size: 14))
                    .foregroundStyle(secondaryTextStyle)
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .accessibilityLabel("Machine step count")

            VStack(spacing: 10) {
                Button {
                    guard let enteredSteps else { return }
                    onSubmit(enteredSteps)
                } label: {
                    Text("Submit")
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(Color.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(enteredSteps == nil || enteredSteps == 0)
                .opacity(enteredSteps == nil || enteredSteps == 0 ? 0.5 : 1)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.montserratBold(size: 14))
                        .foregroundStyle(secondaryTextStyle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 10)
        .appSheetBackground()
        .trackOnce(screen: .stepAccuracyCalibration)
        .onChange(of: machineStepsText) { _, newValue in
            let filtered = newValue.filter(\.isNumber)
            if filtered != newValue {
                machineStepsText = filtered
            }
        }
    }
}

#Preview {
    StepAccuracyCalibrationPromptView(appSteps: 500, onSubmit: { _ in }, onSkip: {})
        .appSheetStyle(.fitted())
}
