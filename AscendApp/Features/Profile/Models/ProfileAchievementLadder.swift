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
/// back to them withholds the placement badges rather than guessing at them. The one thing
/// such a profile can still prove is an empty podium below first - see `exactFinishes(atRank:)`.
///
/// A ladder is one of three things, and the three are deliberately not interchangeable:
/// record-backed (every count is provable), banded (the bands are provable and the exact
/// placements are not), or `unreadable` - nobody managed to read this climber's ladder at all,
/// so every count is `nil` and a zero is never claimed on their behalf.
struct ProfileAchievementLadder: Equatable, Sendable {
    let counts: ProfileAchievementCounts
    let records: [ProfileAchievementRecord]
    let placements: ProfileExactPlacementCounts?
    /// `false` only when the read that would have filled this ladder failed. Zeroed counts on an
    /// unreadable ladder are placeholders nobody may quote.
    let isReadable: Bool

    /// Record-backed and genuinely empty: this climber holds nothing, and we know it.
    static let empty = ProfileAchievementLadder(records: [])

    /// The read failed. Distinct from `empty`, which is a measured zero.
    static let unreadable = ProfileAchievementLadder(unreadable: ())

    /// The finalized records themselves, so every placement is provable.
    init(records: [ProfileAchievementRecord]) {
        self.counts = ProfileAchievementCounts(records: records)
        self.records = records
        self.placements = ProfileExactPlacementCounts(records: records)
        self.isReadable = true
    }

    /// Only the banded `profile_stats` counters reached the client. Nothing here can name an
    /// exact placement, so nothing does.
    init(bandedCounters counts: ProfileAchievementCounts) {
        self.counts = counts
        self.records = []
        self.placements = nil
        self.isReadable = true
    }

    private init(unreadable: ()) {
        self.counts = .zero
        self.records = []
        self.placements = nil
        self.isReadable = false
    }

    /// How many finishes this climber has inside a cumulative band, or `nil` when the ladder was
    /// never read. The bands are the one thing both readable ladders can always answer.
    func bandFinishes(_ band: ProfileAchievementRankBand) -> Int? {
        guard isReadable else { return nil }

        switch band {
        case .top1:
            return counts.top1
        case .top3:
            return counts.top3
        case .top10:
            return counts.top10
        case .top100:
            return counts.top100
        }
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
        guard isReadable else { return nil }

        if let placements {
            return rank == 2 ? placements.second : placements.third
        }
        return counts.top3 == counts.top1 ? 0 : nil
    }
}
