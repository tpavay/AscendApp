import SwiftUI

struct ActiveStandingsSection: View {
    let standings: [ProfileStanding]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeaderView(title: "Active Standings")

            HStack(spacing: 8) {
                ForEach(orderedStandings) { standing in
                    standingCard(standing)
                }
            }
        }
    }

    private var orderedStandings: [ProfileStanding] {
        let map = Dictionary(uniqueKeysWithValues: standings.map { ($0.timeFrame, $0) })
        return [LeaderboardTimeFrame.weekly, .monthly, .yearly].map { timeFrame in
            map[timeFrame] ?? ProfileStanding(
                timeFrame: timeFrame,
                rank: nil,
                value: 0,
                leaderValue: nil,
                previousRankValue: nil,
                totalClimbers: 0,
                tiedForFirst: false
            )
        }
    }

    private func standingCard(_ standing: ProfileStanding) -> some View {
        ProfileCardSurfaceView {
            VStack(alignment: .leading, spacing: 7) {
                Text(standing.timeFrame.displayName.uppercased())
                    .font(.montserratBold(size: 10))
                    .foregroundStyle(ProfileVisualStyle.secondaryText)
                    .tracking(1.1)
                    .lineLimit(1)

                rankValue(standing)

                Text(subtitle(for: standing))
                    .font(.montserratSemiBold(size: 9))
                    .foregroundStyle(Color.ascendAccent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(10)
        }
    }

    @ViewBuilder
    private func rankValue(_ standing: ProfileStanding) -> some View {
        if let rank = standing.rank {
            Text("#\(rank)")
                .font(.montserratBold(size: 30))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        } else {
            Text("Unranked")
                .font(.montserratBold(size: 16))
                .foregroundStyle(ProfileVisualStyle.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
    }

    private func subtitle(for standing: ProfileStanding) -> String {
        guard standing.hasRank else { return "Climb to claim a spot" }
        return ProfileStandingSubtitleFormatter.subtitle(for: standing)
    }
}
