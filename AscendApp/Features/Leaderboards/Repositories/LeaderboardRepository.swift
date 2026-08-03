import Foundation
@preconcurrency import FirebaseFirestore

final class LeaderboardRepository: Sendable {
    static let shared = LeaderboardRepository()
    private let db = Firestore.firestore()

    private init() {}

    func documentID(userId: String, timeFrame: LeaderboardTimeFrame, periodKey: String) -> String {
        "\(timeFrame.rawValue)_\(periodKey)_\(userId)"
    }

    func documentID(userId: String, timeFrame: LeaderboardTimeFrame, period: LeaderboardPeriod) -> String {
        documentID(userId: userId, timeFrame: timeFrame, periodKey: period.key)
    }

    func currentDocumentID(userId: String, timeFrame: LeaderboardTimeFrame) -> String {
        documentID(userId: userId, timeFrame: timeFrame, period: timeFrame.currentPeriod())
    }

    // Standings are server-derived and this collection is read-only to clients
    // (firestore.rules, functions/src/leaderboardStats.ts). There is deliberately
    // no write here: a device that could publish its own totals is the whole of
    // issue #307.

    func fetchLeaderboard(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        limit: Int = 100,
        source: FirestoreSource = .default
    ) async throws -> [FirestoreLeaderboardStats] {
        let period = timeFrame.currentPeriod()
        return try await fetchLeaderboard(
            metric: metric,
            timeFrame: timeFrame,
            period: period,
            limit: limit,
            source: source
        )
    }

    func fetchLeaderboard(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        period: LeaderboardPeriod,
        limit: Int = 100,
        source: FirestoreSource = .default
    ) async throws -> [FirestoreLeaderboardStats] {
        let query = db.collection("leaderboard_stats")
            .whereField("timeFrame", isEqualTo: timeFrame.rawValue)
            .whereField("periodStartAt", isEqualTo: Timestamp(date: period.startAt))
            .order(by: metric.sortField, descending: true)
            .limit(to: max(limit, 0))

        let snapshot = try await query.getDocuments(source: source)
        var statsByUserId: [String: FirestoreLeaderboardStats] = [:]
        var canonicalUserIds = Set<String>()

        for document in snapshot.documents {
            let data = document.data()
            guard let stat = parseStat(data) else { continue }
            guard stat.periodStartAt == period.startAt else { continue }
            let canonicalID = documentID(userId: stat.userId, timeFrame: timeFrame, periodKey: stat.periodKey)
            let isCanonical = document.documentID == canonicalID

            if let existing = statsByUserId[stat.userId] {
                let existingIsCanonical = canonicalUserIds.contains(stat.userId)
                if isCanonical && !existingIsCanonical {
                    statsByUserId[stat.userId] = stat
                    canonicalUserIds.insert(stat.userId)
                } else if isCanonical == existingIsCanonical && stat.lastUpdated > existing.lastUpdated {
                    statsByUserId[stat.userId] = stat
                }
            } else {
                statsByUserId[stat.userId] = stat
                if isCanonical {
                    canonicalUserIds.insert(stat.userId)
                }
            }
        }

        // userId only breaks ties in the *ordering* — it never breaks ties in rank.
        // Matches the server's ordering in functions/src/leaderboardAchievements.ts.
        let stats = statsByUserId.values.sorted {
            let lhs = $0.value(for: metric)
            let rhs = $1.value(for: metric)
            if lhs != rhs { return lhs > rhs }
            return $0.userId < $1.userId
        }

        return stats
    }

    func getUserRank(
        userId: String,
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame
    ) async throws -> (rank: Int, total: Int)? {
        let allStats = try await fetchLeaderboard(
            metric: metric,
            timeFrame: timeFrame,
            limit: 1000
        )

        guard let index = allStats.firstIndex(where: { $0.userId == userId }),
              let rank = CompetitionRanking.rank(at: index, in: allStats, key: { $0.value(for: metric) })
        else {
            return nil
        }

        return (rank: rank, total: allStats.count)
    }

    func parseStat(_ data: [String: Any]) -> FirestoreLeaderboardStats? {
        guard let userId = data["userId"] as? String,
              let identityPolicyVersion = intValue(for: "identityPolicyVersion", in: data),
              identityPolicyVersion == PublicClimberIdentity.policyVersion,
              let identityState = data["identityState"] as? String,
              ["published", "pending_public_profile", "deleted"].contains(identityState),
              let timeFrame = data["timeFrame"] as? String,
              let periodKey = data["periodKey"] as? String,
              let periodStartAt = timestampValue(for: "periodStartAt", in: data),
              let lastUpdated = timestampValue(for: "lastUpdated", in: data) else {
            return nil
        }

        let identityChangedAt = timestampValue(for: "identityChangedAt", in: data)
        guard identityState != "published" || identityChangedAt != nil else {
            return nil
        }

        let schemaVersion = intValue(for: "schemaVersion", in: data) ?? 1
        let totalSteps = intValue(for: "totalSteps", in: data) ?? 0
        let totalFloors = intValue(for: "totalFloors", in: data) ?? 0
        let totalWorkouts = intValue(for: "totalWorkouts", in: data) ?? 0
        let totalDuration = doubleValue(for: "totalDuration", in: data) ?? 0
        let stepsPerMinute = doubleValue(for: "stepsPerMinute", in: data) ?? 0
        let identity = if identityState == "published" {
            PublicClimberIdentity.resolve(
                userId: userId,
                storedDisplayName: data["displayName"] as? String,
                storedPhotoURL: (data["photoURL"] as? String).flatMap(URL.init(string:))
            )
        } else {
            PublicClimberIdentity.resolve(
                userId: userId,
                storedDisplayName: PublicClimberIdentity.anonymousDisplayName,
                storedPhotoURL: nil
            )
        }

        guard totalWorkouts > 0 || totalSteps > 0 || totalFloors > 0 || totalDuration > 0 else {
            return nil
        }

        return FirestoreLeaderboardStats(
            userId: userId,
            displayName: identity.displayName,
            photoURL: identity.photoURL?.absoluteString,
            identityPolicyVersion: identityPolicyVersion,
            identityChangedAt: identityChangedAt ?? .distantPast,
            timeFrame: timeFrame,
            schemaVersion: schemaVersion,
            periodKey: periodKey,
            periodStartAt: periodStartAt,
            totalSteps: totalSteps,
            totalFloors: totalFloors,
            totalWorkouts: totalWorkouts,
            totalDuration: totalDuration,
            stepsPerMinute: stepsPerMinute,
            lastUpdated: lastUpdated,
            age: intValue(for: "age", in: data),
            weightKg: doubleValue(for: "weight_kg", in: data),
            locationCity: data["location_city"] as? String,
            locationCountry: data["location_country"] as? String,
            locationRegion: data["location_region"] as? String
        )
    }

    private func intValue(for key: String, in data: [String: Any]) -> Int? {
        if let value = data[key] as? Int { return value }
        if let value = data[key] as? Int64 { return Int(value) }
        if let value = data[key] as? Double { return Int(value) }
        if let value = data[key] as? NSNumber { return value.intValue }
        return nil
    }

    private func doubleValue(for key: String, in data: [String: Any]) -> Double? {
        if let value = data[key] as? Double { return value }
        if let value = data[key] as? Int { return Double(value) }
        if let value = data[key] as? Int64 { return Double(value) }
        if let value = data[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    private func timestampValue(for key: String, in data: [String: Any]) -> Date? {
        if let timestamp = data[key] as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = data[key] as? Date {
            return date
        }
        return nil
    }
}
