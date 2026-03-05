//
//  LeaderboardRepository.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
@preconcurrency import FirebaseFirestore

final class LeaderboardRepository: Sendable {
    static let shared = LeaderboardRepository()
    private let db = Firestore.firestore()

    private init() {}

    // Sync stats to Firestore - accepts Sendable primitives only
    func syncStatsToFirestore(
        userId: String,
        displayName: String,
        photoURL: URL?,
        timeFrame: String,
        periodIdentifier: String,
        totalSteps: Int,
        totalFloors: Int,
        totalWorkouts: Int,
        totalDuration: Double,
        averageStepsPerMinute: Double,
        averageFloorsPerMinute: Double,
        lastUpdated: Date
    ) async throws {
        let docRef = db.collection("leaderboard_stats")
            .document("\(userId)_\(timeFrame)_\(periodIdentifier)")

        try await docRef.setData([
            "userId": userId,
            "displayName": displayName,
            "photoURL": photoURL?.absoluteString ?? "",
            "timeFrame": timeFrame,
            "periodIdentifier": periodIdentifier,
            "totalSteps": totalSteps,
            "totalFloors": totalFloors,
            "totalWorkouts": totalWorkouts,
            "totalDuration": totalDuration,
            "averageStepsPerMinute": averageStepsPerMinute,
            "averageFloorsPerMinute": averageFloorsPerMinute,
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // Fetch leaderboard for a specific metric and time frame
    func fetchLeaderboard(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        limit: Int = 100,
        preferredWorkoutMetric: WorkoutMetric = .steps,
        source: FirestoreSource = .default
    ) async throws -> [FirestoreLeaderboardStats] {
        let (firstWeekday, timeZone): (Int, TimeZone) = await MainActor.run {
            (SettingsManager.shared.weekStartFirstWeekday, TimeZone.current)
        }
        let periodIdentifier = timeFrame.periodIdentifier(
            firstWeekday: firstWeekday,
            timeZone: timeZone
        )
        return try await fetchLeaderboard(
            metric: metric,
            timeFrame: timeFrame,
            periodIdentifier: periodIdentifier,
            limit: limit,
            preferredWorkoutMetric: preferredWorkoutMetric,
            source: source
        )
    }

    // Fetch leaderboard with explicit period identifier (used when period is pinned at capture time)
    func fetchLeaderboard(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        periodIdentifier: String,
        limit: Int = 100,
        preferredWorkoutMetric: WorkoutMetric = .steps,
        source: FirestoreSource = .default
    ) async throws -> [FirestoreLeaderboardStats] {
        // Query Firestore for the specific time frame and period
        let query = db.collection("leaderboard_stats")
            .whereField("timeFrame", isEqualTo: timeFrame.rawValue)
            .whereField("periodIdentifier", isEqualTo: periodIdentifier)

        let snapshot = try await query.getDocuments(source: source)

        var stats: [FirestoreLeaderboardStats] = []

        for document in snapshot.documents {
            let data = document.data()

            guard let userId = stringValue(for: "userId", in: data),
                  let displayName = stringValue(for: "displayName", in: data),
                  let timeFrameValue = stringValue(for: "timeFrame", in: data),
                  let periodIdentifierValue = stringValue(for: "periodIdentifier", in: data) else {
                continue
            }

            let photoURLString = data["photoURL"] as? String
            // Handle older or partially populated documents gracefully.
            let totalSteps = intValue(for: "totalSteps", in: data) ?? 0
            let totalWorkouts = intValue(for: "totalWorkouts", in: data) ?? 0
            let totalDuration = doubleValue(for: "totalDuration", in: data) ?? 0
            let averageStepsPerMinute = doubleValue(for: "averageStepsPerMinute", in: data) ?? 0
            let totalFloors = intValue(for: "totalFloors", in: data) ?? 0
            let averageFloorsPerMinute = doubleValue(for: "averageFloorsPerMinute", in: data) ?? 0
            let lastUpdated = timestampValue(for: "lastUpdated", in: data) ?? .distantPast
            let hasActivity = totalWorkouts > 0 ||
                totalSteps > 0 ||
                totalFloors > 0 ||
                totalDuration > 0 ||
                averageStepsPerMinute > 0 ||
                averageFloorsPerMinute > 0

            // Filter legacy seeded documents that contain only zeros.
            guard hasActivity else { continue }

            let stat = FirestoreLeaderboardStats(
                userId: userId,
                displayName: displayName,
                photoURL: photoURLString,
                timeFrame: timeFrameValue,
                periodIdentifier: periodIdentifierValue,
                totalSteps: totalSteps,
                totalFloors: totalFloors,
                totalWorkouts: totalWorkouts,
                totalDuration: totalDuration,
                averageStepsPerMinute: averageStepsPerMinute,
                averageFloorsPerMinute: averageFloorsPerMinute,
                lastUpdated: lastUpdated
            )

            stats.append(stat)
        }

        // Sort by requested metric with deterministic tie-breaking.
        stats.sort {
            let lhs = $0.value(for: metric, preferredWorkoutMetric: preferredWorkoutMetric)
            let rhs = $1.value(for: metric, preferredWorkoutMetric: preferredWorkoutMetric)
            if lhs != rhs { return lhs > rhs }
            return $0.userId < $1.userId
        }

        let effectiveLimit = max(limit, 0)
        guard effectiveLimit > 0 else { return [] }
        return Array(stats.prefix(effectiveLimit))
    }

    // Get user's rank for a specific metric and time frame
    func getUserRank(
        userId: String,
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        preferredWorkoutMetric: WorkoutMetric = .steps
    ) async throws -> (rank: Int, total: Int)? {
        let allStats = try await fetchLeaderboard(
            metric: metric,
            timeFrame: timeFrame,
            limit: 1000,
            preferredWorkoutMetric: preferredWorkoutMetric
        )

        guard let userIndex = allStats.firstIndex(where: { $0.userId == userId }) else {
            return nil
        }

        return (rank: userIndex + 1, total: allStats.count)
    }
    
    // Update profile picture URL across all user's leaderboard documents
    func updateProfilePictureURL(userId: String, photoURL: String) async throws {
        // Query all documents for this user
        let query = db.collection("leaderboard_stats")
            .whereField("userId", isEqualTo: userId)
        
        let snapshot = try await query.getDocuments()
        
        // Update each document
        for document in snapshot.documents {
            try await document.reference.updateData([
                "photoURL": photoURL,
                "lastUpdated": FieldValue.serverTimestamp()
            ])
        }
    }
    
    // Update display name across all user's leaderboard documents
    func updateDisplayName(userId: String, displayName: String) async throws {
        // Query all documents for this user
        let query = db.collection("leaderboard_stats")
            .whereField("userId", isEqualTo: userId)
        
        let snapshot = try await query.getDocuments()
        
        // Update each document
        for document in snapshot.documents {
            try await document.reference.updateData([
                "displayName": displayName,
                "lastUpdated": FieldValue.serverTimestamp()
            ])
        }
    }

    private func stringValue(for key: String, in data: [String: Any]) -> String? {
        data[key] as? String
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
