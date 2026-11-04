import SwiftUI

/// Placeholder for the `claimCity` screen. The chunk that builds it deletes this file and adds a view
/// of the same name and `init(coordinator:)` signature, with its own `.trackOnce(screen:)`.
struct OnboardingClaimCityScreen: View {
    let coordinator: OnboardingV3Coordinator

    var body: some View {
        OnboardingV3StubScreen(step: .claimCity, coordinator: coordinator)
            .trackOnce(screen: .onboardingClaimCity)
    }
}
