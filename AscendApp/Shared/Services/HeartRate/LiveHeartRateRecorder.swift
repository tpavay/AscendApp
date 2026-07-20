import Foundation

/// Session-agnostic live heart-rate sampling for every in-app workout.
///
/// Source priority is explicit so a connected chest strap remains authoritative
/// if an Apple Watch source is added later.
@MainActor
final class LiveHeartRateRecorder {
    private let sources: [any LiveHeartRateSource]
    private let minimumSampleInterval: TimeInterval
    private var samples: [HeartRateDataPoint] = []
    private var lastSampleAt: Date?

    init(
        sources: [any LiveHeartRateSource] = [HeartRateMonitorService.shared],
        minimumSampleInterval: TimeInterval = 0.9
    ) {
        self.sources = sources
        self.minimumSampleInterval = minimumSampleInterval
    }

    var currentSourceKind: LiveHeartRateSourceKind? {
        selectedMeasurement?.sourceKind
    }

    var currentMeasurement: HeartRateMeasurement? {
        selectedMeasurement?.measurement
    }

    var isSourceConnected: Bool {
        sources.contains(where: \.isConnected)
    }

    var workoutSummary: LiveHeartRateWorkoutSummary {
        let heartRates = samples.map(\.heartRate)
        let averageHeartRate = heartRates.isEmpty
            ? nil
            : heartRates.reduce(0, +) / heartRates.count

        return LiveHeartRateWorkoutSummary(
            averageHeartRate: averageHeartRate,
            maximumHeartRate: heartRates.max(),
            timeSeries: samples.isEmpty ? nil : samples
        )
    }

    func prepareForSession() {
        samples.removeAll(keepingCapacity: true)
        lastSampleAt = nil
        sources.forEach { $0.prepareForLiveSession() }
    }

    func recordSample(at now: Date = Date()) {
        guard let measurement = currentMeasurement else { return }
        if let lastSampleAt,
           now.timeIntervalSince(lastSampleAt) < minimumSampleInterval {
            return
        }

        lastSampleAt = now
        samples.append(
            HeartRateDataPoint(timestamp: now, heartRate: measurement.beatsPerMinute)
        )
    }

    private var selectedMeasurement: (
        sourceKind: LiveHeartRateSourceKind,
        measurement: HeartRateMeasurement
    )? {
        var selected: (
            sourceKind: LiveHeartRateSourceKind,
            measurement: HeartRateMeasurement
        )?

        for source in sources {
            guard let measurement = source.freshMeasurement else { continue }
            if let selected,
               selected.sourceKind.selectionPriority >= source.sourceKind.selectionPriority {
                continue
            }
            selected = (source.sourceKind, measurement)
        }

        return selected
    }
}
