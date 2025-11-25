//
//  LeaderboardStats.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation
import SwiftData

@Model
class LeaderboardStats {
    var id: UUID
    var userId: String
    var timeFrame: String // LeaderboardTimeFrame rawValue
    var periodIdentifier: String // e.g., "2025-W40" for week 40

    // Aggregated metrics - track both steps and floors
    var totalSteps: Int
    var totalFloors: Int
    var totalWorkouts: Int
    var totalDuration: TimeInterval
    var averageStepsPerMinute: Double
    var averageFloorsPerMinute: Double

    // Metadata
    var lastUpdated: Date
    var lastSyncedToFirestore: Date?
    var needsSync: Bool

    init(
        userId: String,
        timeFrame: LeaderboardTimeFrame,
        periodIdentifier: String,
        totalSteps: Int = 0,
        totalFloors: Int = 0,
        totalWorkouts: Int = 0,
        totalDuration: TimeInterval = 0,
        averageStepsPerMinute: Double = 0,
        averageFloorsPerMinute: Double = 0
    ) {
        self.id = UUID()
        self.userId = userId
        self.timeFrame = timeFrame.rawValue
        self.periodIdentifier = periodIdentifier
        self.totalSteps = totalSteps
        self.totalFloors = totalFloors
        self.totalWorkouts = totalWorkouts
        self.totalDuration = totalDuration
        self.averageStepsPerMinute = averageStepsPerMinute
        self.averageFloorsPerMinute = averageFloorsPerMinute
        self.lastUpdated = Date()
        self.lastSyncedToFirestore = nil
        self.needsSync = true
    }

    // Computed property for easy access
    var timeFrameEnum: LeaderboardTimeFrame {
        LeaderboardTimeFrame(rawValue: timeFrame) ?? .allTime
    }

    // Update stats from workouts
    func updateFromWorkouts(_ workouts: [Workout]) {
        totalSteps = workouts.map { $0.steps }.reduce(0, +)
        totalFloors = workouts.map { $0.floors }.reduce(0, +)
        totalWorkouts = workouts.count
        totalDuration = workouts.map { $0.duration }.reduce(0, +)

        // Calculate average per minute across all workouts
        let totalMinutes = totalDuration / 60.0
        averageStepsPerMinute = totalMinutes > 0 ? Double(totalSteps) / totalMinutes : 0
        averageFloorsPerMinute = totalMinutes > 0 ? Double(totalFloors) / totalMinutes : 0

        lastUpdated = Date()
        needsSync = true
    }

    // Get value for specific metric, respecting user's preferred workout metric
    func value(for metric: LeaderboardMetric, preferredWorkoutMetric: WorkoutMetric = .steps) -> Double {
        switch metric {
        case .climb:
            return preferredWorkoutMetric == .steps ? Double(totalSteps) : Double(totalFloors)
        case .workouts:
            return Double(totalWorkouts)
        case .duration:
            return totalDuration
        case .pace:
            return preferredWorkoutMetric == .steps ? averageStepsPerMinute : averageFloorsPerMinute
        }
    }

    // Format value for display
    func formattedValue(for metric: LeaderboardMetric, preferredWorkoutMetric: WorkoutMetric = .steps) -> String {
        let value = value(for: metric, preferredWorkoutMetric: preferredWorkoutMetric)

        switch metric {
        case .climb, .workouts:
            return String(format: "%.0f", value)
        case .duration:
            return formatDuration(value)
        case .pace:
            return String(format: "%.1f", value)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
