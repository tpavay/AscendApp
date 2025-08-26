//
//  Workout.swift
//  AscendApp
//
//  Created by Tyler Pavay on 8/25/25.
//

import Foundation
import SwiftData

@Model
class Workout {
    var id: UUID
    var date: Date
    var duration: TimeInterval // Duration in seconds
    var steps: Int?
    var floors: Int?
    var notes: String
    var createdAt: Date
    
    init(date: Date = Date(), duration: TimeInterval, steps: Int? = nil, floors: Int? = nil, notes: String = "") {
        self.id = UUID()
        self.date = date
        self.duration = duration
        self.steps = steps
        self.floors = floors
        self.notes = notes
        self.createdAt = Date()
    }
    
    // Computed properties for convenience
    var durationFormatted: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    var primaryMetricValue: Int? {
        // Return the non-nil value, preferring steps if both exist
        return steps ?? floors
    }
    
    var metricType: WorkoutMetric {
        if steps != nil {
            return .steps
        } else {
            return .floors
        }
    }
}