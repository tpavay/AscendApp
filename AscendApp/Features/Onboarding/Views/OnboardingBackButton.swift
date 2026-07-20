import SwiftUI

struct OnboardingBackButton: View {
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0)
        .accessibilityLabel("Back")
        .accessibilityHidden(!isEnabled)
    }

    @ViewBuilder
    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: OnboardingChromeMetrics.backButtonSize / 2, style: .continuous)
        let content = ZStack {
            Image(systemName: "chevron.backward")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
        }
        .frame(
            width: OnboardingChromeMetrics.backButtonSize,
            height: OnboardingChromeMetrics.backButtonSize
        )
        .contentShape(shape)

        content
            .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: shape)
    }
}
