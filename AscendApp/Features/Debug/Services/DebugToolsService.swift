//
//  DebugToolsService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation

#if DEBUG
@MainActor
final class DebugToolsService {
    static let shared = DebugToolsService()
    
    private let leaderboardSeeder = LeaderboardTestDataSeeder()
    
    private init() {}
    
    // MARK: - Leaderboard Operations
    
    func seedLeaderboardData() async throws {
        try await leaderboardSeeder.seedTestData()
    }
    
    func clearLeaderboardData() async throws {
        try await leaderboardSeeder.clearTestData()
    }
    
    // MARK: - Future: Add more debug operations
    // func seedWorkoutData() async throws { }
    // func clearAllData() async throws { }
    // func resetUserPreferences() async throws { }
}
#endif
