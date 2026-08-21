import SwiftUI

/// The circular glass control in an onboarding screen's leading corner, drawn as
/// whatever it actually does.
struct OnboardingLeadingControlButton: View {
    var control: OnboardingLeadingControl = .back
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0)
        .accessibilityLabel(control.accessibilityLabel)
        .accessibilityHidden(!isEnabled)
    }

    @ViewBuilder
    private var label: some View {
        let shape = RoundedRectangle(cornerRadius: OnboardingChromeMetrics.backButtonSize / 2, style: .continuous)
        let content = ZStack {
            Image(systemName: control.symbolName)
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

extension EnvironmentValues {
    /// Defaults to `.back` because every surface outside the opening onboarding
    /// screen has somewhere to go back to. A flow that does not sets it once, so
    /// the control and the action it is wired to can never disagree.
    @Entry var onboardingLeadingControl: OnboardingLeadingControl = .back
}

extension OnboardingLeadingControl {
    var symbolName: String {
        switch self {
        case .back:
            return "chevron.backward"
        case .signOut:
            return "rectangle.portrait.and.arrow.right"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .back:
            return "Back"
        case .signOut:
            return "Sign out"
        }
    }
}
