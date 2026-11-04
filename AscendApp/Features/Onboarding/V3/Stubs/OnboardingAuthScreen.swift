import SwiftUI

/// Placeholder for the `auth` screen. The chunk that builds it deletes this file and adds a view
/// of the same name and `init(coordinator:)` signature, with its own `.trackOnce(screen:)`.
struct OnboardingAuthScreen: View {
    let coordinator: OnboardingV3Coordinator

    var body: some View {
        OnboardingV3StubScreen(step: .auth, coordinator: coordinator)
            .trackOnce(screen: .onboardingAuth)
    }
}
