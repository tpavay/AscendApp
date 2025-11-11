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
        totalWorkouts: Int,
        totalDuration: Double,
        averageStepsPerMinute: Double,
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
            "totalWorkouts": totalWorkouts,
            "totalDuration": totalDuration,
            "averageStepsPerMinute": averageStepsPerMinute,
            "lastUpdated": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // Fetch leaderboard for a specific metric and time frame
    func fetchLeaderboard(
        metric: LeaderboardMetric,
        timeFrame: LeaderboardTimeFrame,
        limit: Int = 100
    ) async throws -> [FirestoreLeaderboardStats] {
        let periodIdentifier = timeFrame.periodIdentifier()

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

            let stat = FirestoreLeaderboardStats(
                userId: userId,
                displayName: displayName,
                photoURL: photoURLString,
                timeFrame: timeFrame,
                periodIdentifier: periodIdentifier,
                totalSteps: totalSteps,
                totalWorkouts: totalWorkouts,
                totalDuration: totalDuration,
                averageStepsPerMinute: averageStepsPerMinute,
                lastUpdated: timestamp.dateValue()
            )

            stats.append(stat)
        }

        // Sort by the requested metric
        stats.sort { $0.value(for: metric) > $1.value(for: metric) }

        return stats
    }

    // Get user's rank for a specific metric and time frame
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

        guard let userIndex = allStats.firstIndex(where: { $0.userId == userId }) else {
            return nil
        }

        return (rank: userIndex + 1, total: allStats.count)
    }
}
