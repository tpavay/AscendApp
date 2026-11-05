import SwiftUI

/// Placeholder for the `countMethods` screen. The chunk that builds it deletes this file and adds a view
/// of the same name and `init(coordinator:)` signature, with its own `.trackOnce(screen:)`.
struct OnboardingCountMethodsScreen: View {
    let coordinator: OnboardingV3Coordinator

    var body: some View {
        OnboardingV3StubScreen(step: .countMethods, coordinator: coordinator)
            .trackOnce(screen: .onboardingCountMethods)
    }
}
