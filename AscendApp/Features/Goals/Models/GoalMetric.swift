import Foundation

/// Metrics that can be tracked for weekly goals
enum GoalMetric: String, CaseIterable, Codable {
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
}
