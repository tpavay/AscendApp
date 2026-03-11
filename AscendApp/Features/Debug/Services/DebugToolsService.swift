//
//  DebugToolsService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftData

#if DEBUG
@MainActor
final class DebugToolsService {
    static let shared = DebugToolsService()
    
    private let leaderboardSeeder = LeaderboardTestDataSeeder()
    private let workoutSeeder = WorkoutTestDataSeeder()
    
    private init() {}
    
    // MARK: - Leaderboard Operations
    
    func seedLeaderboardData() async throws {
        try await leaderboardSeeder.seedTestData()
    }
    
    func clearLeaderboardData() async throws {
        try await leaderboardSeeder.clearTestData()
    }

    // MARK: - Workout Operations

    func seedWorkoutData(
        preset: WorkoutSeedPreset,
        modelContext: ModelContext
    ) async throws -> Int {
        try await workoutSeeder.seedWorkouts(
            preset: preset,
            modelContext: modelContext
        )
    }

    func clearSeededWorkoutData(modelContext: ModelContext) async throws -> Int {
        try workoutSeeder.clearSeededWorkouts(modelContext: modelContext)
    }
    
    // MARK: - Future: Add more debug operations
    // func clearAllData() async throws { }
    // func resetUserPreferences() async throws { }
}
#endif
