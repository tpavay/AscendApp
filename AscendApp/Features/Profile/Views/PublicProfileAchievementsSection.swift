import SwiftUI

struct PublicProfileAchievementsSection: View {
    let achievements: ProfileAchievementCounts
    let isOtherLoading: Bool

    private var presentation: PublicProfileAchievementPresentation {
        PublicProfileAchievementPresentation(
            achievements: achievements,
            isOtherLoading: isOtherLoading
        )
    }

    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()

        case .visible(let achievements):
            ProfileComparisonSection(title: "ACHIEVEMENTS") {
                ProfilePrestigeBadgeShelf(
                    tokens: ProfilePrestigeToken.leaderboardTokens(for: achievements),
                    imageSize: 46,
                    history: nil
                )
            }
        }
    }
}
