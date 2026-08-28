import Foundation

/// How many times a climber finished at an exact place, counted from finalized records.
///
/// Every achievement record stores the rank the climber actually finished at, so these are
/// counted rather than inferred. Records outside the leaderboard taxonomy - a First Ascent -
/// carry no rank band and are ignored.
struct ProfileExactPlacementCounts: Equatable {
    let second: Int
    let third: Int

    static let zero = ProfileExactPlacementCounts(second: 0, third: 0)

    init(second: Int, third: Int) {
        self.second = max(second, 0)
        self.third = max(third, 0)
    }

    init(records: [ProfileAchievementRecord]) {
        var second = 0
        var third = 0

        for record in records where record.rankBand != nil {
            switch record.rank {
            case 2:
                second += 1
            case 3:
                third += 1
            default:
                break
            }
        }

        self.init(second: second, third: third)
    }
}

/// Everything a profile can prove about one climber's leaderboard finishes.
///
/// `counts` are the cumulative bands. `placements` are the exact finishes, and they exist
/// only when the finalized records loaded: the `profile_stats` counters are banded into
/// top 1 / 3 / 10 / 100 and carry no second-versus-third breakdown, so a profile that fell
/// back to them reports `nil` and the placement badges are withheld rather than guessed at.
struct ProfileAchievementLadder: Equatable, Sendable {
    let counts: ProfileAchievementCounts
    let records: [ProfileAchievementRecord]
    let placements: ProfileExactPlacementCounts?

    static let empty = ProfileAchievementLadder(records: [])

    /// The finalized records themselves, so every placement is provable.
    init(records: [ProfileAchievementRecord]) {
        self.counts = ProfileAchievementCounts(records: records)
        self.records = records
        self.placements = ProfileExactPlacementCounts(records: records)
    }

    /// Only the banded `profile_stats` counters reached the client. Nothing here can name an
    /// exact placement, so nothing does.
    init(bandedCounters counts: ProfileAchievementCounts) {
        self.counts = counts
        self.records = []
        self.placements = nil
    }

    var hasAny: Bool {
        counts.hasAny
    }

    /// How many times this climber finished exactly second, or `nil` when this ladder cannot
    /// say. See `exactFinishes(atRank:)` for why a banded ladder can sometimes still answer.
    var secondPlaceFinishes: Int? {
        exactFinishes(atRank: 2)
    }

    /// How many times this climber finished exactly third, or `nil` when this ladder cannot say.
    var thirdPlaceFinishes: Int? {
        exactFinishes(atRank: 3)
    }

    /// `nil` means *this ladder cannot speak to that rank* - which is not the same as zero.
    ///
    /// The banded `profile_stats` counters carry no second-versus-third breakdown, so a ladder
    /// built from them normally cannot tell one apart from the other. It can at zero: every
    /// second and third place also counts toward `top3`, so when `top3` holds nothing beyond
    /// the champion finishes there is provably nothing on the podium below first. Withholding
    /// that answer would hide a decorated climber's own row rather than protect anyone.
    private func exactFinishes(atRank rank: Int) -> Int? {
        if let placements {
            return rank == 2 ? placements.second : placements.third
        }
        return counts.top3 == counts.top1 ? 0 : nil
    }
}
