import SwiftUI

struct AchievementsSection: View {
    let counts: ProfileAchievementCounts
    let mode: ProfileViewMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeaderView(title: "Achievements")

            LazyVGrid(columns: columns, spacing: 8) {
                // PROD-ASSET: AchievementTop1
                achievementCard(
                    label: ProfileTerminology.topOneAchievementLabel,
                    count: counts.top1,
                    assetImage: "LeaderboardCrown",
                    tint: ProfileVisualStyle.gold,
                    productionAssetName: "AchievementTop1"
                )
                // PROD-ASSET: AchievementTop3
                achievementCard(
                    label: ProfileTerminology.topThreeAchievementLabel,
                    count: counts.top3,
                    assetImage: "LeaderboardTop3",
                    tint: ProfileVisualStyle.silver,
                    productionAssetName: "AchievementTop3"
                )
                // PROD-ASSET: AchievementTop10
                achievementCard(
                    label: ProfileTerminology.topTenAchievementLabel,
                    count: counts.top10,
                    assetImage: "LeaderboardTop10",
                    tint: ProfileVisualStyle.gold,
                    productionAssetName: "AchievementTop10"
                )
                // PROD-ASSET: AchievementTop100
                achievementCard(
                    label: ProfileTerminology.topHundredAchievementLabel,
                    count: counts.top100,
                    assetImage: "LeaderboardTop100",
                    tint: ProfileVisualStyle.secondaryText,
                    productionAssetName: "AchievementTop100"
                )
            }

        }
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    private func achievementCard(
        label: String,
        count: Int,
        assetImage: String?,
        tint: Color,
        productionAssetName: String
    ) -> some View {
        ProfileCardSurfaceView {
            HStack(spacing: 10) {
                achievementIcon(
                    assetImage: assetImage,
                    tint: tint,
                    productionAssetName: productionAssetName
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.montserratBold(size: 11))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                        .tracking(1.1)
                        .lineLimit(1)

                    Text(count.formatted(.number.grouping(.automatic)))
                        .font(.montserratBold(size: 24))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .accessibilityLabel("\(label), \(count)")
    }

    @ViewBuilder
    private func achievementIcon(
        assetImage: String?,
        tint: Color,
        productionAssetName: String
    ) -> some View {
        if let assetImage {
            Image(assetImage)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: tint.opacity(0.24), radius: 5, x: 0, y: 1)
                .accessibilityHidden(true)
                .accessibilityIdentifier(productionAssetName)
        }
    }
}
