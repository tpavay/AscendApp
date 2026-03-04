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
        let displayName = user.displayName ?? "Test User"
        let photoURL = user.photoURL?.absoluteString ?? ""

        print("Seeding leaderboard data for \(displayName) (\(userId))...")

        for timeFrame in LeaderboardTimeFrame.allCases {
            let period = timeFrame.periodIdentifier()
            let stats = generateRandomStats(for: timeFrame)
            let docId = "\(userId)_\(timeFrame.rawValue)_\(period)"

            let docRef = db.collection("leaderboard_stats").document(docId)

            try await docRef.setData([
                "userId": userId,
                "displayName": displayName,
                "photoURL": photoURL,
                "timeFrame": timeFrame.rawValue,
                "periodIdentifier": period,
                "totalSteps": stats.totalSteps,
                "totalFloors": stats.totalFloors,
                "totalWorkouts": stats.totalWorkouts,
                "totalDuration": stats.totalDuration,
                "averageStepsPerMinute": stats.averageStepsPerMinute,
                "averageFloorsPerMinute": stats.averageFloorsPerMinute,
                "lastUpdated": FieldValue.serverTimestamp(),
                "isTestData": true,
                "seedSource": "debug-tools",
                "seededAt": FieldValue.serverTimestamp()
            ], merge: true)
        }

        print("Seeded \(LeaderboardTimeFrame.allCases.count) entries for \(displayName)")
    }

    func clearTestData() async throws {
        guard let user = Auth.auth().currentUser else {
            throw LeaderboardSeederError.notAuthenticated
        }

        let userId = user.uid
        print("Clearing seeded leaderboard data for \(userId)...")

        for timeFrame in LeaderboardTimeFrame.allCases {
            let period = timeFrame.periodIdentifier()
            let docId = "\(userId)_\(timeFrame.rawValue)_\(period)"
            let docRef = db.collection("leaderboard_stats").document(docId)

            try await docRef.delete()
        }

        print("Cleared seeded data for \(userId)")
    }

    private func generateRandomStats(
        for timeFrame: LeaderboardTimeFrame
    ) -> (totalSteps: Int, totalFloors: Int, totalWorkouts: Int, totalDuration: Double, averageStepsPerMinute: Double, averageFloorsPerMinute: Double) {

        let multiplier: Double
        switch timeFrame {
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
        let averageStepsPerMinute = totalMinutes > 0 ? Double(totalSteps) / totalMinutes : 0
        let averageFloorsPerMinute = totalMinutes > 0 ? Double(totalFloors) / totalMinutes : 0

        return (totalSteps, totalFloors, totalWorkouts, totalDuration, averageStepsPerMinute, averageFloorsPerMinute)
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
