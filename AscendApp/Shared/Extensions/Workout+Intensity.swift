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

}
