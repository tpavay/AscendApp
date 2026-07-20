import Foundation

/// Session-agnostic live heart-rate sampling for every in-app workout.
///
/// Source priority is explicit so a connected chest strap remains authoritative
/// if an Apple Watch source is added later.
@MainActor
final class LiveHeartRateRecorder {
    private let sources: [any LiveHeartRateSource]
    private let minimumSampleInterval: TimeInterval
    private var buffer: HeartRateSessionSampleBuffer

    init(
        sources: [any LiveHeartRateSource] = [HeartRateMonitorService.shared],
        minimumSampleInterval: TimeInterval = 0.9
    ) {
        self.sources = sources
        self.minimumSampleInterval = minimumSampleInterval
        self.buffer = HeartRateSessionSampleBuffer(minimumCaptureInterval: minimumSampleInterval)
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

    var samples: [HeartRateDataPoint] {
        buffer.samples
    }

    var sampleBuffer: HeartRateSessionSampleBuffer {
        buffer
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

    /// Seeds the buffer with a recovered session's series so a resumed session
    /// extends one continuous trace instead of starting a second one.
    func restore(samples: [HeartRateDataPoint]) {
        buffer = HeartRateSessionSampleBuffer(
            restoring: samples,
            minimumCaptureInterval: minimumSampleInterval
        )
    }

    func prepareForSession(restoring samples: [HeartRateDataPoint] = []) {
        restore(samples: samples)
        sources.forEach { $0.prepareForLiveSession() }
    }

    /// `sessionStartedAt` anchors the reading on the session's logical timeline,
    /// so readings after a resume keep extending the pre-interruption series
    /// rather than jumping forward by the interruption's wall-clock gap. Passing
    /// nil means there is no logical timeline yet, and wall clock is used.
    func recordSample(
        at now: Date = Date(),
        sessionStartedAt: Date? = nil,
        sessionElapsed: TimeInterval = 0
    ) {
        guard let measurement = currentMeasurement else { return }

        record(
            measurement,
            capturedAt: now,
            sessionStartedAt: sessionStartedAt,
            sessionElapsed: sessionElapsed
        )
    }

    func record(
        _ measurement: HeartRateMeasurement,
        capturedAt: Date,
        sessionStartedAt: Date? = nil,
        sessionElapsed: TimeInterval = 0
    ) {
        buffer.record(
            beatsPerMinute: measurement.beatsPerMinute,
            capturedAt: capturedAt,
            sessionStartedAt: sessionStartedAt ?? capturedAt,
            sessionElapsed: sessionStartedAt == nil ? 0 : sessionElapsed
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
