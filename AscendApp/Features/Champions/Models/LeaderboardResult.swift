import Foundation

/// The frozen final result of one closed Steps board, written by the nightly finalizer
/// (`leaderboard_results/{timeFrame}_{periodKey}`).
///
/// It is the record past boards, the champion strip and the recap read, so a champion who
/// later deletes their account stays champion instead of promoting the runner-up.
struct LeaderboardResult: Equatable, Sendable {
    struct MostClimbs: Equatable, Sendable {
        let count: Int
        let userIds: [String]
    }

    struct Community: Equatable, Sendable {
        let climbers: Int
        let climbs: Int
        let steps: Int
        let floors: Int

        static let empty = Community(climbers: 0, climbs: 0, steps: 0, floors: 0)
    }

    let period: LeaderboardPeriod
    let climberCount: Int
    let championUserIds: [String]
    let podiumUserIds: [String]
    let mostClimbs: MostClimbs?
    let community: Community

    var id: String {
        Self.documentID(timeFrame: period.timeFrame, periodKey: period.key)
    }

    var timeFrame: LeaderboardTimeFrame {
        period.timeFrame
    }

    var title: ChampionTitle? {
        ChampionTitle(timeFrame: period.timeFrame)
    }

    var hasChampion: Bool {
        !championUserIds.isEmpty
    }

    static func documentID(timeFrame: LeaderboardTimeFrame, periodKey: String) -> String {
        "\(timeFrame.rawValue)_\(periodKey)"
    }
}

/// One climber's frozen standing on a closed board
/// (`leaderboard_results/{resultId}/placings/{uid}`).
struct LeaderboardPlacing: Equatable, Sendable {
    let userId: String
    let unresolvedIdentity: UnresolvedUserIdentity
    let rank: Int
    let totalSteps: Int
    let totalWorkouts: Int

    /// The placing as a board entry, so a past board renders through the same podium,
    /// rows and moderation boundary as the live one.
    func entry(isCurrentUser: Bool, isTied: Bool) -> LeaderboardEntry {
        LeaderboardEntry(
            userId: userId,
            unresolvedIdentity: unresolvedIdentity,
            rank: rank,
            value: Double(totalSteps),
            formattedValue: totalSteps.formatted(.number.grouping(.automatic)),
            isCurrentUser: isCurrentUser,
            isTied: isTied
        )
    }
}

extension Array where Element == LeaderboardPlacing {
    /// Placings as board entries, with each shared rank marked as a tie.
    func entries(currentUserId: String?) -> [LeaderboardEntry] {
        let rankCounts = Dictionary(grouping: self, by: \.rank).mapValues(\.count)
        return map {
            $0.entry(
                isCurrentUser: $0.userId == currentUserId,
                isTied: (rankCounts[$0.rank] ?? 0) > 1
            )
        }
    }
}
