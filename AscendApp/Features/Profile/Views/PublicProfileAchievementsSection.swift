import SwiftUI

/// The ACHIEVEMENTS section of the profile comparison, as one row per badge type rather than a
/// shelf. A shelf answers "whose is this" with nothing at all; the rows answer it structurally,
/// and answer "who is winning" as well. The full-prestige shelf still lives on the climber's own
/// profile, which is the screen for admiring a case rather than counting it against someone's.
struct PublicProfileAchievementsSection: View {
    let viewer: ProfileAchievementTally
    let other: ProfileAchievementTally
    let isOtherLoading: Bool

    private var presentation: PublicProfileAchievementPresentation {
        PublicProfileAchievementPresentation(
            viewer: viewer,
            other: other,
            isOtherLoading: isOtherLoading
        )
    }

    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()

        case .visible(let entries):
            ProfileComparisonSection(title: "ACHIEVEMENTS") {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        ProfileAchievementComparisonRow(
                            entry: entry,
                            showDivider: entry.id != entries.last?.id
                        )
                    }
                }
            }
        }
    }
}
