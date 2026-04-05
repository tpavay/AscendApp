//
//  LeaderboardMetric.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation

enum LeaderboardMetric: String, CaseIterable, Codable, Identifiable {
    case climb = "climb"
    case workouts = "workouts"
    case duration = "duration"
    case pace = "pace"
    
    var id: String { rawValue }
    
    func displayName(for preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .climb:
            return "Steps"
        case .workouts:
            return "Workouts"
        case .duration:
            return "Duration"
        case .pace:
            return "Steps/Min"
        }
    }
    
    func unit(for preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .climb:
            return WorkoutMetric.steps.unit
        case .workouts:
            return "workouts"
        case .duration:
            return ""
        case .pace:
            return "\(WorkoutMetric.steps.unit)/min"
        }
    }
    
    func icon(for preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .climb:
            return "figure.stairs"
        case .workouts:
            return "flame.fill"
        case .duration:
            return "clock.fill"
        case .pace:
            return "speedometer"
        }
    }
    
    func shortName(for preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .climb:
            return "Steps"
        case .workouts:
            return "Workouts"
        case .duration:
            return "Duration"
        case .pace:
            return "Pace"
        }
    }
    
    // MARK: - Legacy convenience properties (use preference-aware methods when possible)
    
    var displayName: String {
        displayName(for: .steps)
    }
    
    var unit: String {
        unit(for: .steps)
    }
    
    var icon: String {
        icon(for: .steps)
    }
    
    var shortName: String {
        shortName(for: .steps)
    }

    var sortField: String {
        switch self {
        case .climb:
            return "totalSteps"
        case .workouts:
            return "totalWorkouts"
        case .duration:
            return "totalDuration"
        case .pace:
            return "stepsPerMinute"
        }
    }
}
