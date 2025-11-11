//
//  LeaderboardTestDataSeeder.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
@preconcurrency import FirebaseFirestore

#if DEBUG
@MainActor
final class LeaderboardTestDataSeeder {
    private let db = Firestore.firestore()
    
    // Fake user data for testing
    private let testUsers: [(id: String, name: String)] = [
        ("test_user_1", "Sarah Johnson"),
        ("test_user_2", "Mike Chen"),
        ("test_user_3", "Emma Davis"),
        ("test_user_4", "James Wilson"),
        ("test_user_5", "Olivia Martinez"),
        ("test_user_6", "Noah Brown"),
        ("test_user_7", "Ava Garcia"),
        ("test_user_8", "Liam Anderson"),
        ("test_user_9", "Sophia Taylor"),
        ("test_user_10", "Ethan Moore"),
        ("test_user_11", "Isabella Thomas"),
        ("test_user_12", "Mason Jackson"),
        ("test_user_13", "Mia White"),
        ("test_user_14", "Lucas Harris"),
        ("test_user_15", "Charlotte Clark"),
    ]
    
    func seedTestData() async throws {
        print("🌱 Starting to seed leaderboard test data...")
        
        // Seed for all time frames
        for timeFrame in LeaderboardTimeFrame.allCases {
            try await seedDataForTimeFrame(timeFrame)
        }
        
        print("✅ Successfully seeded test data for all time frames!")
    }
    
    private func seedDataForTimeFrame(_ timeFrame: LeaderboardTimeFrame) async throws {
        let periodIdentifier = timeFrame.periodIdentifier()
        
        print("🌱 Seeding data for \(timeFrame.displayName) (\(periodIdentifier))...")
        
        for user in testUsers {
            // Generate random but realistic stats
            let stats = generateRandomStats(for: user.id, timeFrame: timeFrame)
            
            let docRef = db.collection("leaderboard_stats")
                .document("\(user.id)_\(timeFrame.rawValue)_\(periodIdentifier)")
            
            try await docRef.setData([
                "userId": user.id,
                "displayName": user.name,
                "photoURL": "",
                "timeFrame": timeFrame.rawValue,
                "periodIdentifier": periodIdentifier,
                "totalSteps": stats.totalSteps,
                "totalWorkouts": stats.totalWorkouts,
                "totalDuration": stats.totalDuration,
                "averageStepsPerMinute": stats.averageStepsPerMinute,
                "lastUpdated": FieldValue.serverTimestamp()
            ], merge: true)
        }
        
        print("✅ Seeded \(testUsers.count) users for \(timeFrame.displayName)")
    }
    
    private func generateRandomStats(
        for userId: String,
        timeFrame: LeaderboardTimeFrame
    ) -> (totalSteps: Int, totalWorkouts: Int, totalDuration: Double, averageStepsPerMinute: Double) {
        
        // Different ranges based on time frame
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
        
        // Random but realistic stats
        let baseWorkouts = Int.random(in: 3...7) // Weekly workouts
        let baseStepsPerWorkout = Int.random(in: 800...2500)
        let baseDurationPerWorkout = Double.random(in: 15...45) * 60 // 15-45 minutes in seconds
        
        let totalWorkouts = Int(Double(baseWorkouts) * multiplier)
        let totalSteps = Int(Double(baseStepsPerWorkout * baseWorkouts) * multiplier)
        let totalDuration = Double(baseDurationPerWorkout * Double(baseWorkouts)) * multiplier
        
        // Calculate average steps per minute
        let totalMinutes = totalDuration / 60.0
        let averageStepsPerMinute = totalMinutes > 0 ? Double(totalSteps) / totalMinutes : 0
        
        return (totalSteps, totalWorkouts, totalDuration, averageStepsPerMinute)
    }
    
    // Clean up test data
    func clearTestData() async throws {
        print("🧹 Clearing test data...")
        
        for user in testUsers {
            for timeFrame in LeaderboardTimeFrame.allCases {
                let periodIdentifier = timeFrame.periodIdentifier()
                let docRef = db.collection("leaderboard_stats")
                    .document("\(user.id)_\(timeFrame.rawValue)_\(periodIdentifier)")
                
                try await docRef.delete()
            }
        }
        
        print("✅ Test data cleared!")
    }
}
#endif
