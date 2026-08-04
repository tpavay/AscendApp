import SwiftUI

/// The square tick box used for opt-ins on onboarding screens.
///
/// Built as a `ToggleStyle` rather than a button so VoiceOver reads it as a
/// control with an on/off value, and so the label is part of the same target.
/// Nothing here animates: the box takes its new state in one frame, in every
/// Reduce Motion state.
struct OnboardingCheckboxToggleStyle: ToggleStyle {
    let boxSize: CGFloat
    let cornerRadius: CGFloat
    let spacing: CGFloat
    /// Floor for the whole row, so the tick box never becomes a small target.
    let minimumTargetHeight: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: spacing) {
                box(isOn: configuration.isOn)

                configuration.label

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: minimumTargetHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func box(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(isOn ? OnboardingValuePalette.lime : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isOn ? OnboardingValuePalette.lime : .white.opacity(0.42),
                        lineWidth: 1.5
                    )
            )
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: boxSize * 0.6, weight: .bold))
                        .foregroundStyle(.black.opacity(0.9))
                }
            }
            .frame(width: boxSize, height: boxSize)
    }
}
