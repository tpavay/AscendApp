import Foundation
@preconcurrency import FirebaseFirestore

final class ProfileStandingService: Sendable {
    static let shared = ProfileStandingService()

    private let repository: LeaderboardRepository

    init(repository: LeaderboardRepository = .shared) {
        self.repository = repository
    }

    func loadStandings(userId: String) async -> [ProfileStanding] {
        var standings: [ProfileStanding] = []

        for timeFrame in [LeaderboardTimeFrame.weekly, .monthly, .yearly] {
            do {
                let stats = try await repository.fetchLeaderboard(
                    metric: .climb,
                    timeFrame: timeFrame,
                    limit: 1_000,
                    source: .default
                )
                standings.append(standing(for: userId, timeFrame: timeFrame, stats: stats))
            } catch {
                standings.append(
                    ProfileStanding(
                        timeFrame: timeFrame,
                        rank: nil,
                        value: 0,
                        leaderValue: nil,
                        previousRankValue: nil,
                        totalClimbers: 0,
                        tiedForFirst: false
                    )
                )
            }
        }

        return standings
    }

    private func standing(
        for userId: String,
        timeFrame: LeaderboardTimeFrame,
        stats: [FirestoreLeaderboardStats]
    ) -> ProfileStanding {
        let ranked = competitionRankedRows(stats)
        guard let userRow = ranked.first(where: { $0.stat.userId == userId }) else {
            return ProfileStanding(
                timeFrame: timeFrame,
                rank: nil,
                value: 0,
                leaderValue: ranked.first?.value,
                previousRankValue: nil,
                totalClimbers: ranked.count,
                tiedForFirst: false
            )
        }

        let leaderValue = ranked.first?.value
        let tiedForFirst = userRow.rank == 1 && ranked.filter { $0.rank == 1 }.count > 1
        let topTenValue = thresholdValue(at: 10, in: ranked)
        let topHundredValue = thresholdValue(at: 100, in: ranked)
        let topFiftyPercentValue = thresholdValue(
            at: topFiftyPercentRank(totalClimbers: ranked.count),
            in: ranked
        )
        let targetRank: Int? = {
            switch userRow.rank {
            case 1:
                return ranked.first { $0.rank > 1 }?.rank
            case 2:
                return 1
            case 3:
                return 2
            case 4...10:
                return 3
            case 11...100:
                return 10
            default:
                return nil
            }
        }()
        let targetValue = targetRank.flatMap { target in ranked.first { $0.rank == target }?.value }

        return ProfileStanding(
            timeFrame: timeFrame,
            rank: userRow.rank,
            value: userRow.value,
            leaderValue: leaderValue,
            previousRankValue: targetValue,
            totalClimbers: ranked.count,
            tiedForFirst: tiedForFirst,
            stepsToTopTen: stepDelta(from: userRow.value, to: topTenValue),
            stepsToTopHundred: stepDelta(from: userRow.value, to: topHundredValue),
            stepsToTopFiftyPercent: stepDelta(from: userRow.value, to: topFiftyPercentValue)
        )
    }

    private func competitionRankedRows(
        _ stats: [FirestoreLeaderboardStats]
    ) -> [(stat: FirestoreLeaderboardStats, rank: Int, value: Double)] {
        var rows: [(FirestoreLeaderboardStats, Int, Double)] = []
        var lastValue: Double?
        var currentRank = 0

        for (index, stat) in stats.enumerated() {
            let value = stat.value(for: .climb)
            if lastValue != value {
                currentRank = index + 1
                lastValue = value
            }
            rows.append((stat, currentRank, value))
        }

        return rows
    }

    private func thresholdValue(
        at rankThreshold: Int,
        in rows: [(stat: FirestoreLeaderboardStats, rank: Int, value: Double)]
    ) -> Double? {
        guard rankThreshold > 0, rows.count >= rankThreshold else { return nil }
        return rows[rankThreshold - 1].value
    }

    private func topFiftyPercentRank(totalClimbers: Int) -> Int {
        guard totalClimbers > 0 else { return 0 }
        return max(Int(ceil(Double(totalClimbers) * 0.5)), 1)
    }

    private func stepDelta(from value: Double, to targetValue: Double?) -> Int? {
        guard let targetValue else { return nil }
        return max(Int((targetValue - value).rounded()), 0)
    }
}
