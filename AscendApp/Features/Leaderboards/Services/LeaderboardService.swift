//
//  LeaderboardService.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftData

@MainActor
final class LeaderboardService: LeaderboardProfileSyncing {
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
        workouts: [Workout],
        referenceDate: Date = Date()
    ) throws {
        guard let context = modelContext else {
            throw LeaderboardError.notConfigured
        }

        let settings = SettingsManager.shared
        let firstWeekday = settings.weekStartFirstWeekday
        let timeZone = TimeZone.current
        let periodIdentifier = timeFrame.periodIdentifier(
            for: referenceDate,
            firstWeekday: firstWeekday,
            timeZone: timeZone
        )

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
            if timeFrame.shouldReset(
                lastUpdated: existing.lastUpdated,
                referenceDate: referenceDate,
                firstWeekday: firstWeekday,
                timeZone: timeZone
            ) {
                // Reset stats for new period
                stats.periodIdentifier = periodIdentifier
                stats.totalSteps = 0
                stats.totalFloors = 0
                stats.totalWorkouts = 0
                stats.totalDuration = 0
                stats.averageStepsPerMinute = 0
                stats.averageFloorsPerMinute = 0
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
        let startDate = timeFrame.startDate(
            for: referenceDate,
            firstWeekday: firstWeekday,
            timeZone: timeZone
        )
        let relevantWorkouts = workouts.filter { $0.date >= startDate }

        // Update stats
        stats.updateFromWorkouts(relevantWorkouts)

        try context.save()
    }

    // Update all time frames for a user
    func updateAllTimeFrames(for userId: String, workouts: [Workout], referenceDate: Date = Date()) throws {
        for timeFrame in LeaderboardTimeFrame.allCases {
            try updateLeaderboardStats(
                for: userId,
                timeFrame: timeFrame,
                workouts: workouts,
                referenceDate: referenceDate
            )
        }
    }

    // Sync local stats to Firestore - includes both steps and floors
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
            totalFloors: Int,
            totalWorkouts: Int,
            totalDuration: Double,
            averageStepsPerMinute: Double,
            averageFloorsPerMinute: Double,
            lastUpdated: Date
        )] = statsToSync.compactMap { stats in
            // Don't create empty remote leaderboard rows for users with no activity.
            let hasActivity = stats.totalWorkouts > 0 ||
                stats.totalSteps > 0 ||
                stats.totalFloors > 0 ||
                stats.totalDuration > 0 ||
                stats.averageStepsPerMinute > 0 ||
                stats.averageFloorsPerMinute > 0

            guard hasActivity else { return nil }

            return (
                userId: stats.userId,
                displayName: displayName,
                photoURL: photoURL,
                timeFrame: stats.timeFrame,
                periodIdentifier: stats.periodIdentifier,
                totalSteps: stats.totalSteps,
                totalFloors: stats.totalFloors,
                totalWorkouts: stats.totalWorkouts,
                totalDuration: stats.totalDuration,
                averageStepsPerMinute: stats.averageStepsPerMinute,
                averageFloorsPerMinute: stats.averageFloorsPerMinute,
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
                totalFloors: data.totalFloors,
                totalWorkouts: data.totalWorkouts,
                totalDuration: data.totalDuration,
                averageStepsPerMinute: data.averageStepsPerMinute,
                averageFloorsPerMinute: data.averageFloorsPerMinute,
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

        let settings = SettingsManager.shared
        let periodIdentifier = timeFrame.periodIdentifier(
            firstWeekday: settings.weekStartFirstWeekday,
            timeZone: TimeZone.current
        )

        let predicate = #Predicate<LeaderboardStats> { stats in
            stats.userId == userId &&
            stats.timeFrame == timeFrame.rawValue &&
            stats.periodIdentifier == periodIdentifier
        }

        let descriptor = FetchDescriptor<LeaderboardStats>(predicate: predicate)
        return try context.fetch(descriptor).first
    }
    
    // Update profile picture URL across all user's leaderboard documents in Firestore
    func updateProfilePictureURL(userId: String, photoURL: URL?) async throws {
        try await repository.updateProfilePictureURL(
            userId: userId,
            photoURL: photoURL?.absoluteString ?? ""
        )
    }
    
    // Update display name across all user's leaderboard documents in Firestore
    func updateDisplayName(userId: String, displayName: String) async throws {
        try await repository.updateDisplayName(
            userId: userId,
            displayName: displayName
        )
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
