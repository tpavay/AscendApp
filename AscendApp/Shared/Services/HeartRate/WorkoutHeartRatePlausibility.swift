import Foundation

/// The one definition of a usable heart-rate reading, applied where Ascend first writes a sample
/// into its own cache - the live capture buffer and the HealthKit metrics reader. Filtering at
/// ingress keeps the stored series, the stored average, and the stored maximum consistent for the
/// life of the workout, so nothing downstream has to reconcile them. Source records are read-only
/// here: only Ascend's derived copy is filtered.
enum WorkoutHeartRatePlausibility {
    static let maximumBeatsPerMinute = 400

    struct NormalizedSeries {
        let samples: [HeartRateDataPoint]
        let average: Int?
        let maximum: Int?
    }

    static func isPlausible(beatsPerMinute: Int) -> Bool {
        beatsPerMinute > 0 && beatsPerMinute <= maximumBeatsPerMinute
    }

    static func isPlausibleSample(_ sample: HeartRateDataPoint) -> Bool {
        isPlausible(beatsPerMinute: sample.heartRate) &&
            sample.timestamp.timeIntervalSinceReferenceDate.isFinite
    }

    /// Drops out-of-range points and, only when something was actually dropped, recomputes the
    /// summary from what survived. An untouched series keeps the source's own average and maximum,
    /// which stay more faithful than a mean over a sampled series.
    static func normalized(
        samples: [HeartRateDataPoint],
        average: Int?,
        maximum: Int?
    ) -> NormalizedSeries {
        let retainedSamples = samples.filter(isPlausibleSample)
        guard retainedSamples.count != samples.count else {
            return NormalizedSeries(samples: samples, average: average, maximum: maximum)
        }

        AppDiagnosticsRecorder.shared.record(
            "workout_hr_implausible_samples_dropped",
            level: .warning,
            details: [
                "dropped_count": String(samples.count - retainedSamples.count),
                "kept_count": String(retainedSamples.count)
            ]
        )

        guard retainedSamples.isEmpty == false else {
            return NormalizedSeries(samples: [], average: nil, maximum: nil)
        }

        return NormalizedSeries(
            samples: retainedSamples,
            average: averageHeartRate(of: retainedSamples),
            maximum: retainedSamples.map(\.heartRate).max()
        )
    }

    private static func averageHeartRate(of samples: [HeartRateDataPoint]) -> Int {
        let total = samples.reduce(0) { $0 + $1.heartRate }
        return Int((Double(total) / Double(samples.count)).rounded())
    }
}
