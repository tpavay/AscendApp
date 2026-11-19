import SwiftUI

/// 06 Your workouts, counted for you: the one Connect Apple Health screen, in onboarding's chrome.
///
/// It is the screen the Climb sheet and Settings open later (`AppleHealthConnectView`), so there is
/// one copy of the words, the tiles and the motion. Here the progress header replaces the X.
/// Connect goes to 06b, which shows the iOS sheet before asking for it; the request itself is 06b's.
///
/// There is no Skip. Guideline 5.1.1(iv) rejected 1.3.0 (build 2026111701) because a custom message
/// ahead of the Health request could be closed without reaching the request, so this screen's one
/// forward action leads to the request and the climber's no is the iOS sheet's Don't Allow, which
/// 06b takes as an answer and moves on from (`OnboardingHealthPermissionViewModel`). The way back
/// is the header's Back, which leaves onboarding's earlier screens, not this one's request.
struct OnboardingHealthConnectScreen: View {
    let coordinator: OnboardingV3Coordinator

    var body: some View {
        AppleHealthConnectView(chrome: .onboarding, onConnect: coordinator.advance)
    }
}

#Preview("06 connect Apple Health") {
    OnboardingV3FlowView(coordinator: OnboardingV3Coordinator(
        store: PreAuthOnboardingStore(userDefaults: UserDefaults(suiteName: "onboarding-v3-preview-health-connect") ?? .standard),
        startingAt: .healthConnect
    ))
}
