//
//  ImportCelebrationData.swift
//  AscendApp
//

import Foundation

struct GoalCelebrationSnapshot: Sendable {
    let goalId: UUID
    let metric: GoalMetric
    let target: Int
    let previousPercent: Double
    let newPercent: Double
    let previousCurrent: Int
    let newCurrent: Int
    let goalCompleted: Bool
    let formattedTarget: String
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
