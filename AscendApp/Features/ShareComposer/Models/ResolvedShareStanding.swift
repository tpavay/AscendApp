import Foundation

/// The frozen leaderboard population a recap card renders against.
struct ResolvedShareStanding: Equatable, Sendable {
    let rank: Int
    let totalClimbers: Int
    let percentile: Int

    var isFirstAscent: Bool {
        totalClimbers == 1
    }

    var ordinalRank: String {
        Self.ordinal(rank)
    }

    var formattedFieldSize: String {
        totalClimbers.formatted(.number.grouping(.automatic))
    }

    init?(rank: Int?, totalClimbers: Int?, percentile: Int? = nil) {
        guard let rank, let totalClimbers, rank > 0, totalClimbers > 0 else {
            return nil
        }

        self.rank = min(rank, totalClimbers)
        self.totalClimbers = totalClimbers
        if let percentile {
            self.percentile = min(max(percentile, 1), 99)
        } else if totalClimbers == 1 {
            self.percentile = 99
        } else {
            let fieldBeat = Double(totalClimbers - self.rank) / Double(totalClimbers)
            self.percentile = min(max(Int((fieldBeat * 100).rounded(.down)), 1), 99)
        }
    }

    private static func ordinal(_ value: Int) -> String {
        let tens = value % 100
        if (11...13).contains(tens) {
            return "\(value)th"
        }

        switch value % 10 {
        case 1: return "\(value)st"
        case 2: return "\(value)nd"
        case 3: return "\(value)rd"
        default: return "\(value)th"
        }
    }
}
