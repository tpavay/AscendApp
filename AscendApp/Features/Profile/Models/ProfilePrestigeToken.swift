import SwiftUI

struct ProfilePrestigeToken: Identifiable {
    let id: String
    let asset: String
    let tint: Color
    let count: Int
    let label: String
    /// What VoiceOver announces. `#2` reads as a bare number next to the count, so the
    /// placement badges spell their rank out instead.
    let accessibilityName: String
    let historyFilter: ProfileAchievementHistoryFilter?

    init(
        id: String,
        asset: String,
        tint: Color,
        count: Int,
        label: String,
        accessibilityName: String? = nil,
        historyFilter: ProfileAchievementHistoryFilter?
    ) {
        self.id = id
        self.asset = asset
        self.tint = tint
        self.count = count
        self.label = label
        self.accessibilityName = accessibilityName ?? label
        self.historyFilter = historyFilter
    }

    /// The leaderboard ladder, in order: CHAMPION, #2, #3, TOP 10, TOP 100.
    ///
    /// The placement badges appear only when the ladder carries `placements`. On the banded
    /// fallback it does not, and a second place that cannot be told apart from a third is not
    /// shown at all.
    static func leaderboardTokens(
        for ladder: ProfileAchievementLadder
    ) -> [ProfilePrestigeToken] {
        var tokens: [ProfilePrestigeToken] = []
        let achievements = ladder.counts

        if achievements.top1 > 0 {
            tokens.append(
                ProfilePrestigeToken(
                    id: "top1",
                    asset: "LeaderboardCrown",
                    tint: ProfileVisualStyle.gold,
                    count: achievements.top1,
                    label: ProfileTerminology.topOneAchievementLabel,
                    historyFilter: .band(.top1)
                )
            )
        }
        if let placements = ladder.placements {
            if placements.second > 0 {
                tokens.append(
                    ProfilePrestigeToken(
                        id: "place2",
                        asset: "LeaderboardSilverMedal",
                        tint: ProfileVisualStyle.silver,
                        count: placements.second,
                        label: ProfileTerminology.secondPlaceAchievementLabel,
                        accessibilityName: ProfileTerminology.secondPlaceAccessibilityName,
                        historyFilter: .placement(2)
                    )
                )
            }
            if placements.third > 0 {
                tokens.append(
                    ProfilePrestigeToken(
                        id: "place3",
                        asset: "LeaderboardBronzeMedal",
                        tint: ProfileVisualStyle.bronze,
                        count: placements.third,
                        label: ProfileTerminology.thirdPlaceAchievementLabel,
                        accessibilityName: ProfileTerminology.thirdPlaceAccessibilityName,
                        historyFilter: .placement(3)
                    )
                )
            }
        }
        if achievements.top10 > 0 {
            tokens.append(
                ProfilePrestigeToken(
                    id: "top10",
                    asset: "LeaderboardTop10",
                    tint: ProfileVisualStyle.gold,
                    count: achievements.top10,
                    label: ProfileTerminology.topTenAchievementLabel,
                    historyFilter: .band(.top10)
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
                    historyFilter: .band(.top100)
                )
            )
        }

        return tokens
    }
}
