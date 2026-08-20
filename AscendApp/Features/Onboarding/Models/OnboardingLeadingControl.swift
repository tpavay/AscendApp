import Foundation

/// What an onboarding screen's leading chrome control actually does.
///
/// The first post-auth screen has nothing behind it, so a back chevron there is a
/// control that draws one thing and does another - and it is the only route a
/// climber who signed into the wrong account has back to the sign-in screen. That
/// one control signs out, and says so on its face.
enum OnboardingLeadingControl: String, CaseIterable, Sendable {
    case back
    case signOut = "sign_out"
}
