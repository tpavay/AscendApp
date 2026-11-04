import SwiftUI

/// Placeholder for 06-later: the Health connect screen opened from the Climb sheet and Settings
/// instead of from the flow, with an X in place of the bar. Chunk B deletes this file and tracks
/// `.healthConnectLater` where it presents that screen.
struct OnboardingHealthConnectLaterStub: View {
    let onClose: () -> Void

    var body: some View {
        VStack {
            OnboardingProgressHeader(onClose: onClose)
            Spacer()
        }
        .background(OnboardingV3Palette.background)
        .trackOnce(screen: .healthConnectLater)
    }
}
