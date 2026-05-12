import Foundation

enum WorkoutPlausibilityPolicy {
    static let maximumAverageStepsPerMinute: Double = 220

    static func averageStepsPerMinute(
        steps: Int,
        duration: TimeInterval
    ) -> Double? {
        guard steps > 0, duration > 0 else { return nil }
        return Double(steps) / (duration / 60)
    }

    static func hasPlausibleTotals(
        steps: Int,
        duration: TimeInterval
    ) -> Bool {
        guard steps >= 0, duration > 0 else { return false }
        guard let averageStepsPerMinute = averageStepsPerMinute(
            steps: steps,
            duration: duration
        ) else {
            return true
        }

        return averageStepsPerMinute <= maximumAverageStepsPerMinute
    }

    static func hasPlausibleTotals(_ workout: Workout) -> Bool {
        hasPlausibleTotals(steps: workout.steps, duration: workout.duration)
    }
}
