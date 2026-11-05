import SwiftUI

private struct OnboardingPaywallModelKey: EnvironmentKey {
    static let defaultValue: OnboardingPaywallModel? = nil
}

extension EnvironmentValues {
    /// The model the paywall and the gift share. Absent, the app's own is used; a test or a preview
    /// injects one built on a stub store. The flow view constructs each screen from its coordinator
    /// alone, so this is how the two screens reach the same instance.
    var onboardingPaywallModel: OnboardingPaywallModel? {
        get { self[OnboardingPaywallModelKey.self] }
        set { self[OnboardingPaywallModelKey.self] = newValue }
    }
}
