import SwiftUI

struct ProfilePrestigeToken: Identifiable {
    let id: String
    let asset: String
    let tint: Color
    let count: Int
    let label: String
    let achievementBand: ProfileAchievementRankBand?
    let usesFreeStandingArt: Bool

    init(
        id: String,
        asset: String,
        tint: Color,
        count: Int,
        label: String,
        achievementBand: ProfileAchievementRankBand?,
        usesFreeStandingArt: Bool = false
    ) {
        self.id = id
        self.asset = asset
        self.tint = tint
        self.count = count
        self.label = label
        self.achievementBand = achievementBand
        self.usesFreeStandingArt = usesFreeStandingArt
    }

    static func leaderboardTokens(
        for achievements: ProfileAchievementCounts
    ) -> [ProfilePrestigeToken] {
        var tokens: [ProfilePrestigeToken] = []

        if achievements.top1 > 0 {
            tokens.append(
                ProfilePrestigeToken(
                    id: "top1",
                    asset: "LeaderboardCrown",
                    tint: ProfileVisualStyle.gold,
                    count: achievements.top1,
                    label: ProfileTerminology.topOneAchievementLabel,
                    achievementBand: .top1,
                    usesFreeStandingArt: true
                )
            )
        }
        if achievements.top3 > 0 {
            tokens.append(
                ProfilePrestigeToken(
                    id: "top3",
                    asset: "LeaderboardTop3",
                    tint: ProfileVisualStyle.silver,
                    count: achievements.top3,
                    label: ProfileTerminology.topThreeAchievementLabel,
                    achievementBand: .top3
                )
            )
        }
        if achievements.top10 > 0 {
            tokens.append(
                ProfilePrestigeToken(
                    id: "top10",
                    asset: "LeaderboardTop10",
                    tint: ProfileVisualStyle.gold,
                    count: achievements.top10,
                    label: ProfileTerminology.topTenAchievementLabel,
                    achievementBand: .top10
                )
            )
        }
        if achievements.top100 > 0 {
            tokens.append(
                ProfilePrestigeToken(
                    id: "top100",
                    asset: "LeaderboardTop100",
                    tint: ProfileVisualStyle.secondaryText,
                    count: achievements.top100,
                    label: ProfileTerminology.topHundredAchievementLabel,
                    achievementBand: .top100
                )
            )
        }

        return tokens
    }
}
