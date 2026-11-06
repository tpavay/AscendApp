import SwiftUI

/// A select row with its detail on the right, the way 07b draws it: the title on the left, the
/// detail trailing and lit with the border when chosen. No check mark and no radio circle - the
/// captain's call, round 45 - so the chosen state is spoken through the selected trait.
struct OnboardingChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var detailSize: CGFloat = 14

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.custom("Montserrat-ExtraBold", fixedSize: titleSize))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(detail)
                    .font(.custom("Montserrat-SemiBold", fixedSize: detailSize))
                    .foregroundStyle(isSelected ? OnboardingV3Palette.accent : OnboardingV3Palette.skip)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? OnboardingV3Palette.accent.opacity(0.1) : OnboardingV3Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? OnboardingV3Palette.accent : OnboardingV3Palette.cardBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? OnboardingV3Palette.accent.opacity(0.28) : .clear, radius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
