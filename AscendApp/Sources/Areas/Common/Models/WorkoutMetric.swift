//
//  WorkoutMetric.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import Foundation

enum WorkoutMetric: String, CaseIterable, Identifiable {
    case steps = "steps"
    case floors = "floors"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .floors: return "Floors"
        }
    }
    
    var unit: String {
        switch self {
        case .steps: return "steps"
        case .floors: return "floors"
        }
    }
    
    var description: String {
        switch self {
        case .steps: return "Track individual steps climbed"
        case .floors: return "Track floors or levels climbed"
        }
    }
}