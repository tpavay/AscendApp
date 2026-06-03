import Foundation

struct LeaderboardRankSubtitleContext: Equatable {
    let rank: Int?
    let totalClimbers: Int
    let tiedForFirst: Bool
    let stepsAheadOfSecond: Int?
    let stepsFromGold: Int?
    let stepsFromSilver: Int?
    let stepsToBronze: Int?
    let stepsToTopTen: Int?
    let stepsToTopHundred: Int?
    let stepsToTopFiftyPercent: Int?
}

enum LeaderboardRankSubtitleFormatter {
    static let topHundredPopulationThreshold = 500

    static func subtitle(for context: LeaderboardRankSubtitleContext) -> String {
        guard let rank = context.rank else {
            return "Climb to be ranked"
        }

        if rank == 1 {
            if context.tiedForFirst {
                return "TIED FOR GOLD"
            }

            return "DEFENDING GOLD · \(formattedSteps(context.stepsAheadOfSecond)) AHEAD"
        }

        if rank == 2 {
            return "\(formattedSteps(context.stepsFromGold)) STEPS FROM GOLD"
        }

        if rank == 3 {
            return "\(formattedSteps(context.stepsFromSilver)) STEPS FROM SILVER"
        }

        if (4...10).contains(rank) {
            return "\(formattedSteps(context.stepsToBronze)) STEPS TO BRONZE"
        }

        let isTopHundredUnlocked = context.totalClimbers >= topHundredPopulationThreshold
        if rank <= 100, isTopHundredUnlocked {
            return "\(ProfileTerminology.topHundredAchievementLabel) · \(formattedSteps(context.stepsToTopTen)) TO TOP 10"
        }

        if rank >= 11, !isTopHundredUnlocked {
            return "\(formattedSteps(context.stepsToTopTen)) STEPS TO TOP 10"
        }

        if let percentileBand = earnedPercentileBand(rank: rank, totalClimbers: context.totalClimbers) {
            return "TOP \(percentileBand)% OF CLIMBERS"
        }

        if isTopHundredUnlocked, rank > 100 {
            return "\(formattedSteps(context.stepsToTopHundred)) STEPS TO TOP 100"
        }

        return "\(formattedSteps(context.stepsToTopFiftyPercent)) STEPS TO TOP 50%"
    }

    private static func earnedPercentileBand(rank: Int, totalClimbers: Int) -> Int? {
        guard totalClimbers > 0 else { return nil }
        let percentile = (Double(rank) / Double(totalClimbers)) * 100

        for band in [1, 5, 10, 25, 50] where percentile <= Double(band) {
            return band
        }

        return nil
    }

    private static func formattedSteps(_ value: Int?) -> String {
        max(value ?? 0, 0).formatted(.number.grouping(.automatic))
    }
}

enum ProfileStandingSubtitleFormatter {
    static let topHundredPopulationThreshold = LeaderboardRankSubtitleFormatter.topHundredPopulationThreshold

    static func subtitle(for standing: ProfileStanding) -> String {
        LeaderboardRankSubtitleFormatter.subtitle(for: standing.subtitleContext)
    }
}

private extension ProfileStanding {
    var subtitleContext: LeaderboardRankSubtitleContext {
        LeaderboardRankSubtitleContext(
            rank: rank,
            totalClimbers: totalClimbers,
            tiedForFirst: tiedForFirst,
            stepsAheadOfSecond: delta(from: previousRankValue ?? 0, to: value),
            stepsFromGold: delta(from: value, to: leaderValue),
            stepsFromSilver: delta(from: value, to: previousRankValue),
            stepsToBronze: delta(from: value, to: previousRankValue),
            stepsToTopTen: stepsToTopTen ?? delta(from: value, to: previousRankValue),
            stepsToTopHundred: stepsToTopHundred,
            stepsToTopFiftyPercent: stepsToTopFiftyPercent
        )
    }

    private func delta(from currentValue: Double, to targetValue: Double?) -> Int {
        max(Int(((targetValue ?? currentValue) - currentValue).rounded()), 0)
    }
}
