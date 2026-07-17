import Foundation
@preconcurrency import FirebaseFirestore

final class ProfileRepository: Sendable {
    static let shared = ProfileRepository()

    private let db = Firestore.firestore()

    private init() {}

    func fetchRemoteBundle(userId: String) async throws -> ProfileRemoteBundle {
        async let identity = fetchPublicIdentity(userId: userId)
        async let stats = fetchStats(userId: userId)
        async let achievements = fetchAchievements(userId: userId)
        async let workouts = fetchWorkoutSummaries(userId: userId, limit: 60)

        return try await ProfileRemoteBundle(
            identity: identity,
            stats: stats,
            achievements: achievements,
            workoutSummaries: workouts
        )
    }

    func fetchPublicIdentity(userId: String) async throws -> ProfileUserIdentity? {
        let document = try await publicProfileDocument(userId: userId).getDocument()
        guard let data = document.data() else { return nil }
        return parseIdentity(userId: userId, data: data)
    }

    func fetchStats(userId: String) async throws -> ProfileStatsSnapshot? {
        let document = try await statsDocument(userId: userId).getDocument()
        guard let data = document.data() else { return nil }
        return parseStats(data)
    }

    func fetchAchievements(userId: String) async throws -> [ProfileAchievementRecord] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("achievements")
            .order(by: "earnedAt", descending: true)
            .limit(to: 200)
            .getDocuments()

        return snapshot.documents.compactMap { document in
            parseAchievement(id: document.documentID, data: document.data())
        }
    }

    func fetchWorkoutSummaries(userId: String, limit: Int) async throws -> [ProfileWorkoutSummary] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("profile_workouts")
            .order(by: "startedAt", descending: true)
            .limit(to: max(limit, 0))
            .getDocuments()

        return snapshot.documents.compactMap { document in
            parseWorkoutSummary(id: document.documentID, data: document.data())
        }
    }

    func upsertPublicIdentity(_ identity: ProfileUserIdentity) async throws {
        var data: [String: Any] = [
            "userId": identity.userId,
            "displayName": identity.displayName,
            "photoURL": identity.photoURL?.absoluteString ?? "",
            "lastUpdated": FieldValue.serverTimestamp()
        ]

        if let age = identity.age {
            data["age"] = age
        }
        if let gender = identity.gender {
            data["gender"] = gender.rawValue
        }
        if let weightKg = identity.weightKg {
            data["weight_kg"] = weightKg
        }
        if let heightCm = identity.heightCm {
            data["height_cm"] = heightCm
        }
        if let city = identity.locationCity {
            data["location_city"] = city
        }
        if let country = identity.locationCountryCode {
            data["location_country"] = country.uppercased()
        }
        if let region = identity.locationRegionCode {
            data["location_region"] = region
        }
        if let joinedAt = identity.joinedAt {
            data["joined_at"] = Timestamp(date: joinedAt)
        }

        try await publicProfileDocument(userId: identity.userId).setData(data, merge: true)
    }

    func updatePublicIdentityFields(
        userId: String,
        displayName: String? = nil,
        photoURL: URL? = nil
    ) async throws {
        let document = publicProfileDocument(userId: userId)
        let exists = (try? await document.getDocument().exists) ?? false
        var data: [String: Any] = [
            "userId": userId,
            "lastUpdated": FieldValue.serverTimestamp()
        ]

        if !exists {
            let fallbackDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            data["displayName"] = fallbackDisplayName.isEmpty ? "Climber" : fallbackDisplayName
            data["photoURL"] = photoURL?.absoluteString ?? ""
        }

        if let displayName {
            data["displayName"] = displayName
        }
        if let photoURL {
            data["photoURL"] = photoURL.absoluteString
        }
        try await document.setData(data, merge: true)
    }

    func upsertStats(userId: String, stats: ProfileStatsSnapshot) async throws {
        try await statsDocument(userId: userId).setData([
            "total_climbs_completed": stats.totalClimbsCompleted,
            "total_first_ascents": stats.totalFirstAscents,
            "lifetime_total_steps": stats.lifetimeTotalSteps,
            "lifetime_duration_seconds": stats.lifetimeDurationSeconds,
            "total_climbs": stats.totalClimbs,
            "average_steps_per_minute": stats.averageStepsPerMinute,
            "top_1_finishes": stats.achievementCounts.top1,
            "top_3_finishes": stats.achievementCounts.top3,
            "top_10_finishes": stats.achievementCounts.top10,
            "top_100_finishes": stats.achievementCounts.top100,
            "most_completed_climb_id": stats.mostCompletedClimbId ?? "",
            "current_streak_weeks": stats.currentStreakWeeks,
            "best_streak_weeks": stats.bestStreakWeeks,
            "pr_most_steps": stats.prMostSteps,
            "pr_longest_climb_seconds": stats.prLongestClimbSeconds,
            "pr_highest_spm": stats.prHighestSPM,
            "lastUpdated": FieldValue.serverTimestamp(),
            // Migration: drop the misnamed `_weeks` keys these counts used to live under.
            // Rules validate the merged document with `hasOnly`, so leaving them behind
            // would make every write fail. Remove after 2026-10-01, once published
            // profiles have all been rewritten.
            "top_1_weeks": FieldValue.delete(),
            "top_3_weeks": FieldValue.delete(),
            "top_10_weeks": FieldValue.delete(),
            "top_100_weeks": FieldValue.delete()
        ], merge: true)
    }

    func replaceWorkoutSummaries(userId: String, summaries: [ProfileWorkoutSummary]) async throws {
        let collection = db.collection("users")
            .document(userId)
            .collection("profile_workouts")
        let existing = try await collection.getDocuments()
        let keepIDs = Set(summaries.map(\.id))
        let batch = db.batch()

        for document in existing.documents where !keepIDs.contains(document.documentID) {
            batch.deleteDocument(document.reference)
        }

        for summary in summaries {
            batch.setData(workoutSummaryData(summary), forDocument: collection.document(summary.id), merge: true)
        }

        try await batch.commit()
    }

    private func publicProfileDocument(userId: String) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("public_profile")
            .document("current")
    }

    private func statsDocument(userId: String) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("profile_stats")
            .document("current")
    }

    private func parseIdentity(userId: String, data: [String: Any]) -> ProfileUserIdentity {
        ProfileUserIdentity(
            userId: stringValue(for: "userId", in: data) ?? userId,
            displayName: stringValue(for: "displayName", in: data) ?? "Climber",
            photoURL: stringValue(for: "photoURL", in: data).flatMap(URL.init(string:)),
            age: intValue(for: "age", in: data),
            gender: stringValue(for: "gender", in: data).flatMap(ProfileGender.init(rawValue:)),
            weightKg: doubleValue(for: "weight_kg", in: data),
            heightCm: doubleValue(for: "height_cm", in: data),
            locationCity: stringValue(for: "location_city", in: data),
            locationCountryCode: stringValue(for: "location_country", in: data),
            locationRegionCode: stringValue(for: "location_region", in: data),
            joinedAt: timestampValue(for: "joined_at", in: data)
        )
    }

    private func parseStats(_ data: [String: Any]) -> ProfileStatsSnapshot {
        ProfileStatsSnapshot(
            totalClimbsCompleted: intValue(for: "total_climbs_completed", in: data) ?? 0,
            totalFirstAscents: intValue(for: "total_first_ascents", in: data) ?? 0,
            achievementCounts: ProfileAchievementCounts(
                top1: achievementCountValue(band: "1", in: data),
                top3: achievementCountValue(band: "3", in: data),
                top10: achievementCountValue(band: "10", in: data),
                top100: achievementCountValue(band: "100", in: data)
            ),
            mostCompletedClimbId: nonEmptyStringValue(for: "most_completed_climb_id", in: data),
            currentStreakWeeks: intValue(for: "current_streak_weeks", in: data) ?? 0,
            bestStreakWeeks: intValue(for: "best_streak_weeks", in: data) ?? 0,
            prMostSteps: intValue(for: "pr_most_steps", in: data) ?? 0,
            prLongestClimbSeconds: intValue(for: "pr_longest_climb_seconds", in: data) ?? 0,
            prHighestSPM: doubleValue(for: "pr_highest_spm", in: data) ?? 0,
            lifetimeTotalSteps: intValue(for: "lifetime_total_steps", in: data) ?? 0,
            lifetimeDurationSeconds: intValue(for: "lifetime_duration_seconds", in: data) ?? 0,
            totalClimbs: intValue(for: "total_climbs", in: data) ?? 0,
            averageStepsPerMinute: doubleValue(for: "average_steps_per_minute", in: data) ?? 0
        )
    }

    private func parseAchievement(
        id: String,
        data: [String: Any]
    ) -> ProfileAchievementRecord? {
        guard let typeRawValue = stringValue(for: "type", in: data),
              let type = ProfileAchievementType(rawValue: typeRawValue),
              let earnedAt = timestampValue(for: "earnedAt", in: data) else {
            return nil
        }

        return ProfileAchievementRecord(
            id: id,
            type: type,
            scope: nonEmptyStringValue(for: "scope", in: data)
                .flatMap(ProfileAchievementScope.init(rawValue:)) ??
                (type == .firstAscent ? .climb : .global),
            metric: nonEmptyStringValue(for: "metric", in: data)
                .flatMap(ProfileAchievementMetric.init(rawValue:)),
            climbId: nonEmptyStringValue(for: "climbId", in: data),
            periodKey: nonEmptyStringValue(for: "periodKey", in: data),
            periodStartAt: timestampValue(for: "periodStartAt", in: data),
            periodEndAt: timestampValue(for: "periodEndAt", in: data),
            earnedAt: earnedAt,
            rank: intValue(for: "rank", in: data),
            value: intValue(for: "value", in: data),
            valueUnit: nonEmptyStringValue(for: "valueUnit", in: data)
        )
    }

    private func parseWorkoutSummary(
        id: String,
        data: [String: Any]
    ) -> ProfileWorkoutSummary? {
        guard let name = stringValue(for: "name", in: data),
              let startedAt = timestampValue(for: "startedAt", in: data),
              let sourceRawValue = stringValue(for: "source", in: data),
              let source = WorkoutSource(rawValue: sourceRawValue) else {
            return nil
        }

        return ProfileWorkoutSummary(
            id: id,
            name: name,
            startedAt: startedAt,
            durationSeconds: doubleValue(for: "durationSeconds", in: data) ?? 0,
            steps: intValue(for: "steps", in: data) ?? 0,
            source: source,
            climbId: nonEmptyStringValue(for: "climbId", in: data),
            climbTier: nonEmptyStringValue(for: "climbTier", in: data).flatMap(ClimbTier.init(rawValue:)),
            climbCompletionStatus: nonEmptyStringValue(for: "climbCompletionStatus", in: data).flatMap(ClimbAttemptStatus.init(rawValue:)),
            climbCompletionDurationSeconds: intValue(for: "climbCompletionDurationSeconds", in: data)
        )
    }

    private func workoutSummaryData(_ summary: ProfileWorkoutSummary) -> [String: Any] {
        var data: [String: Any] = [
            "name": summary.name,
            "startedAt": Timestamp(date: summary.startedAt),
            "durationSeconds": summary.durationSeconds,
            "steps": summary.steps,
            "source": summary.source.rawValue,
            "lastUpdated": FieldValue.serverTimestamp()
        ]

        if let climbId = summary.climbId {
            data["climbId"] = climbId
        }
        if let climbTier = summary.climbTier {
            data["climbTier"] = climbTier.rawValue
        }
        if let climbCompletionStatus = summary.climbCompletionStatus {
            data["climbCompletionStatus"] = climbCompletionStatus.rawValue
        }
        if let climbCompletionDurationSeconds = summary.climbCompletionDurationSeconds {
            data["climbCompletionDurationSeconds"] = climbCompletionDurationSeconds
        }

        return data
    }

    private func stringValue(for key: String, in data: [String: Any]) -> String? {
        data[key] as? String
    }

    private func nonEmptyStringValue(for key: String, in data: [String: Any]) -> String? {
        guard let value = stringValue(for: key, in: data)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Reads a band's finish count, falling back to the misnamed `_weeks` key so profiles
    /// published before the rename keep their badges until their next publication rewrites
    /// them. Remove the fallback after 2026-10-01.
    private func achievementCountValue(band: String, in data: [String: Any]) -> Int {
        intValue(for: "top_\(band)_finishes", in: data)
            ?? intValue(for: "top_\(band)_weeks", in: data)
            ?? 0
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
