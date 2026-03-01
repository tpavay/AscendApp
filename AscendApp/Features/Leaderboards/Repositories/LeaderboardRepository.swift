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
        preferredWorkoutMetric: WorkoutMetric = .steps
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
            preferredWorkoutMetric: preferredWorkoutMetric
        )
    }

    // Fetch leaderboard with explicit period identifier (used when period is pinned at capture time)
    func fetchLeaderboard(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        periodIdentifier: String,
        limit: Int = 100,
        preferredWorkoutMetric: WorkoutMetric = .steps
    ) async throws -> [FirestoreLeaderboardStats] {
        // Query Firestore for the specific time frame and period
        let query = db.collection("leaderboard_stats")
            .whereField("timeFrame", isEqualTo: timeFrame.rawValue)
            .whereField("periodIdentifier", isEqualTo: periodIdentifier)
            .limit(to: limit)

        let snapshot = try await query.getDocuments()

        var stats: [FirestoreLeaderboardStats] = []

        for document in snapshot.documents {
            let data = document.data()

            guard let userId = data["userId"] as? String,
                  let displayName = data["displayName"] as? String,
                  let timeFrame = data["timeFrame"] as? String,
                  let periodIdentifier = data["periodIdentifier"] as? String,
                  let totalSteps = data["totalSteps"] as? Int,
                  let totalWorkouts = data["totalWorkouts"] as? Int,
                  let totalDuration = data["totalDuration"] as? Double,
                  let averageStepsPerMinute = data["averageStepsPerMinute"] as? Double,
                  let timestamp = data["lastUpdated"] as? Timestamp else {
                continue
            }

            let photoURLString = data["photoURL"] as? String
            // Handle missing floors data gracefully (for backwards compatibility)
            let totalFloors = data["totalFloors"] as? Int ?? 0
            let averageFloorsPerMinute = data["averageFloorsPerMinute"] as? Double ?? 0

            let stat = FirestoreLeaderboardStats(
                userId: userId,
                displayName: displayName,
                photoURL: photoURLString,
                timeFrame: timeFrame,
                periodIdentifier: periodIdentifier,
                totalSteps: totalSteps,
                totalFloors: totalFloors,
                totalWorkouts: totalWorkouts,
                totalDuration: totalDuration,
                averageStepsPerMinute: averageStepsPerMinute,
                averageFloorsPerMinute: averageFloorsPerMinute,
                lastUpdated: timestamp.dateValue()
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

        return stats
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
}
