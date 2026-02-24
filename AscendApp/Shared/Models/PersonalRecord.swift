//
//  PersonalRecord.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/20/25.
//

import Foundation
import SwiftData

/// Represents the type of personal record achieved
enum PersonalRecordType: String, CaseIterable, Codable {
    case mostSteps = "most_steps"
    case mostFloors = "most_floors"
    case longestDuration = "longest_duration"
    case highestAveragePace = "highest_avg_pace" // steps or floors per minute
    case highestVerticalClimb = "highest_vertical_climb"
    case highestAverageHeartRate = "highest_avg_heart_rate"
    case highestMaxHeartRate = "highest_max_heart_rate"
    case mostCaloriesBurned = "most_calories_burned"
    
    var displayName: String {
        switch self {
        case .mostSteps:
            return "Most Steps"
        case .mostFloors:
            return "Most Floors"
        case .longestDuration:
            return "Longest Workout"
        case .highestAveragePace:
            return "Highest Average Pace"
        case .highestVerticalClimb:
            return "Highest Vertical Climb"
        case .highestAverageHeartRate:
            return "Highest Avg Heart Rate"
        case .highestMaxHeartRate:
            return "Highest Max Heart Rate"
        case .mostCaloriesBurned:
            return "Most Calories Burned"
        }
    }
    
    var emoji: String {
        switch self {
        case .mostSteps:
            return "👟"
        case .mostFloors:
            return "🪜"
        case .longestDuration:
            return "⏱️"
        case .highestAveragePace:
            return "⚡"
        case .highestVerticalClimb:
            return "🏔️"
        case .highestAverageHeartRate:
            return "❤️"
        case .highestMaxHeartRate:
            return "💗"
        case .mostCaloriesBurned:
            return "🔥"
        }
    }
}

/// A personal record entry that tracks both current and historical PRs
@Model
class PersonalRecord {
    var id: UUID
    var type: PersonalRecordType
    var value: Double // The record value (steps, duration in seconds, pace, etc.)
    var workoutId: UUID // The workout that achieved this PR
    var achievedAt: Date // When this PR was achieved
    var isCurrent: Bool // Whether this is the current PR (false if it's been beaten)
    var previousRecordId: UUID? // Reference to the previous record that this one beat
    
    // Metadata for display purposes
    var workoutName: String
    var workoutDate: Date
    
    init(
        type: PersonalRecordType,
        value: Double,
        workoutId: UUID,
        achievedAt: Date = Date(),
        isCurrent: Bool = true,
        previousRecordId: UUID? = nil,
        workoutName: String,
        workoutDate: Date
    ) {
        self.id = UUID()
        self.type = type
        self.value = value
        self.workoutId = workoutId
        self.achievedAt = achievedAt
        self.isCurrent = isCurrent
        self.previousRecordId = previousRecordId
        self.workoutName = workoutName
        self.workoutDate = workoutDate
    }
    
    /// Formatted display of the record value
    func formattedValue(measurementSystem: MeasurementSystem) -> String {
        switch type {
        case .mostSteps, .mostFloors:
            return formatInteger(Int(value))
        case .longestDuration:
            return formatDuration(value)
        case .highestAveragePace:
            return "\(value.formatted(.number.precision(.fractionLength(1))))/min"
        case .highestVerticalClimb:
            let unit = measurementSystem.distanceAbbreviation
            return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
        case .highestAverageHeartRate, .highestMaxHeartRate:
            return "\(Int(value)) BPM"
        case .mostCaloriesBurned:
            return "\(Int(value)) cal"
        }
    }
    
    private func formatInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(secs < 10 ? "0" : "")\(secs)"
        } else {
            return "\(minutes):\(secs < 10 ? "0" : "")\(secs)"
        }
    }
}

/// Result of checking for PRs in a workout
struct PersonalRecordResult {
    let type: PersonalRecordType
    let newValue: Double
    let previousValue: Double?
    let previousRecordId: UUID?
    let isNewRecord: Bool
    
    var improvement: Double? {
        guard let prev = previousValue else { return nil }
        return newValue - prev
    }
    
    var improvementPercentage: Double? {
        guard let prev = previousValue, prev > 0 else { return nil }
        return ((newValue - prev) / prev) * 100
    }
}

