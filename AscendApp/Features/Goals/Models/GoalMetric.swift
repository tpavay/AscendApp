import Foundation

/// Metrics that can be tracked for weekly goals
enum GoalMetric: String, CaseIterable, Codable, Sendable {
    case steps
    case floors
    case duration     // total minutes
    case workouts     // count of workouts

    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .floors: return "Floors"
        case .duration: return "Duration"
        case .workouts: return "Workouts"
        }
    }

    var unit: String {
        switch self {
        case .steps: return "steps"
        case .floors: return "floors"
        case .duration: return "min"
        case .workouts: return "workouts"
        }
    }

    var unitSingular: String {
        switch self {
        case .steps: return "step"
        case .floors: return "floor"
        case .duration: return "min"
        case .workouts: return "workout"
        }
    }

    var icon: String {
        switch self {
        case .steps: return "figure.stairs"
        case .floors: return "building.2"
        case .duration: return "clock"
        case .workouts: return "flame"
        }
    }

    /// Step amount for the stepper control
    var stepAmount: Int {
        switch self {
        case .steps: return 1000
        case .floors: return 25
        case .duration: return 10
        case .workouts: return 1
        }
    }

    /// Default starting value
    var defaultValue: Int {
        switch self {
        case .steps: return 10000
        case .floors: return 100
        case .duration: return 60
        case .workouts: return 3
        }
    }

    /// Minimum value
    var minValue: Int {
        switch self {
        case .steps: return 1000
        case .floors: return 25
        case .duration: return 10
        case .workouts: return 1
        }
    }
}
