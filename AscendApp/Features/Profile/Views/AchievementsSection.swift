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
                    systemImage: "crown.fill",
                    tint: ProfileVisualStyle.gold,
                    productionAssetName: "AchievementTop1"
                )
                // PROD-ASSET: AchievementTop3
                achievementCard(
                    label: ProfileTerminology.topThreeAchievementLabel,
                    count: counts.top3,
                    systemImage: "medal.fill",
                    tint: ProfileVisualStyle.silver,
                    productionAssetName: "AchievementTop3"
                )
                // PROD-ASSET: AchievementTop10
                achievementCard(
                    label: ProfileTerminology.topTenAchievementLabel,
                    count: counts.top10,
                    systemImage: "star.circle.fill",
                    tint: ProfileVisualStyle.gold,
                    productionAssetName: "AchievementTop10"
                )
                // PROD-ASSET: AchievementTop100
                achievementCard(
                    label: ProfileTerminology.topHundredAchievementLabel,
                    count: counts.top100,
                    systemImage: "star.fill",
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
        systemImage: String,
        tint: Color,
        productionAssetName: String
    ) -> some View {
        ProfileCardSurfaceView {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint.opacity(0.14)))
                    .accessibilityIdentifier(productionAssetName)

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
}
