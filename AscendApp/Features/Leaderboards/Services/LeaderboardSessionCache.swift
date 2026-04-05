import Foundation

actor LeaderboardSessionCache {
    static let shared = LeaderboardSessionCache()

    struct DetailKey: Hashable, Sendable {
        let timeFrame: LeaderboardTimeFrame
        let metric: LeaderboardMetric
    }

    private var detailCache: [DetailKey: [FirestoreLeaderboardStats]] = [:]
    private var previewCache: [LeaderboardTimeFrame: [LeaderboardMetric: [FirestoreLeaderboardStats]]] = [:]

    func detailEntries(
        for metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame
    ) -> [FirestoreLeaderboardStats]? {
        detailCache[DetailKey(timeFrame: timeFrame, metric: metric)]
    }

    func setDetailEntries(
        _ entries: [FirestoreLeaderboardStats],
        for metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame
    ) {
        detailCache[DetailKey(timeFrame: timeFrame, metric: metric)] = entries
    }

    func previewEntries(
        for timeFrame: LeaderboardTimeFrame
    ) -> [LeaderboardMetric: [FirestoreLeaderboardStats]]? {
        previewCache[timeFrame]
    }

    func setPreviewEntries(
        _ entries: [LeaderboardMetric: [FirestoreLeaderboardStats]],
        for timeFrame: LeaderboardTimeFrame
    ) {
        previewCache[timeFrame] = entries
    }

    func invalidateAll() {
        detailCache.removeAll()
        previewCache.removeAll()
    }

    func invalidate(timeFrame: LeaderboardTimeFrame) {
        previewCache.removeValue(forKey: timeFrame)
        detailCache = detailCache.filter { $0.key.timeFrame != timeFrame }
    }

    func updateCurrentUserProfile(userId: String, displayName: String?, photoURL: URL?) {
        detailCache = detailCache.mapValues { stats in
            stats.map { stat in
                guard stat.userId == userId else { return stat }
                return FirestoreLeaderboardStats(
                    userId: stat.userId,
                    displayName: displayName ?? stat.displayName,
                    photoURL: photoURL?.absoluteString ?? stat.photoURL,
                    timeFrame: stat.timeFrame,
                    schemaVersion: stat.schemaVersion,
                    periodKey: stat.periodKey,
                    periodStartAt: stat.periodStartAt,
                    totalSteps: stat.totalSteps,
                    totalFloors: stat.totalFloors,
                    totalWorkouts: stat.totalWorkouts,
                    totalDuration: stat.totalDuration,
                    stepsPerMinute: stat.stepsPerMinute,
                    lastUpdated: stat.lastUpdated
                )
            }
        }

        previewCache = previewCache.mapValues { metrics in
            Dictionary(uniqueKeysWithValues: metrics.map { metric, stats in
                let updatedStats = stats.map { stat in
                    guard stat.userId == userId else { return stat }
                    return FirestoreLeaderboardStats(
                        userId: stat.userId,
                        displayName: displayName ?? stat.displayName,
                        photoURL: photoURL?.absoluteString ?? stat.photoURL,
                        timeFrame: stat.timeFrame,
                        schemaVersion: stat.schemaVersion,
                        periodKey: stat.periodKey,
                        periodStartAt: stat.periodStartAt,
                        totalSteps: stat.totalSteps,
                        totalFloors: stat.totalFloors,
                        totalWorkouts: stat.totalWorkouts,
                        totalDuration: stat.totalDuration,
                        stepsPerMinute: stat.stepsPerMinute,
                        lastUpdated: stat.lastUpdated
                    )
                }
                return (metric, updatedStats)
            })
        }
    }
}
