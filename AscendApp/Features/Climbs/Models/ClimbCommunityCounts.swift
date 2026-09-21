import Foundation

/// The two community numbers a climb's card carries, named by what each counts.
///
/// `completedClimbers` is the number of distinct climbers who have finished the climb,
/// the same figure Climb Detail shows as "completed". `completions` is every finished
/// attempt on the board, the population Climb Detail's ALL TIMES tab lists. Both come
/// from the server-derived leaderboard projection; the card never counts anything
/// itself.
struct ClimbCommunityCounts: Equatable, Sendable {
    let completedClimbers: Int
    let completions: Int

    init(completedClimbers: Int, completions: Int) {
        self.completedClimbers = max(completedClimbers, 0)
        self.completions = max(completions, self.completedClimbers)
    }
}
