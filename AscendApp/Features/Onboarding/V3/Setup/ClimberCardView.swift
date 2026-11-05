import SwiftUI

/// The live climber card: what people see when they tap the climber's name or compare with them.
/// It fills in as the climber answers below it; a tile with no answer draws a short line, never a
/// dash character, because a lone dash reads as a minus sign.
struct ClimberCardView: View {
    let draft: ClimberCardDraft
    /// Fixes the clock for the age the birthday gives.
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text("You")
                        .font(.custom("Montserrat-ExtraBold", size: 20))
                        .foregroundStyle(.white)

                    Text("Joined today")
                        .font(.custom("Montserrat-SemiBold", size: 14))
                        .foregroundStyle(OnboardingV3Palette.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                tile(title: "Gender", value: draft.genderTileText)
                tile(title: "Age", value: draft.age(on: now).map { $0.formatted() })
                tile(title: "Height", value: draft.heightText)
                tile(title: "Weight", value: draft.weightText)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [OnboardingV3Palette.accent.opacity(0.14), OnboardingV3Palette.cardFill],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(OnboardingV3Palette.accent.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your climber card, joined today")
        .accessibilityValue(accessibilitySummary)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(OnboardingV3Palette.accent.opacity(0.18))
            Image(systemName: "person.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(OnboardingV3Palette.accent.opacity(0.75))
                .offset(y: 4)
        }
        .frame(width: 58, height: 58)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(OnboardingV3Palette.accent, lineWidth: 3))
    }

    private func tile(title: String, value: String?) -> some View {
        VStack(spacing: 6) {
            Group {
                if let value {
                    Text(value)
                        .font(.custom("Montserrat-Black", size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Capsule()
                        .fill(OnboardingV3Palette.chipBorder)
                        .frame(width: 18, height: 4)
                }
            }
            .frame(height: 22)

            Text(title)
                .font(.custom("Montserrat-ExtraBold", size: 10))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(OnboardingV3Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let gender = draft.genderTileText { parts.append("Gender \(gender)") }
        if let age = draft.age(on: now) { parts.append("Age \(age)") }
        if let height = draft.heightText { parts.append("Height \(height)") }
        if let weight = draft.weightText { parts.append("Weight \(weight)") }
        return parts.isEmpty ? "Nothing added yet" : parts.joined(separator: ", ")
    }
}
