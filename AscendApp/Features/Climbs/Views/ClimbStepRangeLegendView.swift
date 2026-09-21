import SwiftUI

/// The step-range key for the globe's tier-colored pins. Lists only the tiers that
/// have a pin on the globe, so the legend never names a color nobody can find.
struct ClimbStepRangeLegendView: View {
    let tiers: [ClimbTier]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STEPS")
                .font(.montserratBold(size: 9))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(tiers, id: \.self) { tier in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tier.color)
                            .frame(width: 7, height: 7)

                        Text(tier.stepRangeDescription)
                            .font(.montserratSemiBold(size: 9.5))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let ranges = tiers.map { "\($0.displayName) \($0.stepRangeDescription)" }
        return "Marker colors by steps: " + ranges.joined(separator: ", ")
    }
}

#Preview {
    ClimbStepRangeLegendView(tiers: ClimbTier.allCases)
        .padding(20)
        .background(Color(hex: "07101B"))
        .preferredColorScheme(.dark)
}
