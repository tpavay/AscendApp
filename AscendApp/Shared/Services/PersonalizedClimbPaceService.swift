import Foundation

/// Single source of truth for the personalized-else-default climb time estimate.
///
/// Every surface that renders "how long will this climb take me" reads through here:
/// personalized to the user's all-time average pace once they have completed workouts,
/// falling back to the app's existing default pace (`SettingsManager.effectiveBaseLevelSPM`)
/// for a user with none. The all-time average matches `ProfileStatsSnapshot.averageStepsPerMinute`
/// exactly - the same lifetime steps / lifetime minutes definition already shown to users as
/// "Avg SPM" on their own profile - so a climber never sees two different numbers for the same pace.
@MainActor
enum PersonalizedClimbPaceService {
    /// Lifetime average steps-per-minute across completed workouts, or `nil` with no usable history.
    static func allTimeAverageSPM(workouts: [Workout]) -> Double? {
        let totalSteps = workouts.reduce(0) { $0 + $1.steps }
        let totalDurationSeconds = Int(workouts.reduce(0.0) { $0 + $1.duration }.rounded())

        guard totalDurationSeconds > 0, totalSteps > 0 else { return nil }

        return Double(totalSteps) / (Double(totalDurationSeconds) / 60.0)
    }

    /// The SPM to estimate a climb's duration with: the user's all-time average when they
    /// have completed workouts, else the app's existing default pace.
    static func effectiveSPM(workouts: [Workout]) -> Int {
        guard let averageSPM = allTimeAverageSPM(workouts: workouts) else {
            return SettingsManager.shared.effectiveBaseLevelSPM
        }

        return Int(averageSPM.rounded())
    }

    /// Formatted estimated-time text (e.g. "~12 min") for a climb, personalized when possible.
    static func estimatedTimeText(forStepCount stepCount: Int, workouts: [Workout]) -> String {
        ClimbEstimatedTimeFormatter.estimatedTimeText(
            for: stepCount,
            spm: effectiveSPM(workouts: workouts)
        )
    }
}
