import SwiftUI

struct OnboardingValueShowcaseButton: View {
    let title: String
    var height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(
            OnboardingPrimaryCTAButtonStyle(
                height: height,
                cornerRadius: 12,
                fontSize: 16,
                tint: OnboardingValuePalette.lime,
                shadowOpacity: 0
            )
        )
    }
}
