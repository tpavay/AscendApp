import Foundation

/// A title and who holds it: the result of the period immediately before the current one.
///
/// A weekly champion reigns through the following week, a monthly champion through the
/// following month, a yearly champion through the following year. When a new period
/// closes the reign ends, whether or not the next result has landed yet.
struct ChampionReign: Equatable, Sendable {
    let title: ChampionTitle
    let result: LeaderboardResult
    /// The rank-1 placings, board order. More than one only on an exact tie.
    let champions: [LeaderboardPlacing]

    var championUserIds: Set<String> {
        Set(result.championUserIds)
    }

    /// When the crown comes off: the end of the period after the one that was won.
    var endsAt: Date? {
        result.period.next?.endAt
    }

    /// Whether this reign is still the live one at `date`. The reigning result is always the
    /// previous period's; anything older has been superseded.
    func isCurrent(at date: Date) -> Bool {
        title.timeFrame.previousPeriod(referenceDate: date)?.key == result.period.key
    }
}
