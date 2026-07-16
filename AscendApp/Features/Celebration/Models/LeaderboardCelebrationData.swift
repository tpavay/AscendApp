//
//  LeaderboardCelebrationData.swift
//  AscendApp
//

import Foundation

struct CelebrationLeaderboardEntry: Identifiable, Sendable {
    let id: String
    let rank: Int
    let displayName: String
    let photoURL: String?
    let formattedValue: String
    let isCurrentUser: Bool
}

struct LeaderboardCelebrationSnapshot: Sendable {
    let bestMetric: LeaderboardMetric
    let metricDisplayName: String
    let previousValue: Double
    let newValue: Double
    let formattedPreviousValue: String
    let nearbyEntries: [CelebrationLeaderboardEntry]
}
