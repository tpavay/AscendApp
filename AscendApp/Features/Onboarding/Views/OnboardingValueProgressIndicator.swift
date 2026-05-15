import SwiftUI

struct OnboardingValueProgressIndicator: View {
    let activeIndex: Int
    let totalCount: Int
    var activeColor: Color = OnboardingValuePalette.lime
    var inactiveColor: Color = .white.opacity(0.24)

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == clampedActiveIndex ? activeColor : inactiveColor)
                    .frame(width: index == clampedActiveIndex ? 36 : 28, height: 3)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: clampedActiveIndex)
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
