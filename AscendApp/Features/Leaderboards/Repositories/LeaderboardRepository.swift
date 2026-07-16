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

    func upsertStats(_ payload: LeaderboardSyncPayload) async throws {
        let docRef = db.collection("leaderboard_stats")
            .document(documentID(userId: payload.userId, timeFrame: payload.timeFrame, periodKey: payload.periodKey))

        var data: [String: Any] = [
            "userId": payload.userId,
            "displayName": payload.displayName,
            "photoURL": payload.photoURL?.absoluteString ?? "",
            "timeFrame": payload.timeFrame.rawValue,
            "schemaVersion": payload.schemaVersion,
            "periodKey": payload.periodKey,
            "periodStartAt": Timestamp(date: payload.periodStartAt),
            "totalSteps": payload.totalSteps,
            "totalFloors": payload.totalFloors,
            "totalWorkouts": payload.totalWorkouts,
            "totalDuration": payload.totalDuration,
            "stepsPerMinute": payload.stepsPerMinute,
            "lastUpdated": FieldValue.serverTimestamp()
        ]

        if let profile = payload.profile {
            setOptional(profile.age, for: "age", in: &data)
            setOptional(profile.weightKg, for: "weight_kg", in: &data)
            setOptional(profile.locationCity, for: "location_city", in: &data)
            setOptional(profile.locationCountry, for: "location_country", in: &data)
            setOptional(profile.locationRegion, for: "location_region", in: &data)
        }

        try await docRef.setData(data, merge: true)
    }

    func deleteStats(userId: String, timeFrame: LeaderboardTimeFrame, periodKey: String) async throws {
        let docRef = db.collection("leaderboard_stats")
            .document(documentID(userId: userId, timeFrame: timeFrame, periodKey: periodKey))
        try await docRef.delete()
    }

    func deleteLegacyStats(userId: String) async throws {
        let snapshot = try await db.collection("leaderboard_stats")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        let legacyDocumentIDs = Set(LeaderboardTimeFrame.allCases.map { "\(userId)_\($0.rawValue)" })
        for document in snapshot.documents where legacyDocumentIDs.contains(document.documentID) {
            try await document.reference.delete()
        }
    }

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

        guard let index = allStats.firstIndex(where: { $0.userId == userId }) else {
            return nil
        }

        return (rank: index + 1, total: allStats.count)
    }

    func updateProfilePictureURL(userId: String, photoURL: String) async throws {
        let snapshot = try await db.collection("leaderboard_stats")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        for document in snapshot.documents {
            try await document.reference.updateData([
                "photoURL": photoURL,
                "lastUpdated": FieldValue.serverTimestamp()
            ])
        }
    }

    func updateDisplayName(userId: String, displayName: String) async throws {
        let snapshot = try await db.collection("leaderboard_stats")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        for document in snapshot.documents {
            try await document.reference.updateData([
                "displayName": displayName,
                "lastUpdated": FieldValue.serverTimestamp()
            ])
        }
    }

    func updateBodyWeight(userId: String, weightKg: Double) async throws {
        let snapshot = try await db.collection("leaderboard_stats")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()

        for document in snapshot.documents {
            try await document.reference.updateData([
                "weight_kg": weightKg,
                "lastUpdated": FieldValue.serverTimestamp()
            ])
        }
    }

    private func parseStat(_ data: [String: Any]) -> FirestoreLeaderboardStats? {
        guard let userId = data["userId"] as? String,
              let displayName = data["displayName"] as? String,
              let timeFrame = data["timeFrame"] as? String,
              let periodKey = data["periodKey"] as? String,
              let periodStartAt = timestampValue(for: "periodStartAt", in: data),
              let lastUpdated = timestampValue(for: "lastUpdated", in: data) else {
            return nil
        }

        let schemaVersion = intValue(for: "schemaVersion", in: data) ?? 1
        let totalSteps = intValue(for: "totalSteps", in: data) ?? 0
        let totalFloors = intValue(for: "totalFloors", in: data) ?? 0
        let totalWorkouts = intValue(for: "totalWorkouts", in: data) ?? 0
        let totalDuration = doubleValue(for: "totalDuration", in: data) ?? 0
        let stepsPerMinute = doubleValue(for: "stepsPerMinute", in: data) ?? 0

        guard totalWorkouts > 0 || totalSteps > 0 || totalFloors > 0 || totalDuration > 0 else {
            return nil
        }

        return FirestoreLeaderboardStats(
            userId: userId,
            displayName: displayName,
            photoURL: data["photoURL"] as? String,
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

    private func setOptional(_ value: Any?, for key: String, in data: inout [String: Any]) {
        if let value {
            data[key] = value
        } else {
            data[key] = FieldValue.delete()
        }
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
