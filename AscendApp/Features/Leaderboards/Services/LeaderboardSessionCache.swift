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

}
