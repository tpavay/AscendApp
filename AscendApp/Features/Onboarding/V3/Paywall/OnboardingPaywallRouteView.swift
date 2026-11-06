import SwiftUI

/// The root's `.onboardingPaywall` route: the onboarding flow, always carrying the account routes
/// the app-access gate carries. They are parameters rather than an optional environment value here
/// because this route cannot ship without them.
struct OnboardingPaywallRouteView: View {
    let coordinator: OnboardingV3Coordinator
    let onDeleteAccount: @MainActor () -> Void
    let onSignOut: @MainActor () -> Void

    var body: some View {
        OnboardingV3FlowView(coordinator: coordinator)
            .environment(\.onboardingPaywallAccountActions, OnboardingPaywallAccountActions(
                onDeleteAccount: onDeleteAccount,
                onSignOut: onSignOut
            ))
    }
}
