import Foundation

/// Everything the achievement catalogue needs to count one climber's badges.
///
/// First Ascents are counted from the climb summaries rather than from the leaderboard ladder,
/// so they travel alongside it instead of inside it.
struct ProfileAchievementTally: Equatable, Sendable {
    let ladder: ProfileAchievementLadder
    let firstAscentsHeld: Int

    init(ladder: ProfileAchievementLadder, firstAscentsHeld: Int = 0) {
        self.ladder = ladder
        self.firstAscentsHeld = max(firstAscentsHeld, 0)
    }
}
