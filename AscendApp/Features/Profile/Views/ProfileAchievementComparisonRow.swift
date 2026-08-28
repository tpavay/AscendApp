import SwiftUI

/// One badge type, counted for both climbers, in `ProfileComparisonStatRow`'s exact geometry:
/// the viewer's count on the left, the badge's name centred, the other climber's count on the
/// right, and the shared lime/blue bar underneath.
///
/// Position is the ownership label, the same way it is on every other row of this screen, so
/// there is no owner caption to forget. The art sits outboard of each count, which keeps both
/// numbers pointing at the centre label.
///
/// A side that holds none of this badge renders a real `0` under ghosted art. Never a dash: a
/// dash on this screen means *we do not know this*, and here we know exactly.
struct ProfileAchievementComparisonRow: View {
    let entry: ProfileAchievementComparisonEntry
    var showDivider = true

    private let artworkSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                side(count: entry.viewerCount, isViewer: true)

                Text(entry.label)
                    .font(.montserratBold(size: 12))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .frame(width: 118, alignment: .center)

                side(count: entry.otherCount, isViewer: false)
            }

            ProfileComparisonStatBar(
                viewerValue: Double(entry.viewerCount),
                otherValue: Double(entry.otherCount)
            )

            if showDivider {
                Rectangle()
                    .fill(ProfileVisualStyle.cardStroke)
                    .frame(height: 1)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.accessibilityName), you \(entry.viewerCount), them \(entry.otherCount)"
        )
    }

    private func side(count: Int, isViewer: Bool) -> some View {
        HStack(spacing: 8) {
            if isViewer {
                artwork(isEarned: count > 0)
                countText(count)
            } else {
                countText(count)
                artwork(isEarned: count > 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: isViewer ? .leading : .trailing)
    }

    private func artwork(isEarned: Bool) -> some View {
        ProfilePrestigeBadgeArtwork(
            asset: entry.asset,
            tint: entry.tint,
            size: artworkSize,
            isEarned: isEarned
        )
    }

    private func countText(_ count: Int) -> some View {
        Text(count.formatted(.number.grouping(.automatic)))
            .font(.montserratBold(size: 17))
            .foregroundStyle(count > 0 ? Color.white : ProfileVisualStyle.tertiaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
