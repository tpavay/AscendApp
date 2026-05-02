//
//  ImportCelebrationData.swift
//  AscendApp
//

import Foundation

/// All data the celebration screens need, captured at import time
struct ImportCelebrationData: Sendable {
    let importedCount: Int
    let failedCount: Int
    let totalDuration: TimeInterval
    let totalSteps: Int
    let totalFloors: Int
    let totalVerticalClimb: Double
    let verticalClimbUnit: String     // "feet" or "meters"

    var totalCount: Int { importedCount + failedCount }
    var hasPartialFailure: Bool { failedCount > 0 }

    // Future iterations:
    // let leaderboardSnapshot: LeaderboardCelebrationSnapshot?
}
