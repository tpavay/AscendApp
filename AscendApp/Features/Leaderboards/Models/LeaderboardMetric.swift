//
//  LeaderboardMetric.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation

enum LeaderboardMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case climb = "climb"
    case workouts = "workouts"
    case duration = "duration"
    case pace = "pace"
    
    var id: String { rawValue }
    
    var displayName: String {
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
    
    var unit: String {
        switch self {
        case .climb:
            return "steps"
        case .workouts:
            return "workouts"
        case .duration:
            return ""
        case .pace:
            return "steps/min"
        }
    }
    
    var icon: String {
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
    
    var shortName: String {
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
