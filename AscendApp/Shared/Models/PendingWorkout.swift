//
//  PendingWorkout.swift
//  AscendApp
//
//  Created by Claude Code on 1/16/26.
//

import Foundation
import HealthKit

/// Unified model representing a pending workout from any source (Apple Health or Hevy)
enum PendingWorkout: Identifiable {
    case appleHealth(HKWorkout)
    case hevy(HevyExerciseHistory, matchingAHWorkout: HKWorkout?)

    var id: String {
        // Prefixed to avoid collision between sources
        switch self {
        case .appleHealth(let workout):
            return "ah_\(workout.uuid.uuidString)"
        case .hevy(let exercise, _):
            return "hevy_\(exercise.workout_id)"
        }
    }

    var source: WorkoutSource {
        switch self {
        case .appleHealth:
            return .appleHealth
        case .hevy:
            return .hevy
        }
    }

    var startDate: Date {
        switch self {
        case .appleHealth(let workout):
            return workout.startDate
        case .hevy(let exercise, _):
            return exercise.startDate ?? Date.distantPast
        }
    }

    var duration: TimeInterval {
        switch self {
        case .appleHealth(let workout):
            return workout.duration
        case .hevy(let exercise, _):
            return exercise.duration
        }
    }

    /// Returns the raw source name without auto-link logic
    /// Use displaySourceName(autoLinkEnabled:) for UI display
    var rawSourceName: String {
        switch self {
        case .appleHealth(let workout):
            return workout.sourceRevision.source.name.isEmpty
                ? "Apple Health"  // Fallback if missing
                : workout.sourceRevision.source.name
        case .hevy:
            return "Hevy"
        }
    }

    /// Computed display name - call from view layer with current auto-link setting
    func displaySourceName(autoLinkEnabled: Bool) -> String {
        switch self {
        case .appleHealth(let workout):
            let name = workout.sourceRevision.source.name
            return name.isEmpty ? "Apple Health" : name
        case .hevy(_, let match):
            if autoLinkEnabled, let ahWorkout = match {
                let ahName = ahWorkout.sourceRevision.source.name
                let safeName = ahName.isEmpty ? "Apple Health" : ahName
                return "Hevy + \(safeName)"
            }
            return "Hevy"
        }
    }

    /// The underlying HKWorkout, if this is an Apple Health workout
    var hkWorkout: HKWorkout? {
        switch self {
        case .appleHealth(let workout):
            return workout
        case .hevy:
            return nil
        }
    }

    /// The underlying HevyExerciseHistory, if this is a Hevy workout
    var hevyExercise: HevyExerciseHistory? {
        switch self {
        case .appleHealth:
            return nil
        case .hevy(let exercise, _):
            return exercise
        }
    }

    /// The matching Apple Health workout for a Hevy workout (used for data merging)
    var matchingAppleHealthWorkout: HKWorkout? {
        switch self {
        case .appleHealth:
            return nil
        case .hevy(_, let match):
            return match
        }
    }
}
