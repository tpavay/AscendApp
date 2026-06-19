import SwiftUI

struct OnboardingValueShowcaseCarouselDots: View {
    let activeIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalCount, id: \.self) { index in
                Circle()
                    .fill(index == clampedActiveIndex ? OnboardingValuePalette.lime : Color.white.opacity(0.26))
                    .frame(width: index == clampedActiveIndex ? 7 : 5, height: index == clampedActiveIndex ? 7 : 5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: clampedActiveIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue(accessibilityValue)
    }

    private var clampedActiveIndex: Int {
        guard totalCount > 0 else { return 0 }
        return min(max(activeIndex, 0), totalCount - 1)
    }

    private var accessibilityValue: String {
        guard totalCount > 0 else { return "0 of 0" }
        return "\(clampedActiveIndex + 1) of \(totalCount)"
    }
}
