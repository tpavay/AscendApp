import Foundation

enum LeaderboardCurrentUserReconciler {
    static func reconcilePreviewStats(
        _ statsByMetric: [LeaderboardMetric: [FirestoreLeaderboardStats]],
        userId: String,
        displayName: String,
        localStats: LeaderboardStats
    ) -> [LeaderboardMetric: [FirestoreLeaderboardStats]] {
        var resolved = statsByMetric

        for metric in LeaderboardMetric.allCases {
            resolved[metric] = reconcileStats(
                resolved[metric] ?? [],
                metric: metric,
                userId: userId,
                displayName: displayName,
                localStats: localStats
            )
        }

        return resolved
    }

    static func reconcileDetailStats(
        _ stats: [FirestoreLeaderboardStats],
        metric: LeaderboardMetric,
        userId: String,
        displayName: String,
        localStats: LeaderboardStats
    ) -> [FirestoreLeaderboardStats] {
        reconcileStats(
            stats,
            metric: metric,
            userId: userId,
            displayName: displayName,
            localStats: localStats
        )
    }

    private static func reconcileStats(
        _ stats: [FirestoreLeaderboardStats],
        metric: LeaderboardMetric,
        userId: String,
        displayName: String,
        localStats: LeaderboardStats
    ) -> [FirestoreLeaderboardStats] {
        var resolved = stats
        if localStats.hasActivity == false {
            resolved.removeAll { $0.userId == userId }
            return resolved
        }

        if let currentIndex = resolved.firstIndex(where: { $0.userId == userId }) {
            let existing = resolved[currentIndex]
            resolved[currentIndex] = FirestoreLeaderboardStats(
                userId: existing.userId,
                unresolvedIdentity: existing.identityApplyingOverrides(
                    displayName: displayName,
                    photoURL: nil
                ),
                identityPolicyVersion: existing.identityPolicyVersion,
                identityChangedAt: existing.identityChangedAt,
                timeFrame: existing.timeFrame,
                schemaVersion: existing.schemaVersion,
                periodKey: existing.periodKey,
                periodStartAt: existing.periodStartAt,
                totalSteps: localStats.totalSteps,
                totalFloors: localStats.totalFloors,
                totalWorkouts: localStats.totalWorkouts,
                totalDuration: localStats.totalDuration,
                stepsPerMinute: localStats.stepsPerMinute,
                lastUpdated: max(existing.lastUpdated, localStats.lastUpdated),
                age: existing.age,
                weightKg: existing.weightKg,
                locationCity: existing.locationCity,
                locationCountry: existing.locationCountry,
                locationRegion: existing.locationRegion
            )
        } else {
            resolved.append(
                FirestoreLeaderboardStats(
                    userId: userId,
                    displayName: displayName,
                    photoURL: nil,
                    timeFrame: localStats.timeFrameEnum.rawValue,
                    schemaVersion: localStats.schemaVersion,
                    periodKey: localStats.periodKey,
                    periodStartAt: localStats.periodStartAt,
                    totalSteps: localStats.totalSteps,
                    totalFloors: localStats.totalFloors,
                    totalWorkouts: localStats.totalWorkouts,
                    totalDuration: localStats.totalDuration,
                    stepsPerMinute: localStats.stepsPerMinute,
                    lastUpdated: localStats.lastUpdated
                )
            )
        }

        resolved.sort { lhs, rhs in
            let lhsValue = lhs.value(for: metric)
            let rhsValue = rhs.value(for: metric)
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
            return lhs.userId < rhs.userId
        }

        return resolved
    }
}
