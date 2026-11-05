import SwiftUI

/// The yearly card: the selected, lime-bordered plan with the monthly equivalent on the right.
struct PaywallYearlyCard: View {
    let plan: NativePaywallPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                selectionMark

                VStack(alignment: .leading, spacing: 2) {
                    Text("Yearly")
                        .paywallText(.extraBold, size: 13, tracking: 0.16, relativeTo: .footnote)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)

                    // The amount charged leads: it is the largest figure on the card, with the
                    // monthly equivalent a smaller line beside it.
                    Text(plan.localizedPrice)
                        .paywallText(.black, size: 28, relativeTo: .title2)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text("billed once a year")
                        .paywallText(.semiBold, size: 14, relativeTo: .subheadline)
                        .foregroundStyle(OnboardingV3Palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let perMonth = plan.localizedPricePerMonth {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(perMonth)
                            .paywallText(.extraBold, size: 15, relativeTo: .subheadline)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)

                        Text("per month")
                            .paywallText(.bold, size: 12, relativeTo: .caption)
                            .foregroundStyle(OnboardingV3Palette.secondary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "17220A"), Color(hex: "0A0A0A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isSelected ? OnboardingV3Palette.accent : OnboardingV3Palette.cardBorder,
                        lineWidth: 2
                    )
            )
            .overlay(alignment: .topTrailing) {
                Text("Best value")
                    .paywallText(.black, size: 10, tracking: 0.14, relativeTo: .caption2)
                    .textCase(.uppercase)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(OnboardingV3Palette.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.trailing, 18)
                    .offset(y: -12)
            }
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectionMark: some View {
        Circle()
            .fill(isSelected ? OnboardingV3Palette.accent : Color.clear)
            .overlay(Circle().strokeBorder(OnboardingV3Palette.accent.opacity(isSelected ? 0 : 0.5), lineWidth: 2))
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 26, height: 26)
    }

    private var subtitle: String {
        "\(plan.localizedPrice) billed once a year"
    }
    private var accessibilityLabel: String {
        var parts = ["Yearly, best value", subtitle]
        if let perMonth = plan.localizedPricePerMonth { parts.append("\(perMonth) per month") }
        if let trial = plan.trialDescription { parts.append(trial) }
        return parts.joined(separator: ", ")
    }
}

/// Lifetime, the smaller card under Yearly. One payment: nothing on it names a trial or a renewal.
struct PaywallLifetimeCard: View {
    let plan: NativePaywallPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("Lifetime")
                    .paywallText(.extraBold, size: 12, tracking: 0.16, relativeTo: .footnote)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)

                Text("Pay once. No renewal.")
                    .paywallText(.semiBold, size: 12, relativeTo: .caption)
                    .foregroundStyle(OnboardingV3Palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(plan.localizedPrice) once")
                    .paywallText(.extraBold, size: 14, relativeTo: .subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? OnboardingV3Palette.accent.opacity(0.1) : OnboardingV3Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? OnboardingV3Palette.accent : OnboardingV3Palette.cardBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lifetime, \(plan.localizedPrice) once. Pay once. No renewal.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
