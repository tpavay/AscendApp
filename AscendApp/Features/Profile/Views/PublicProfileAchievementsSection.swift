import SwiftUI

struct PublicProfileAchievementsSection: View {
    let achievements: ProfileAchievementCounts
    let achievementRecords: [ProfileAchievementRecord]
    let isOtherLoading: Bool

    private var presentation: PublicProfileAchievementPresentation {
        PublicProfileAchievementPresentation(
            achievements: achievements,
            isOtherLoading: isOtherLoading
        )
    }

    var body: some View {
        switch presentation {
        case .loading:
            ProfileComparisonSection(title: "ACHIEVEMENTS") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            VStack(spacing: 8) {
                                AscendSkeletonText(width: 46, height: 46)
                                AscendSkeletonText(width: 34, height: 20)
                                AscendSkeletonText(width: 58, height: 9)
                            }
                            .frame(width: 88)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Achievements")
            .accessibilityValue("Loading")

        case .hidden:
            EmptyView()

        case .visible(let achievements):
            ProfileComparisonSection(title: "ACHIEVEMENTS") {
                ProfilePrestigeBadgeShelf(
                    tokens: ProfilePrestigeToken.leaderboardTokens(for: achievements),
                    achievementRecords: achievementRecords,
                    imageSize: 46
                )
            }
        }
    }
}
