//
//  LeaderboardService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftData

@MainActor
final class LeaderboardService {
    static let shared = LeaderboardService()

    private let repository = LeaderboardRepository.shared
    private var modelContext: ModelContext?

    private init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Update local leaderboard stats from workouts
    func updateLeaderboardStats(
        for userId: String,
        timeFrame: LeaderboardTimeFrame,
        workouts: [Workout]
    ) throws {
        guard let context = modelContext else {
            throw LeaderboardError.notConfigured
        }

        let periodIdentifier = timeFrame.periodIdentifier()

        // Fetch or create stats for this period
        let predicate = #Predicate<LeaderboardStats> { stats in
            stats.userId == userId &&
            stats.timeFrame == timeFrame.rawValue &&
            stats.periodIdentifier == periodIdentifier
        }

        let descriptor = FetchDescriptor<LeaderboardStats>(predicate: predicate)
        let existingStats = try context.fetch(descriptor)

        let stats: LeaderboardStats
        if let existing = existingStats.first {
            stats = existing

            // Check if we need to reset for new period
            if timeFrame.shouldReset(lastUpdated: existing.lastUpdated) {
                // Reset stats for new period
                stats.periodIdentifier = periodIdentifier
                stats.totalSteps = 0
                stats.totalWorkouts = 0
                stats.totalDuration = 0
                stats.averageStepsPerMinute = 0
            }
        } else {
            stats = LeaderboardStats(
                userId: userId,
                timeFrame: timeFrame,
                periodIdentifier: periodIdentifier
            )
            context.insert(stats)
        }

        // Filter workouts for this time frame
        let startDate = timeFrame.startDate()
        let relevantWorkouts = workouts.filter { $0.date >= startDate }

        // Update stats
        stats.updateFromWorkouts(relevantWorkouts)

        try context.save()
    }

    // Update all time frames for a user
    func updateAllTimeFrames(for userId: String, workouts: [Workout]) throws {
        for timeFrame in LeaderboardTimeFrame.allCases {
            try updateLeaderboardStats(
                for: userId,
                timeFrame: timeFrame,
                workouts: workouts
            )
        }
    }

    // Sync local stats to Firestore - FIXED VERSION
    func syncToFirestore(
        userId: String,
        displayName: String,
        photoURL: URL?
    ) async throws {
        guard let context = modelContext else {
            throw LeaderboardError.notConfigured
        }

        // Fetch all stats that need syncing
        let predicate = #Predicate<LeaderboardStats> { stats in
            stats.userId == userId && stats.needsSync
        }

        let descriptor = FetchDescriptor<LeaderboardStats>(predicate: predicate)
        let statsToSync = try context.fetch(descriptor)

        // Extract Sendable data from each stat (on MainActor)
        let dataToSync: [(
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
        )] = statsToSync.map { stats in
            (
                userId: stats.userId,
                displayName: displayName,
                photoURL: photoURL,
                timeFrame: stats.timeFrame,
                periodIdentifier: stats.periodIdentifier,
                totalSteps: stats.totalSteps,
                totalWorkouts: stats.totalWorkouts,
                totalDuration: stats.totalDuration,
                averageStepsPerMinute: stats.averageStepsPerMinute,
                lastUpdated: stats.lastUpdated
            )
        }

        // Sync each stat to Firestore using Sendable data
        for data in dataToSync {
            try await repository.syncStatsToFirestore(
                userId: data.userId,
                displayName: data.displayName,
                photoURL: data.photoURL,
                timeFrame: data.timeFrame,
                periodIdentifier: data.periodIdentifier,
                totalSteps: data.totalSteps,
                totalWorkouts: data.totalWorkouts,
                totalDuration: data.totalDuration,
                averageStepsPerMinute: data.averageStepsPerMinute,
                lastUpdated: data.lastUpdated
            )
        }

        // Mark all as synced (back on MainActor)
        for stats in statsToSync {
            stats.lastSyncedToFirestore = Date()
            stats.needsSync = false
        }

        try context.save()
    }

    // Fetch user's local stats
    func getLocalStats(
        for userId: String,
        timeFrame: LeaderboardTimeFrame
    ) throws -> LeaderboardStats? {
        guard let context = modelContext else {
            throw LeaderboardError.notConfigured
        }

        let periodIdentifier = timeFrame.periodIdentifier()

        let predicate = #Predicate<LeaderboardStats> { stats in
            stats.userId == userId &&
            stats.timeFrame == timeFrame.rawValue &&
            stats.periodIdentifier == periodIdentifier
        }

        let descriptor = FetchDescriptor<LeaderboardStats>(predicate: predicate)
        return try context.fetch(descriptor).first
    }
}

enum LeaderboardError: LocalizedError {
    case notConfigured
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Leaderboard service not configured with model context"
        case .syncFailed:
            return "Failed to sync leaderboard data"
        }
    }
}
