//
//  LeaderboardMetric.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation

enum LeaderboardMetric: String, CaseIterable, Codable, Identifiable {
    case steps = "steps"
    case workouts = "workouts"
    case duration = "duration"
    case stepsPerMinute = "steps_per_minute"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .steps:
            return "Steps"
        case .workouts:
            return "Workouts"
        case .duration:
            return "Duration"
        case .stepsPerMinute:
            return "Steps/Min"
        }
    }
    
    var unit: String {
        switch self {
        case .steps:
            return "steps"
        case .workouts:
            return "workouts"
        case .duration:
            return ""
        case .stepsPerMinute:
            return "steps/min"
        }
    }
    
    var icon: String {
        switch self {
        case .steps:
            return "figure.stairs"
        case .workouts:
            return "flame.fill"
        case .duration:
            return "clock.fill"
        case .stepsPerMinute:
            return "speedometer"
        }
    }
    
    var shortName: String {
        switch self {
        case .steps:
            return "Steps"
        case .workouts:
            return "Workouts"
        case .duration:
            return "Time"
        case .stepsPerMinute:
            return "Pace"
        }
    }
}
