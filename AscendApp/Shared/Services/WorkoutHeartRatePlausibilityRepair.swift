import Foundation

/// Ascend's stored heart-rate series is a derived cache of samples it was handed, so an
/// implausible reading is repaired in place once rather than filtered on every upload. The
/// persisted average and maximum are recomputed from the retained points so the summary a device
/// shows - and the one a clean device restores - always agrees with the charted series. HealthKit's
/// own records are never touched.
enum WorkoutHeartRatePlausibilityRepair {
    @discardableResult
    static func repairIfNeeded(_ workout: Workout) -> Bool {
        let samples = workout.heartRateTimeSeries
        guard samples.isEmpty == false else { return false }

        let retainedSamples = samples.filter(WorkoutHeartRateSidecarValidator.isPlausibleSample)
        guard retainedSamples.count != samples.count else { return false }

        if retainedSamples.isEmpty {
            workout.heartRateData = nil
            workout.avgHeartRate = nil
            workout.maxHeartRate = nil
        } else {
            guard let encodedSamples = retainedSamples.encoded else { return false }
            workout.heartRateData = encodedSamples
            workout.avgHeartRate = averageHeartRate(of: retainedSamples)
            workout.maxHeartRate = retainedSamples.map(\.heartRate).max()
        }

        AppDiagnosticsRecorder.shared.record(
            "workout_hr_implausible_samples_dropped",
            level: .warning,
            details: [
                "workout_id": workout.id.uuidString,
                "dropped_count": String(samples.count - retainedSamples.count),
                "kept_count": String(retainedSamples.count)
            ]
        )

        return true
    }

    private static func averageHeartRate(of samples: [HeartRateDataPoint]) -> Int {
        let total = samples.reduce(0) { $0 + $1.heartRate }
        return Int((Double(total) / Double(samples.count)).rounded())
    }
}
