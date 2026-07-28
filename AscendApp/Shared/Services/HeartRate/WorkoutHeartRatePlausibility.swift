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

    /// Drops out-of-range points, then settles the summary. A clean series keeps the source's own
    /// average and maximum, which stay more faithful than a mean over a sampled series - but only
    /// per field, and only while that field is itself in range. The source computes those two
    /// statistics over its parent samples rather than over the series handed here, so one can be an
    /// out-of-range artifact while every charted point is fine.
    static func normalized(
        samples: [HeartRateDataPoint],
        average: Int?,
        maximum: Int?,
        sourceWorkoutId: String? = nil
    ) -> NormalizedSeries {
        let retainedSamples = samples.filter(isPlausibleSample)
        let droppedCount = samples.count - retainedSamples.count

        if droppedCount > 0 {
            record(
                "workout_hr_implausible_samples_dropped",
                sourceWorkoutId: sourceWorkoutId,
                details: [
                    "dropped_count": String(droppedCount),
                    "kept_count": String(retainedSamples.count)
                ]
            )
        }

        guard retainedSamples.isEmpty == false else {
            return NormalizedSeries(samples: [], average: nil, maximum: nil)
        }

        let recomputedAverage = averageHeartRate(of: retainedSamples)
        let recomputedMaximum = retainedSamples.map(\.heartRate).max()

        guard droppedCount == 0 else {
            return NormalizedSeries(
                samples: retainedSamples,
                average: recomputedAverage,
                maximum: recomputedMaximum
            )
        }

        return NormalizedSeries(
            samples: retainedSamples,
            average: usableSummary(
                average,
                replacedBy: recomputedAverage,
                field: "average",
                sourceWorkoutId: sourceWorkoutId
            ),
            maximum: usableSummary(
                maximum,
                replacedBy: recomputedMaximum,
                field: "maximum",
                sourceWorkoutId: sourceWorkoutId
            )
        )
    }

    private static func usableSummary(
        _ value: Int?,
        replacedBy replacement: Int?,
        field: String,
        sourceWorkoutId: String?
    ) -> Int? {
        guard let value else { return nil }
        guard isPlausible(beatsPerMinute: value) == false else { return value }

        record(
            "workout_hr_implausible_summary_replaced",
            sourceWorkoutId: sourceWorkoutId,
            details: ["field": field]
        )
        return replacement
    }

    private static func record(
        _ name: String,
        sourceWorkoutId: String?,
        details: [String: String]
    ) {
        var details = details
        if let sourceWorkoutId {
            details["source_workout_id"] = sourceWorkoutId
        }

        AppDiagnosticsRecorder.shared.record(name, level: .warning, details: details)
    }

    private static func averageHeartRate(of samples: [HeartRateDataPoint]) -> Int {
        let total = samples.reduce(0) { $0 + $1.heartRate }
        return Int((Double(total) / Double(samples.count)).rounded())
    }
}
