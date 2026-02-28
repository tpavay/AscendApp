//
//  ImportCelebrationData.swift
//  AscendApp
//

import Foundation

struct GoalCompletionMessage: Sendable {
    let kicker: String
    let line1: String
    let line2: String
}

struct GoalCompletionMetric: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case workouts
        case duration
        case steps
        case floors
        case verticalClimb
    }

    let kind: Kind
    let iconName: String
    let value: Int
    let label: String

    var id: String { kind.rawValue }
}

struct GoalCompletionContext: Sendable {
    let message: GoalCompletionMessage
    let supportingMetrics: [GoalCompletionMetric]
}

struct GoalCelebrationSnapshot: Sendable {
    let goalId: UUID
    let metric: GoalMetric
    let target: Int
    let weekStartDate: Date
    let weeklyWorkoutCount: Int
    let weeklyDurationMinutes: Int
    let weeklySteps: Int
    let weeklyFloors: Int
    let weeklyVerticalClimb: Int
    let weeklyVerticalClimbUnit: String
    let previousPercent: Double
    let newPercent: Double
    let previousCurrent: Int
    let newCurrent: Int
    let goalCompleted: Bool
    let formattedTarget: String
    let completionContext: GoalCompletionContext
}

/// All data the celebration screens need, captured at import time
struct ImportCelebrationData: Sendable {
    let importedCount: Int
    let failedCount: Int
    let totalDuration: TimeInterval
    let totalSteps: Int
    let totalFloors: Int
    let totalVerticalClimb: Double
    let verticalClimbUnit: String     // "feet" or "meters"
    let goalSnapshot: GoalCelebrationSnapshot?

    var totalCount: Int { importedCount + failedCount }
    var hasPartialFailure: Bool { failedCount > 0 }

    // Future iterations:
    // let leaderboardSnapshot: LeaderboardCelebrationSnapshot?
}
