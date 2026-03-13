import Foundation

extension Workout {
    @MainActor
    var intensityTier: IntensityTier {
        if let effortScoreValue {
            return IntensityTier.from(score: effortScoreValue)
        }

        let baseLevel = SettingsManager.shared.effectiveBaseLevel
        let score = WorkoutEffortService.analyze(
            workout: self,
            baseLevel: baseLevel
        ).score
        return IntensityTier.from(score: score)
    }

    /// Steps per minute helper.
    var stepsPerMinute: Double? {
        guard steps > 0, duration > 0 else { return nil }
        return Double(steps) / (duration / 60.0)
    }
}
