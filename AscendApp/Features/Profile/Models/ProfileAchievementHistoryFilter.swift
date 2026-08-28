import Foundation

/// Which finalized rows an achievement badge's history sheet lists.
///
/// A band badge lists every finish inside the band. A placement badge lists only the finishes
/// at that exact rank, because an exact rank is the only claim that badge makes.
enum ProfileAchievementHistoryFilter: Identifiable, Equatable, Sendable {
    case band(ProfileAchievementRankBand)
    case placement(Int)

    var id: String {
        switch self {
        case .band(let band):
            "band-\(band.rawValue)"
        case .placement(let rank):
            "placement-\(rank)"
        }
    }

    var label: String {
        switch self {
        case .band(let band):
            band.label
        case .placement(let rank):
            "#\(rank)"
        }
    }

    var emptyStatePrompt: String {
        switch self {
        case .band(let band):
            "Finish a leaderboard period inside \(band.label) and the proof lands here."
        case .placement(let rank):
            "Finish a leaderboard period at #\(rank) and the proof lands here."
        }
    }

    func matches(_ record: ProfileAchievementRecord) -> Bool {
        switch self {
        case .band(let band):
            record.countsToward(band)
        case .placement(let rank):
            record.rankBand != nil && record.rank == rank
        }
    }
}
