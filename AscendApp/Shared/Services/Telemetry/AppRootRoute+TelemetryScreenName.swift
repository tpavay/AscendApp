import Foundation

extension AppRootRoute {
    /// The screen this route reports when it becomes the one thing the app is showing.
    ///
    /// Exhaustive on purpose: a new root route cannot ship without someone deciding what it
    /// is called in the funnel, because this switch stops compiling until they do.
    ///
    /// `nil` for ``AppRootRoute/mainApp``, which is a container rather than a destination -
    /// the selected tab reports its own screen, and an event above it would double every
    /// tab visit with a name nobody navigated to.
    var telemetryScreenName: TelemetryScreenName? {
        switch self {
        case .updateRequired: .appUpdateRequired
        case .signedOut: .landing
        case .signingIn: .authSigningIn
        case .restoringSession: .sessionRestoring
        case .resolving: .appAccessResolving
        case .onboarding: .onboardingFlow
        case .paywall: .appAccessGate
        case .mainApp: nil
        }
    }
}
