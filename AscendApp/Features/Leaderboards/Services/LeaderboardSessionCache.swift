import Foundation

actor LeaderboardSessionCache {
    static let shared = LeaderboardSessionCache()

    struct DetailKey: Hashable, Sendable {
        let timeFrame: LeaderboardTimeFrame
        let metric: LeaderboardMetric
        let limit: Int
    }

    private var detailCache: [DetailKey: [FirestoreLeaderboardStats]] = [:]
    private var previewCache: [LeaderboardTimeFrame: [LeaderboardMetric: [FirestoreLeaderboardStats]]] = [:]

    func detailEntries(
        for metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        minimumLimit: Int = 100
    ) -> [FirestoreLeaderboardStats]? {
        detailCache
            .filter {
                $0.key.timeFrame == timeFrame &&
                    $0.key.metric == metric &&
                    $0.key.limit >= minimumLimit
            }
            .sorted { $0.key.limit < $1.key.limit }
            .first?
            .value
    }

    func setDetailEntries(
        _ entries: [FirestoreLeaderboardStats],
        for metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        limit: Int? = nil
    ) {
        detailCache[DetailKey(
            timeFrame: timeFrame,
            metric: metric,
            limit: limit ?? 100
        )] = entries
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
                    lastUpdated: stat.lastUpdated,
                    age: stat.age,
                    weightKg: stat.weightKg,
                    locationCity: stat.locationCity,
                    locationCountry: stat.locationCountry,
                    locationRegion: stat.locationRegion
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
                        lastUpdated: stat.lastUpdated,
                        age: stat.age,
                        weightKg: stat.weightKg,
                        locationCity: stat.locationCity,
                        locationCountry: stat.locationCountry,
                        locationRegion: stat.locationRegion
                    )
                }
                return (metric, updatedStats)
            })
        }
    }
}
