import SwiftUI

/// Today's Climb as a row in Home's sheet: artwork, name, location and the stake line
/// that says what finishing it earns today. Tapping it opens Climb Detail.
struct HomeTodayClimbRow: View {
    let climb: Climb
    let stakeLine: TodayClimbStakeLine
    let isCompleted: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 0) {
                // The image fills the card's left column edge to edge, no inset.
                ClimbArtworkView(climb: climb, variant: .thumb)
                    .frame(width: 104)
                    .frame(maxHeight: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S CLIMB")
                        .font(.montserratBold(size: 9.5))
                        .tracking(1.4)
                        .foregroundStyle(Color.accent)

                    HStack(spacing: 6) {
                        Text(climb.name)
                            .font(.montserratBold(size: 15))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)

                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accent)
                        }
                    }

                    Text(climb.displayLocation)
                        .font(.montserratRegular(size: 12))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)

                    HStack(alignment: .center, spacing: 6) {
                        TodayClimbStakeLineIcon(stakeLine: stakeLine, size: 10)

                        Text(stakeLine.text)
                            .font(.montserratMedium(size: 11.5))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.trailing, 12)
            }
            .frame(minHeight: 104)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(climb.tier.color.opacity(0.42), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's climb: \(climb.name), \(climb.displayLocation). \(stakeLine.text)")
        .accessibilityHint("Open climb detail")
    }
}
