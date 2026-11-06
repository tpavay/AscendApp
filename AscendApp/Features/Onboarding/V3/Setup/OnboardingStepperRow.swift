import SwiftUI

/// A labelled value with a minus and a plus, for the climber card's height and weight. Holding
/// either button repeats, because walking from 160 lb to 215 lb a pound at a time is not a
/// choice anyone should have to make. VoiceOver adjusts it with the rotor's increment and
/// decrement.
struct OnboardingStepperRow: View {
    let title: String
    let value: String?
    let onStep: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var valueSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.custom("Montserrat-ExtraBold", size: 12))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(OnboardingV3Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            RepeatingStepButton(symbol: "minus") { onStep(-1) }

            Group {
                if let value {
                    Text(value)
                        .font(.custom("Montserrat-Black", fixedSize: valueSize))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Capsule()
                        .fill(OnboardingV3Palette.chipBorder)
                        .frame(width: 22, height: 5)
                }
            }
            .frame(minWidth: 86)

            RepeatingStepButton(symbol: "plus", tint: OnboardingV3Palette.accent) { onStep(1) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .onboardingCard(cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "Not set")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onStep(1)
            case .decrement: onStep(-1)
            @unknown default: break
            }
        }
    }
}

private struct RepeatingStepButton: View {
    let symbol: String
    var tint: Color = .white
    let onStep: () -> Void

    var body: some View {
        Button(action: onStep) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(OnboardingV3Palette.controlFill)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityHidden(true)
    }
}
