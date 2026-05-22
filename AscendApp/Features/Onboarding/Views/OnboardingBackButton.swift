import SwiftUI

struct OnboardingBackButton: View {
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(
                    width: OnboardingChromeMetrics.backButtonSize,
                    height: OnboardingChromeMetrics.backButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0)
        .accessibilityLabel("Back")
        .accessibilityHidden(!isEnabled)
    }
}
