import Foundation

struct ProfileStanding: Identifiable, Equatable {
    let timeFrame: LeaderboardTimeFrame
    let rank: Int?
    let value: Double
    let leaderValue: Double?
    let previousRankValue: Double?
    let totalClimbers: Int
    let tiedForFirst: Bool
    let stepsToTopTen: Int?
    let stepsToTopHundred: Int?
    let stepsToTopFiftyPercent: Int?

    init(
        timeFrame: LeaderboardTimeFrame,
        rank: Int?,
        value: Double,
        leaderValue: Double?,
        previousRankValue: Double?,
        totalClimbers: Int,
        tiedForFirst: Bool,
        stepsToTopTen: Int? = nil,
        stepsToTopHundred: Int? = nil,
        stepsToTopFiftyPercent: Int? = nil
    ) {
        self.timeFrame = timeFrame
        self.rank = rank
        self.value = value
        self.leaderValue = leaderValue
        self.previousRankValue = previousRankValue
        self.totalClimbers = totalClimbers
        self.tiedForFirst = tiedForFirst
        self.stepsToTopTen = stepsToTopTen
        self.stepsToTopHundred = stepsToTopHundred
        self.stepsToTopFiftyPercent = stepsToTopFiftyPercent
    }

    var id: String { timeFrame.rawValue }

    var hasRank: Bool {
        rank != nil
    }
}
