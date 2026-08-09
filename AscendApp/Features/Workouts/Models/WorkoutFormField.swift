import Foundation

/// The focusable fields on the edit-climb form.
enum WorkoutFormField: Hashable {
    case workoutName
    case durationHours
    case durationMinutes
    case durationSeconds
    case stepsValue
    case notes
    case caloriesBurned
    case avgHeartRate
    case maxHeartRate
}
