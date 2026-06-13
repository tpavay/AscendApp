import SwiftUI

struct OnboardingPrimaryCTAButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var height: CGFloat = 58
    var cornerRadius: CGFloat = 14
    var fontSize: CGFloat = 17
    var tint: Color = Color.ascendAccent
    var shadowOpacity: Double = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.montserratBold(size: fontSize))
            .foregroundStyle(.black.opacity(isEnabled ? 0.9 : 0.5))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
                    .shadow(
                        color: tint.opacity(configuration.isPressed ? shadowOpacity * 0.55 : shadowOpacity),
                        radius: configuration.isPressed ? 11 : 18,
                        x: 0,
                        y: configuration.isPressed ? 6 : 10
                    )
            )
            .opacity(isEnabled ? 1 : 0.58)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

#Preview("Onboarding CTA Button") {
    VStack(spacing: 24) {
        Button("GET STARTED") {}
            .buttonStyle(
                OnboardingPrimaryCTAButtonStyle(
                    height: 62,
                    tint: .accent,
                    shadowOpacity: 0
                )
            )

        Button("Continue") {}
            .buttonStyle(
            OnboardingPrimaryCTAButtonStyle(
                height: 58,
                tint: .accent,
                shadowOpacity: 0
            )
            )

        Button("Disabled") {}
            .buttonStyle(
            OnboardingPrimaryCTAButtonStyle(
                height: 58,
                tint: .accent,
                shadowOpacity: 0
            )
            )
            .disabled(true)
    }
    .padding(28)
    .background(Color.black)
}
