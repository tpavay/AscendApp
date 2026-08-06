import Foundation

/// Where a recorded email consent decision was made.
///
/// beehiiv can ask for the signup source and method behind any address it is
/// asked to mail, so the origin is stored alongside the choice rather than
/// reconstructed later from timestamps. The server writes its own case for the
/// unsubscribe link; these are the two the app can produce.
enum LifecycleEmailConsentSource: String, Sendable, CaseIterable {
    /// The pre-ticked checkbox on the onboarding notifications step.
    case onboarding
    /// The switch on the Email preference screen.
    case settings
}
