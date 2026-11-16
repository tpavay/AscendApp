import Foundation

/// How the sign-in screen's two buttons read after Sign in with Apple has failed.
///
/// A refusal from Apple's sheet is the one sign-in failure a climber can often fix on the phone and
/// the one that can repeat on the same device for days (an iPad failed four times across three
/// days in production), so the screen never leaves it as a dead end: the first failure says what to
/// check and offers the same button again, labelled as a retry; the second puts the other provider
/// first, because a climber refused twice is better served by the way that works than by a third
/// identical tap. Nothing retries on its own.
struct AppleRetryPresentation: Equatable {
    /// Failures in a row at which Google takes the first, prominent place.
    static let failuresBeforeGoogleLeads = 2

    let appleTitle: String
    let googleTitle: String
    let googleLeads: Bool

    init(appleFailureCount: Int) {
        appleTitle = appleFailureCount == 0 ? "Continue with Apple" : "Try Apple again"
        googleTitle = "Continue with Google"
        googleLeads = appleFailureCount >= Self.failuresBeforeGoogleLeads
    }
}
