import Foundation

extension AppRootRoute {
    /// The screen this route reports when it becomes the one thing the app is showing.
    ///
    /// Exhaustive on purpose: a new root route cannot ship without someone deciding what it
    /// is called in the funnel, because this switch stops compiling until they do.
    ///
    /// `nil` for ``AppRootRoute/mainApp`` and ``AppRootRoute/preAuthOnboarding``, which are
    /// containers rather than destinations - the selected tab and the current onboarding step
    /// report their own screens, and an event above them would double every visit with a name
    /// nobody navigated to.
    var telemetryScreenName: TelemetryScreenName? {
        switch self {
        case .updateRequired: .appUpdateRequired
        case .signedOut: .landing
        case .preAuthOnboarding: nil
        case .signingIn: .authSigningIn
        case .restoringSession: .sessionRestoring
        case .resolving: .appAccessResolving
        case .onboarding: .onboardingFlow
        case .paywall: .appAccessGate
        case .mainApp: nil
        }
    }
}
