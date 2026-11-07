import SwiftUI

/// The fixed needle through the scale's middle: a lime line with a round knob on top.
struct WeightScaleNeedle: View {
    var body: some View {
        VStack(spacing: -4) {
            Circle()
                .fill(OnboardingV3Palette.accent)
                .frame(width: 14, height: 14)

            Capsule()
                .fill(OnboardingV3Palette.accent)
                .frame(width: 3, height: 58)
                .shadow(color: OnboardingV3Palette.accent.opacity(0.55), radius: 6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
