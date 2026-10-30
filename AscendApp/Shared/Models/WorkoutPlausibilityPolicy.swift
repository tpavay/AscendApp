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

    /// Whether a stored climb's totals are inside the envelope its origin is held to.
    ///
    /// A live climb keeps the 220 steps/min sensor gate. A climb nobody measured is held to the
    /// looser refusal line in `ClimbPacePolicy` instead, because the band between its leaderboard
    /// ceiling and that line is climbs Ascend saves and keeps off the boards: refusing them here
    /// would park a climb the climber was told was saved in `rejected` sync, forever.
    static func hasPlausibleTotals(_ workout: Workout) -> Bool {
        hasPlausibleTotals(
            origin: workout.origin,
            steps: workout.steps,
            duration: workout.duration
        )
    }

    static func hasPlausibleTotals(
        origin: ClimbOrigin,
        steps: Int,
        duration: TimeInterval
    ) -> Bool {
        switch origin {
        case .live:
            return hasPlausibleTotals(steps: steps, duration: duration)
        case .healthImport, .manual:
            guard steps >= 0, duration > 0 else { return false }
            return ClimbPacePolicy.verdict(steps: steps, duration: duration).isSaveable
        }
    }
}
