import Foundation

struct LeaderboardPeriod: Equatable, Hashable, Sendable {
    let timeFrame: LeaderboardTimeFrame
    let key: String
    let startAt: Date
    let endAt: Date?

    func contains(_ date: Date, referenceDate: Date = Date()) -> Bool {
        if let endAt {
            return date >= startAt && date < endAt
        }

        return date <= referenceDate
    }
}
