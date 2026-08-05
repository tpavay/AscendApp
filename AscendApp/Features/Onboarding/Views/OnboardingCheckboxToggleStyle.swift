import SwiftUI

/// The square tick box used for opt-ins on onboarding screens.
///
/// The rendered row is a button, so the on/off value comes from the
/// accessibility representation rather than from the `Toggle` behind the style:
/// VoiceOver describes what a style draws, not what it was applied to. Without
/// the representation a blind climber would hear "button" and no state, and
/// could not tell whether Ascend was about to email them. The representation is
/// built from the configuration rather than from a fresh `Toggle`, which is the
/// initializer SwiftUI provides for a style to restate its own control without
/// re-entering itself.
///
/// The label is part of the same target as the box. Nothing here animates: the
/// box takes its new state in one frame, in every Reduce Motion state.
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
        .accessibilityRepresentation {
            Toggle(configuration)
        }
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
