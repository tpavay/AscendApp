//
//  LeaderboardEntry.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation

struct LeaderboardEntry: Identifiable, Equatable {
    let id: String // userId
    let userId: String
    let displayName: String
    let photoURL: URL?
    let rank: Int
    let value: Double
    let formattedValue: String
    let isCurrentUser: Bool

    init(
        userId: String,
        displayName: String,
        photoURL: URL? = nil,
        rank: Int,
        value: Double,
        formattedValue: String,
        isCurrentUser: Bool = false
    ) {
        self.id = userId
        self.userId = userId
        self.displayName = displayName
        self.photoURL = photoURL
        self.rank = rank
        self.value = value
        self.formattedValue = formattedValue
        self.isCurrentUser = isCurrentUser
    }

    static func == (lhs: LeaderboardEntry, rhs: LeaderboardEntry) -> Bool {
        lhs.id == rhs.id && lhs.rank == rhs.rank && lhs.value == rhs.value
    }
}

// Firestore representation
struct FirestoreLeaderboardStats: Codable {
    let userId: String
    let displayName: String
    let photoURL: String?
    let timeFrame: String
    let periodIdentifier: String
    let totalSteps: Int
    let totalWorkouts: Int
    let totalDuration: Double
    let averageStepsPerMinute: Double
    let lastUpdated: Date

    // Initializer for converting from local LeaderboardStats to upload to Firestore
    init(from stats: LeaderboardStats, displayName: String, photoURL: URL?) {
        self.userId = stats.userId
        self.displayName = displayName
        self.photoURL = photoURL?.absoluteString
        self.timeFrame = stats.timeFrame
        self.periodIdentifier = stats.periodIdentifier
        self.totalSteps = stats.totalSteps
        self.totalWorkouts = stats.totalWorkouts
        self.totalDuration = stats.totalDuration
        self.averageStepsPerMinute = stats.averageStepsPerMinute
        self.lastUpdated = stats.lastUpdated
    }

    // Initializer for creating from Firestore data
    init(
        userId: String,
        displayName: String,
        photoURL: String?,
        timeFrame: String,
        periodIdentifier: String,
        totalSteps: Int,
        totalWorkouts: Int,
        totalDuration: Double,
        averageStepsPerMinute: Double,
        lastUpdated: Date
    ) {
        self.userId = userId
        self.displayName = displayName
        self.photoURL = photoURL
        self.timeFrame = timeFrame
        self.periodIdentifier = periodIdentifier
        self.totalSteps = totalSteps
        self.totalWorkouts = totalWorkouts
        self.totalDuration = totalDuration
        self.averageStepsPerMinute = averageStepsPerMinute
        self.lastUpdated = lastUpdated
    }

    func value(for metric: LeaderboardMetric) -> Double {
        switch metric {
        case .steps:
            return Double(totalSteps)
        case .workouts:
            return Double(totalWorkouts)
        case .duration:
            return totalDuration
        case .stepsPerMinute:
            return averageStepsPerMinute
        }
    }
}
