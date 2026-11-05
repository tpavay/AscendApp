import SwiftUI

/// Placeholder for the `healthHistory` screen. The chunk that builds it deletes this file and adds a view
/// of the same name and `init(coordinator:)` signature, with its own `.trackOnce(screen:)`.
struct OnboardingHealthHistoryScreen: View {
    let coordinator: OnboardingV3Coordinator

    var body: some View {
        OnboardingV3StubScreen(step: .healthHistory, coordinator: coordinator)
            .trackOnce(screen: .onboardingHealthHistory)
    }
}
