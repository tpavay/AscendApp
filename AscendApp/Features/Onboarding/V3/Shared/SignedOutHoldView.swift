import SwiftUI

/// What a signed-out launch shows while ``OnboardingV3RouteLatch`` decides between the two flows.
/// Neutral on purpose: it belongs to neither.
struct SignedOutHoldView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AscendWordmark(height: 40, treatment: .onDark)
        }
    }
}
