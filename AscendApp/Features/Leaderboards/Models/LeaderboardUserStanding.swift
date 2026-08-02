import Foundation

/// Where the signed-in climber stands on the board currently on screen.
///
/// A rank is earned by climbing inside the period window; it is never conferred by
/// holding an account. A climber with nothing logged this period is `unranked` - they
/// hold no rank number at all, which is why this is an enum rather than an entry with a
/// rank the caller has to know to distrust.
///
/// This exists because the pinned "you" row used to fabricate `leaderboardEntries.count + 1`
/// for exactly this case. That is a positional rank, and it contradicted the podium beside
/// it: the podium ranks through `CompetitionRanking` over entries that deliberately exclude
/// a zero-activity climber, so it showed places 2 and 3 unclaimed while the row below
/// claimed place 2. `CompetitionRanking` stays the only producer of a rank number.
enum LeaderboardUserStanding: Equatable, Sendable {
    /// The climber holds a rank this period, ranked with everyone else.
    case ranked(LeaderboardEntry)

    /// The climber has logged nothing in this window, so they are on no rung of the ladder.
    case unranked(value: Double, formattedValue: String)

    var rankedEntry: LeaderboardEntry? {
        guard case .ranked(let entry) = self else { return nil }
        return entry
    }

    var value: Double {
        switch self {
        case .ranked(let entry):
            return entry.value
        case .unranked(let value, _):
            return value
        }
    }

    var formattedValue: String {
        switch self {
        case .ranked(let entry):
            return entry.formattedValue
        case .unranked(_, let formattedValue):
            return formattedValue
        }
    }
}
