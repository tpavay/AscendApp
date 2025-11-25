//
//  LeaderboardMetric.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/3/25.
//

import Foundation

enum LeaderboardMetric: String, CaseIterable, Codable, Identifiable {
    case climb = "climb"  // Shows steps or floors based on user preference
    case workouts = "workouts"
    case duration = "duration"
    case pace = "pace"  // Shows steps/min or floors/min based on user preference
    
    var id: String { rawValue }
    
    /// Display name based on user's preferred workout metric
    func displayName(for preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .climb:
            return preferredMetric.displayName
        case .workouts:
            return "Workouts"
        case .duration:
            return "Duration"
        case .pace:
            return "\(preferredMetric.displayName)/Min"
        }
    }
    
    /// Unit label based on user's preferred workout metric
    func unit(for preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .climb:
            return preferredMetric.unit
        case .workouts:
            return "workouts"
        case .duration:
            return ""
        case .pace:
            return "\(preferredMetric.unit)/min"
        }
    }
    
    /// Icon for this metric
    func icon(for preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .climb:
            return preferredMetric == .steps ? "figure.stairs" : "building.2"
        case .workouts:
            return "flame.fill"
        case .duration:
            return "clock.fill"
        case .pace:
            return "speedometer"
        }
    }
    
    /// Short name based on user's preferred workout metric
    func shortName(for preferredMetric: WorkoutMetric) -> String {
        switch self {
        case .climb:
            return preferredMetric.displayName
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
}
