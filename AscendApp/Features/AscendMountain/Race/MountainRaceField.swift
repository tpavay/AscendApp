import Foundation

/// Everybody a live session has seen on the race board, each as a path up the stairs.
///
/// Built from the windows the session already fetches for its leaderboard, so drawing the field
/// on the Mountain costs no read of its own. A window holds the climbers either side of the
/// runner at this moment, which is exactly who can be seen on the stairs; a climber who has left
/// the window keeps heading for their finish on the path learned so far.
///
/// The runner's own previous best is kept apart from the field. The board never counts it as a
/// climber, so neither does this: it is `yourBest`, drawn only when the runner asks for it.
struct MountainRaceField: Equatable, Sendable {
    struct Climber: Equatable, Sendable {
        let id: String
        let userId: String?
        var curve: MountainRivalCurve
    }

    private(set) var climbers: [String: Climber] = [:]
    private(set) var yourBest: MountainRivalCurve?

    /// Folds one fetched window in. A row still climbing at the window's bucket gives a
    /// checkpoint at that bucket's end; a row already home adds nothing its finish did not say.
    mutating func ingest(_ window: LiveReplayLeaderboardWindow) {
        let checkpointSeconds = Double((window.bucketIndex + 1) * window.context.bucketIntervalSeconds)

        for row in window.rows where !row.isLiveAttempt && !row.isCurrentUser {
            var climber = climbers[row.id] ?? Climber(
                id: row.id,
                userId: row.userId,
                curve: MountainRivalCurve(finalSteps: Double(row.finalSteps), finishSeconds: row.completionDurationSeconds)
            )
            Self.record(row, at: checkpointSeconds, into: &climber.curve)
            climbers[row.id] = climber
        }

        if let best = window.ownPreviousCompletionRow {
            var curve = yourBest ?? MountainRivalCurve(
                finalSteps: Double(best.finalSteps),
                finishSeconds: best.completionDurationSeconds
            )
            Self.record(best, at: checkpointSeconds, into: &curve)
            yourBest = curve
        }
    }

    private static func record(_ row: LiveReplayLeaderboardRow, at seconds: Double, into curve: inout MountainRivalCurve) {
        if let finish = curve.finishSeconds, finish <= seconds { return }
        curve.record(steps: Double(row.stepsAtBucket), atSeconds: seconds)
    }
}
