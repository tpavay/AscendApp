import Foundation

/// What the Mountain reads from the race board beyond the session's own leaderboard windows: the
/// climbers someone can filter the race down to, and the climb of each one they chose.
///
/// A window holds only the climbers either side of the runner, so a chosen climber whose best is
/// far above or below them is never in it. Their best is read by owner instead, exactly as the
/// session reads the runner's own previous best: one flagged document once, then that one entry
/// at each bucket it ran.
protocol MountainRaceBoard: Sendable {
    /// A climber's best on this board for the session's goal, or nil where they have none.
    func raceBest(context: LiveReplayLeaderboardContext, userId: String) async throws -> MountainRaceBest?

    /// Where one published climb stood at the end of `bucketIndex`, or nil where it had ended.
    func stepsAtBucket(context: LiveReplayLeaderboardContext, entryId: String, bucketIndex: Int) async throws -> Int?

    /// The climbers whose best is nearest `steps`: up to `limit` at or above it and `limit` below.
    func bests(context: LiveReplayLeaderboardContext, near steps: Int, limit: Int) async throws -> [LiveReplayLeaderboardRow]

    /// One page of every climber's best on this board, most steps first.
    func bests(
        context: LiveReplayLeaderboardContext,
        after cursor: MountainRaceBoardCursor?,
        limit: Int
    ) async throws -> MountainRaceBoardPage
}

/// A climber's flagged best, and how many buckets it published into.
struct MountainRaceBest: Equatable, Sendable {
    let row: LiveReplayLeaderboardRow
    let splitBucketCount: Int?
}

/// Where the next page of bests starts: after this step count, then this entry.
struct MountainRaceBoardCursor: Equatable, Sendable {
    let finalSteps: Int
    let entryId: String
}

struct MountainRaceBoardPage: Equatable, Sendable {
    let rows: [LiveReplayLeaderboardRow]
    /// Nil once the board has no more.
    let next: MountainRaceBoardCursor?
}
