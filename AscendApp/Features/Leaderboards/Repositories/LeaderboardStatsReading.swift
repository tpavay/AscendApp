import Foundation
@preconcurrency import FirebaseFirestore

/// The standings read `LeaderboardViewModel` depends on.
///
/// A protocol so a test can hand the view model a read that fails the way Firestore does -
/// unreachable, refused, or something else - without a server or a signed-in session.
protocol LeaderboardStatsReading: Sendable {
    func fetchLeaderboard(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        limit: Int,
        source: FirestoreSource
    ) async throws -> [FirestoreLeaderboardStats]
}

extension LeaderboardRepository: LeaderboardStatsReading {}
