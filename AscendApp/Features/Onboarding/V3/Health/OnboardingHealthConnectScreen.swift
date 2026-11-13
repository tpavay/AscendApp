import SwiftUI

/// 06 Your workouts, counted for you: the one Connect Apple Health screen, in onboarding's chrome.
///
/// It is the screen the Climb sheet and Settings open later (`AppleHealthConnectView`), so there is
/// one copy of the words, the tiles and the motion. Here the progress header replaces the X and the
/// quiet link says "Skip". Connect goes to 06b, which shows the iOS sheet before
/// asking for it; the request itself is 06b's.
struct OnboardingHealthConnectScreen: View {
    let coordinator: OnboardingV3Coordinator

    var body: some View {
        AppleHealthConnectView(
            chrome: .onboarding,
            onConnect: coordinator.advance,
            onClose: { Self.declineHealth(coordinator) }
        )
    }

    /// "Skip": on to the usual-climb question, and whatever a climber who walked
    /// the Health branch and came back asked to bring in is left behind, so a no here is a no.
    static func declineHealth(_ coordinator: OnboardingV3Coordinator) {
        coordinator.update { $0.clearFoundHealthHistory() }
        coordinator.go(to: .usualClimb)
    }
}

#Preview("06 connect Apple Health") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-health-connect") ?? .standard),
        startingAt: .healthConnect
    ))
}
