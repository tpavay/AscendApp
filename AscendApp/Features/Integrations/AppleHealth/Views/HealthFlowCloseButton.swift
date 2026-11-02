import SwiftUI

/// The close control in the corner of the Connect Apple Health screens, drawn in the same glass
/// circle as an onboarding screen's leading control so the reused screen looks like itself.
struct HealthFlowCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .frame(
                    width: OnboardingChromeMetrics.backButtonSize,
                    height: OnboardingChromeMetrics.backButtonSize
                )
                .glassEffect(
                    .regular.tint(.white.opacity(0.08)).interactive(),
                    in: RoundedRectangle(cornerRadius: OnboardingChromeMetrics.backButtonSize / 2, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}
