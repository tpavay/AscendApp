import SwiftUI

/// The onboarding leading control, rendered as whatever the surrounding flow
/// declared it to be. Outside post-auth onboarding nothing declares anything, so
/// it stays the back chevron every other surface wires it up as.
struct OnboardingBackButton: View {
    @Environment(\.onboardingLeadingControl) private var control

    var isEnabled = true
    let action: () -> Void

    var body: some View {
        OnboardingLeadingControlButton(
            control: control,
            isEnabled: isEnabled,
            action: action
        )
    }
}
