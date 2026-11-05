import SwiftUI

/// The yearly card: the selected, lime-bordered plan with the monthly equivalent on the right.
struct PaywallYearlyCard: View {
    let plan: NativePaywallPlan
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stackedContent
                } else {
                    rowContent
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
                if !dynamicTypeSize.isAccessibilitySize {
                    bestValueTag
                        .padding(.trailing, 18)
                        .offset(y: -12)
                }
            }
            // Dimmed as one piece when locked, so the border does not draw through the tag.
            .compositingGroup()
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            selectionMark

            VStack(alignment: .leading, spacing: 2) {
                title
                price
                billedLine
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
    }

    /// At an accessibility size a row leaves each column too narrow for one word, and the tag would
    /// land on the title, so everything takes its own line.
    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            bestValueTag

            HStack(spacing: 10) {
                selectionMark
                title
            }

            price
            billedLine

            if let perMonth = plan.localizedPricePerMonth {
                Text("\(perMonth) per month")
                    .paywallText(.bold, size: 12, relativeTo: .caption)
                    .foregroundStyle(OnboardingV3Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: some View {
        Text("Yearly")
            .paywallText(.extraBold, size: 13, tracking: 0.16, relativeTo: .footnote)
            .textCase(.uppercase)
            .foregroundStyle(.white)
    }

    /// The amount charged leads: it is the largest figure on the card, with the monthly equivalent a
    /// smaller line.
    private var price: some View {
        Text(plan.localizedPrice)
            .paywallText(.black, size: 28, relativeTo: .title2)
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private var billedLine: some View {
        Text("billed once a year")
            .paywallText(.semiBold, size: 14, relativeTo: .subheadline)
            .foregroundStyle(OnboardingV3Palette.secondary)
    }

    private var bestValueTag: some View {
        Text("Best value")
            .paywallText(.black, size: 10, tracking: 0.14, relativeTo: .caption2)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(OnboardingV3Palette.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
            // Whichever fits whole: no column may be squeezed until a word or the price breaks.
            ViewThatFits(in: .horizontal) {
                row(secondary: "Pay once. No renewal.")
                row(secondary: "Pay once.\nNo renewal.")
                VStack(alignment: .leading, spacing: 2) {
                    title
                    secondary("Pay once. No renewal.")
                    price
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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

    private func row(secondary line: String) -> some View {
        HStack(spacing: 12) {
            title
            secondary(line)
                .frame(maxWidth: .infinity, alignment: .leading)
            price
        }
    }

    private var title: some View {
        Text("Lifetime")
            .paywallText(.extraBold, size: 12, tracking: 0.16, relativeTo: .footnote)
            .textCase(.uppercase)
            .foregroundStyle(.white)
    }

    private func secondary(_ line: String) -> some View {
        Text(line)
            .paywallText(.semiBold, size: 12, relativeTo: .caption)
            .foregroundStyle(OnboardingV3Palette.secondary)
    }

    private var price: some View {
        Text("\(plan.localizedPrice) once")
            .paywallText(.extraBold, size: 14, relativeTo: .subheadline)
            .foregroundStyle(.white)
    }
}
