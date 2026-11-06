import SwiftUI

private struct OnboardingPaywallModelKey: EnvironmentKey {
    static let defaultValue: OnboardingPaywallModel? = nil
}

/// The account routes the app-access gate carries and this paywall replaces it with: Guideline
/// 5.1.1(v) grants no paid-status exception, so a climber who cannot get past the paywall can still
/// delete the account or sign out to authenticate as the Apple ID that owns the subscription.
struct OnboardingPaywallAccountActions: Sendable {
    var onDeleteAccount: @MainActor () -> Void
    var onSignOut: @MainActor () -> Void

    /// The same two destinations the app-access gate leaves for: the root's one deletion sheet and
    /// its sign-out.
    static func gateRoutes(
        presentAccountDeletion: @escaping @MainActor () -> Void,
        signOut: @escaping @MainActor () -> Void
    ) -> OnboardingPaywallAccountActions {
        OnboardingPaywallAccountActions(onDeleteAccount: presentAccountDeletion, onSignOut: signOut)
    }
}

private struct OnboardingPaywallAccountActionsKey: EnvironmentKey {
    static let defaultValue: OnboardingPaywallAccountActions? = nil
}

extension EnvironmentValues {
    var onboardingPaywallAccountActions: OnboardingPaywallAccountActions? {
        get { self[OnboardingPaywallAccountActionsKey.self] }
        set { self[OnboardingPaywallAccountActionsKey.self] = newValue }
    }

    /// The model the paywall and the gift share. Absent, the app's own is used; a test or a preview
    /// injects one built on a stub store. The flow view constructs each screen from its coordinator
    /// alone, so this is how the two screens reach the same instance.
    var onboardingPaywallModel: OnboardingPaywallModel? {
        get { self[OnboardingPaywallModelKey.self] }
        set { self[OnboardingPaywallModelKey.self] = newValue }
    }
}
