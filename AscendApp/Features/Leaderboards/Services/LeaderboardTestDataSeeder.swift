//
//  LeaderboardTestDataSeeder.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

#if DEBUG
@MainActor
final class LeaderboardTestDataSeeder {
    private let db = Firestore.firestore()

    func seedTestData() async throws {
        guard let user = Auth.auth().currentUser else {
            throw LeaderboardSeederError.notAuthenticated
        }

        let userId = user.uid
        let privateDisplayName = user.displayName ?? "Test User"

        debugLog("Seeding leaderboard data for \(privateDisplayName) (\(userId))...")

        for timeFrame in LeaderboardTimeFrame.allCases {
            let period = timeFrame.currentPeriod()
            let stats = generateRandomStats(for: timeFrame)
            let docId = "\(userId)_\(timeFrame.rawValue)"

            let docRef = db.collection("leaderboard_stats").document(docId)

            try await docRef.setData([
                "userId": userId,
                "displayName": PublicClimberIdentity.storedDisplayName,
                "photoURL": PublicClimberIdentity.storedPhotoURL,
                "timeFrame": timeFrame.rawValue,
                "schemaVersion": LeaderboardStats.currentSchemaVersion,
                "periodKey": period.key,
                "periodStartAt": Timestamp(date: period.startAt),
                "totalSteps": stats.totalSteps,
                "totalFloors": stats.totalFloors,
                "totalWorkouts": stats.totalWorkouts,
                "totalDuration": stats.totalDuration,
                "stepsPerMinute": stats.stepsPerMinute,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)
        }

        debugLog("Seeded \(LeaderboardTimeFrame.allCases.count) entries for \(privateDisplayName)")
    }

    func clearTestData() async throws {
        guard let user = Auth.auth().currentUser else {
            throw LeaderboardSeederError.notAuthenticated
        }

        let userId = user.uid
        debugLog("Clearing seeded leaderboard data for \(userId)...")

        for timeFrame in LeaderboardTimeFrame.allCases {
            let docId = "\(userId)_\(timeFrame.rawValue)"
            let docRef = db.collection("leaderboard_stats").document(docId)

            try await docRef.delete()
        }

        debugLog("Cleared seeded data for \(userId)")
    }

    private func generateRandomStats(
        for timeFrame: LeaderboardTimeFrame
    ) -> (totalSteps: Int, totalFloors: Int, totalWorkouts: Int, totalDuration: Double, stepsPerMinute: Double) {

        let multiplier: Double
        switch timeFrame {
        case .daily:
            multiplier = 0.5
        case .weekly:
            multiplier = 1.0
        case .monthly:
            multiplier = 4.0
        case .yearly:
            multiplier = 48.0
        case .allTime:
            multiplier = 100.0
        }

        let baseWorkouts = Int.random(in: 3...7)
        let baseStepsPerWorkout = Int.random(in: 800...2500)
        let baseFloorsPerWorkout = Int.random(in: 10...60)
        let baseDurationPerWorkout = Double.random(in: 15...45) * 60

        let totalWorkouts = Int(Double(baseWorkouts) * multiplier)
        let totalSteps = Int(Double(baseStepsPerWorkout * baseWorkouts) * multiplier)
        let totalFloors = Int(Double(baseFloorsPerWorkout * baseWorkouts) * multiplier)
        let totalDuration = baseDurationPerWorkout * Double(baseWorkouts) * multiplier

        let totalMinutes = totalDuration / 60.0
        let stepsPerMinute = totalMinutes > 0 ? Double(totalSteps) / totalMinutes : 0

        return (totalSteps, totalFloors, totalWorkouts, totalDuration, stepsPerMinute)
    }
}

enum LeaderboardSeederError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to seed leaderboard data."
        }
    }
}
#endif
