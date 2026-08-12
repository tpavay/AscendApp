import Foundation

/// The single piece of board content the Climb Detail Leaderboard tab renders beneath the First
/// Ascent line. Resolution is exhaustive: every combination of inputs maps to exactly one case, so
/// the tab can never fall through to an unlabelled frame.
enum ClimbLeaderboardPageContent: Equatable {
    /// Ranked rows arrived and render.
    case rows

    /// The board is still on its way. A climber with a published completion resolves here while
    /// the board rows lag their rank, because "no completed times yet" would be false for them.
    case loading

    /// Nobody has finished this climb, so the First Ascent is open.
    case empty

    /// The board fetch failed for a climber who already has a standing on it. The page's
    /// "Leaderboard unavailable" line carries the state; claiming a load is in flight would not.
    case unavailable

    static func resolve(
        hasCompletionRows: Bool,
        isLeaderboardLoading: Bool,
        hasPersonalCompletionStanding: Bool,
        hasLeaderboardError: Bool,
        publicResultSyncPhase: LiveClimbPublicResultPhase?
    ) -> ClimbLeaderboardPageContent {
        if hasCompletionRows {
            return .rows
        }

        if isLeaderboardLoading {
            return .loading
        }

        guard !hasPersonalCompletionStanding else {
            return hasLeaderboardError ? .unavailable : .loading
        }

        switch publicResultSyncPhase {
        case .pending, .syncingRanking:
            return .loading
        case .savedOnDevice, .syncFailedRetry, .published, nil:
            return .empty
        }
    }
}
