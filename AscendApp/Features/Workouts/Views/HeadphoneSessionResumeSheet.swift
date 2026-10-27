import SwiftUI

/// The sheet a session resumed after a process death opens with, over the already-counting
/// session: how long Ascend was not counting and why, the machine's count to credit the gap,
/// Save first, keep counting second.
///
/// Save leads because the climber who comes back to a dead session has usually already finished
/// on the machine (2026-10-23: the recovery screen led with Resume Live, the climber resumed, and
/// a 22-minute climb saved as 19:32). Keep counting stays one tap away for the climber mid-climb.
struct HeadphoneSessionResumeSheet: View {
    let notice: HeadphoneSessionResumeNotice
    let sessionLabel: String
    let onSave: (Int?) -> Void
    let onKeepCounting: (Int?) -> Void

    @State private var stepsText = ""
    @FocusState private var isStepFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.ascendCaution)
                    .accessibilityHidden(true)

                Text(notice.headline)
                    .font(.montserratBold(size: 24))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(notice.explanation)
                    .font(.montserratMedium(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Machine's current steps")
                    .font(.montserratSemiBold(size: 13))
                    .foregroundStyle(.white.opacity(0.78))

                HStack(spacing: 10) {
                    TextField("\(notice.suggestedSteps)", text: $stepsText)
                        .keyboardType(.numberPad)
                        .focused($isStepFieldFocused)
                        .font(.montserratBold(size: 30))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel("Machine's current steps")

                    Text("steps")
                        .font(.montserratSemiBold(size: 14))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )

                if let phoneEstimate = notice.phoneEstimateSteps, phoneEstimate > 0 {
                    Text("Your phone counted about \(phoneEstimate.formatted()) steps while Ascend was off. That is the phone's estimate, not the machine's number - check it.")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(Color.ascendAccent.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Ascend last counted \(notice.detectedSteps.formatted()) steps.")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            VStack(spacing: 10) {
                Button {
                    isStepFieldFocused = false
                    onSave(enteredSteps)
                } label: {
                    Text("Save \(sessionLabel)")
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.ascendAccent)
                        )
                }
                .buttonStyle(.plain)
                .disabled((enteredSteps ?? notice.suggestedSteps) <= 0)

                Button {
                    isStepFieldFocused = false
                    onKeepCounting(enteredSteps)
                } label: {
                    Text("Keep counting live")
                        .font(.montserratBold(size: 15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.11))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedBackground()
        .trackOnce(screen: .headphoneSessionResume)
        .onAppear {
            if stepsText.isEmpty {
                stepsText = String(notice.suggestedSteps)
            }
        }
        .onChange(of: notice.suggestedSteps) { previous, suggested in
            // The phone's estimate arrives a moment after the sheet; adopt it unless the climber
            // has already started typing something else.
            if stepsText.isEmpty || stepsText == String(previous) {
                stepsText = String(suggested)
            }
        }
        .onChange(of: stepsText) { _, newValue in
            let filtered = newValue.filter(\.isNumber)
            if filtered != newValue {
                stepsText = filtered
            }
        }
    }

    /// The typed count, or nil when the field was left at the draft's own number - which is not a
    /// correction and must not be recorded as one.
    private var enteredSteps: Int? {
        guard let value = Int(stepsText) else { return nil }
        return value == notice.detectedSteps ? nil : value
    }
}
