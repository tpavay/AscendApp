import SwiftUI

/// The card a tapped pin shows: how many climbers have completed the climb, its name,
/// city, steps and floors. It carries no button and no chevron; the whole card is
/// the tap target and opens Climb Detail, which owns the call to action.
struct ClimbPreviewCardView: View {
    let summary: ClimbPreviewSummary
    /// Distinct climbers who have completed the climb, from the leaderboard
    /// projection. Nil while unread, so the card shows no number it has not fetched.
    var completedClimberCount: Int?
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                ClimbSplitCardSurface(
                    leadingWidth: 110,
                    minimumHeight: 138,
                    glowColor: summary.climb.tier.glowColor,
                    borderColors: summary.climb.tier.borderColors,
                    shadowColor: summary.climb.tier.shadowColor,
                    lineWidth: 1.8,
                    isEmphasizedBorderStyle: summary.climb.tier.usesEmphasizedBorderStyle,
                    leading: {
                        leadingArtwork
                    },
                    content: {
                        cardContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                        .padding(.trailing, 46)
                        .padding(.vertical, 12)
                    }
                )
                .frame(height: 138)
            }
            .buttonStyle(.plain)
            .disabled(!summary.climb.isAvailable)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    @ViewBuilder
    private var leadingArtwork: some View {
        if summary.climb.isComingSoon {
            ClimbLeadingArtworkPanel(climb: summary.climb)
                .blur(radius: 3)
                .opacity(0.42)
                .overlay {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
        } else {
            ClimbLeadingArtworkPanel(climb: summary.climb)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        if summary.climb.isComingSoon {
            comingSoonContent
        } else {
            availableContent
        }
    }

    private var availableContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            completedClimbersLine

            Text(summary.climb.name)
                .font(.montserratBold(size: 14.5))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.46))

                Text(summary.climb.displayLocation)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Text("\(summary.climb.referenceStepCount.formatted()) steps")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.white)

                Text("|")
                    .font(.montserratMedium(size: 11))
                    .foregroundStyle(.white.opacity(0.26))

                Text("\(summary.climb.calculatedFloors.formatted()) floors")
                    .font(.montserratSemiBold(size: 12))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }

    /// One number, counted over distinct climbers, from the projection the board
    /// itself reads. Zero is the open First Ascent, so it reads as the claim it is.
    /// Absent until the board has answered.
    @ViewBuilder
    private var completedClimbersLine: some View {
        if let completedClimberCount {
            HStack(spacing: 6) {
                Circle()
                    .fill(summary.climb.tier.color)
                    .frame(width: 7, height: 7)

                Text(Self.completedClimbersText(completedClimberCount))
                    .font(.montserratSemiBold(size: 11.5))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    static func completedClimbersText(_ count: Int) -> String {
        switch max(count, 0) {
        case 0:
            return "Unclaimed"
        case 1:
            return "1 climber completed"
        case let count:
            return "\(count.formatted()) climbers completed"
        }
    }

    private var comingSoonContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Coming Soon")
                .font(.montserratBold(size: 15))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.46))

                Text(summary.climb.displayLocation)
                    .font(.montserratRegular(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Text("A new First Ascent opens here soon. Be ready.")
                .font(.montserratSemiBold(size: 12))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

#Preview("New Climb") {
    ClimbPreviewCardView(
        summary: ClimbPreviewSummary(climb: .preview, isCompleted: false),
        completedClimberCount: 0,
        onSelect: {},
        onClose: {}
    )
    .padding(16)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Completed Climb") {
    ClimbPreviewCardView(
        summary: ClimbPreviewSummary(climb: .preview, isCompleted: true),
        completedClimberCount: 12,
        onSelect: {},
        onClose: {}
    )
    .padding(16)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Coming Soon") {
    ClimbPreviewCardView(
        summary: ClimbPreviewSummary(climb: .previewComingSoon, isCompleted: false),
        onSelect: {},
        onClose: {}
    )
    .padding(16)
    .background(.black)
    .preferredColorScheme(.dark)
}
