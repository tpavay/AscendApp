import Foundation

/// Reads where the signed-in climber stands on a steps board, so the Totals stickers can show it.
protocol ShareStandingReading: Sendable {
    /// The climber's position and the board's size for `timeFrame`, or nil when unranked or the
    /// board could not be read. A sticker that cannot say where you stand is hidden, never wrong.
    func standing(userId: String, timeFrame: LeaderboardTimeFrame) async -> ShareTotalsSnapshot.Standing?
}

/// The production reader: the same steps board the Leaderboards tab and Home read.
struct LeaderboardShareStandingReader: ShareStandingReading {
    func standing(userId: String, timeFrame: LeaderboardTimeFrame) async -> ShareTotalsSnapshot.Standing? {
        do {
            let result = try await withLeaderboardTimeout(seconds: LeaderboardRefreshPolicy.networkTimeoutSeconds) {
                try await LeaderboardRepository.shared.fetchOwnStepsStanding(
                    userId: userId,
                    timeFrame: timeFrame
                )
            }
            return ShareTotalsSnapshot.Standing(position: result?.rank, field: result?.total)
        } catch {
            return nil
        }
    }
}
