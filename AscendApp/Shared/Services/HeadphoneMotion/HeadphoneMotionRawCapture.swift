import Foundation

/// One raw headphone-motion sample as fed to `HeadphoneMotionStepDetector` - the exact input the
/// algorithm consumed. The detector's vertical-acceleration projection is deliberately not stored:
/// replay recomputes it with `HeadphoneMotionStepDetector.verticalAcceleration(from:)` from the
/// retained `userAcceleration` and `gravity`, so storing it would only duplicate data.
///
/// Values are quantized before they are kept - the timestamp to the millisecond, every vector
/// component to `vectorDecimalPlaces` - because full-precision `Double` text is mostly sensor
/// noise gzip cannot compress, and that noise is what pushed a full capture past the upload cap.
/// Both resolutions sit well below the sensor's own noise floor and the 50Hz sample spacing.
struct HeadphoneMotionRawCaptureSample: Codable, Equatable, Sendable {
    static let timestampDecimalPlaces = 3
    static let vectorDecimalPlaces = 4

    let timestamp: TimeInterval
    let userAcceleration: HeadphoneMotionVector
    let rotationRate: HeadphoneMotionVector
    let gravity: HeadphoneMotionVector

    init(sample: HeadphoneMotionSample) {
        timestamp = sample.timestamp.quantized(toDecimalPlaces: Self.timestampDecimalPlaces)
        userAcceleration = Self.quantized(sample.userAcceleration)
        rotationRate = Self.quantized(sample.rotationRate)
        gravity = Self.quantized(sample.gravity)
    }

    private static func quantized(_ vector: HeadphoneMotionVector) -> HeadphoneMotionVector {
        HeadphoneMotionVector(
            x: vector.x.quantized(toDecimalPlaces: vectorDecimalPlaces),
            y: vector.y.quantized(toDecimalPlaces: vectorDecimalPlaces),
            z: vector.z.quantized(toDecimalPlaces: vectorDecimalPlaces)
        )
    }
}

private extension Double {
    func quantized(toDecimalPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

/// One step the detector fired on, with the filtered signal value that crossed its peak
/// threshold - the algorithm's output, alongside the raw samples that produced it.
struct HeadphoneMotionRawStepDetectionRecord: Codable, Equatable, Sendable {
    let stepCount: Int
    let timestamp: TimeInterval
    let filteredVerticalAcceleration: Double

    init(detection: HeadphoneMotionStepDetection) {
        stepCount = detection.stepCount
        timestamp = detection.timestamp
        filteredVerticalAcceleration = detection.filteredVerticalAcceleration
    }
}

/// The detector's tunable thresholds at capture time, so a raw capture can be replayed against
/// the same decision boundaries that produced it even after the constants change in a later
/// build. Read directly from `HeadphoneMotionStepDetector`'s `static` constants - never a second,
/// hand-copied set of numbers.
struct HeadphoneMotionDetectorThresholds: Codable, Equatable, Sendable {
    let algorithmVersion: Int
    let peakThreshold: Double
    let minimumTimeBetweenPeaksSeconds: TimeInterval
    let maximumPitchRotationRate: Double
    let assumedSampleRateHz: Int

    static let current = HeadphoneMotionDetectorThresholds(
        algorithmVersion: HeadphoneMotionStepDetector.algorithmVersion,
        peakThreshold: HeadphoneMotionStepDetector.peakThreshold,
        minimumTimeBetweenPeaksSeconds: HeadphoneMotionStepDetector.minimumTimeBetweenPeaks,
        maximumPitchRotationRate: HeadphoneMotionStepDetector.maximumPitchRotationRate,
        assumedSampleRateHz: HeadphoneMotionStepDetector.assumedSampleRateHz
    )
}

/// Bounds on how much raw capture a single climb may buffer, so an unusually long session cannot
/// produce an unbounded in-memory buffer or upload. Once a cap is hit, further samples or
/// detections for that climb are dropped rather than growing the buffer - the capture still
/// covers the climb from its start, which is what "replay the algorithm's behavior" needs most,
/// just not past the cap.
enum HeadphoneMotionRawCaptureLimits {
    /// ~20 minutes of continuous capture at the detector's assumed 50Hz input rate. Generous
    /// enough to cover the overwhelming majority of Live Climb attempts in full. With the
    /// quantized `HeadphoneMotionRawCaptureSample` shape, a synthetic full-cap capture of
    /// deliberately noisy motion gzips to ~31 bytes per sample - ~1.9MB at this cap, about a
    /// third of `StepAccuracyRawCaptureStorageRepository.maximumCompressedBytes`. The earlier
    /// full-precision shape with a stored vertical acceleration measured ~110 bytes per sample
    /// (~6.6MB), past the cap, which is why samples are quantized and carry only raw inputs.
    static let maximumSampleCount = 60_000
    /// The detector's own 0.3s minimum time between peaks caps the fastest possible cadence at
    /// ~3.3 steps/sec, so 20 minutes at that ceiling is ~4,000 detections - rounded up for
    /// headroom.
    static let maximumDetectionCount = 4_000
}

/// The raw motion capture buffered for one climb - every input sample the detector saw, up to
/// `HeadphoneMotionRawCaptureLimits.maximumSampleCount`, and every step it fired on, up to
/// `maximumDetectionCount`. Produced only to let a badly-miscounted climb's algorithm behavior be
/// replayed offline; see `StepAccuracyRawCaptureRetentionPolicy` for when it is kept.
struct HeadphoneMotionRawCapture: Equatable, Sendable {
    let samples: [HeadphoneMotionRawCaptureSample]
    let detections: [HeadphoneMotionRawStepDetectionRecord]
    let didTruncateSamples: Bool
    let didTruncateDetections: Bool
    /// Where the session stood when this capture began, for a session recovered from a draft
    /// after the app was killed. The buffer lives only in memory, so a resumed session captures
    /// only what happened after the resume, and its detections' `stepCount` restarts at zero -
    /// `nil` means the capture covers the climb from its first sample.
    let resumeBase: HeadphoneMotionRawCaptureResumeBase?

    init(
        samples: [HeadphoneMotionRawCaptureSample],
        detections: [HeadphoneMotionRawStepDetectionRecord],
        didTruncateSamples: Bool,
        didTruncateDetections: Bool,
        resumeBase: HeadphoneMotionRawCaptureResumeBase? = nil
    ) {
        self.samples = samples
        self.detections = detections
        self.didTruncateSamples = didTruncateSamples
        self.didTruncateDetections = didTruncateDetections
        self.resumeBase = resumeBase
    }

    static let empty = HeadphoneMotionRawCapture(
        samples: [],
        detections: [],
        didTruncateSamples: false,
        didTruncateDetections: false
    )

    func resumed(from resumeBase: HeadphoneMotionRawCaptureResumeBase?) -> HeadphoneMotionRawCapture {
        HeadphoneMotionRawCapture(
            samples: samples,
            detections: detections,
            didTruncateSamples: didTruncateSamples,
            didTruncateDetections: didTruncateDetections,
            resumeBase: resumeBase
        )
    }
}

/// The steps and samples a recovered session had already counted before its raw capture began -
/// the part of the climb the capture cannot replay.
struct HeadphoneMotionRawCaptureResumeBase: Codable, Equatable, Sendable {
    let steps: Int
    let sampleCount: Int
}

/// Accumulates a `HeadphoneMotionRawCapture` while a session records. Confined to whatever queue
/// calls it - `HeadphoneMotionSessionProcessor` owns one on its motion queue - so it takes no
/// locks and must never be touched from more than one thread.
struct HeadphoneMotionRawCaptureBuffer {
    private var samples: [HeadphoneMotionRawCaptureSample] = []
    private var detections: [HeadphoneMotionRawStepDetectionRecord] = []
    private var didTruncateSamples = false
    private var didTruncateDetections = false

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        detections.removeAll(keepingCapacity: true)
        didTruncateSamples = false
        didTruncateDetections = false
    }

    mutating func recordSample(_ sample: HeadphoneMotionSample) {
        guard samples.count < HeadphoneMotionRawCaptureLimits.maximumSampleCount else {
            didTruncateSamples = true
            return
        }
        samples.append(HeadphoneMotionRawCaptureSample(sample: sample))
    }

    mutating func recordDetection(_ detection: HeadphoneMotionStepDetection) {
        guard detections.count < HeadphoneMotionRawCaptureLimits.maximumDetectionCount else {
            didTruncateDetections = true
            return
        }
        detections.append(HeadphoneMotionRawStepDetectionRecord(detection: detection))
    }

    func snapshot() -> HeadphoneMotionRawCapture {
        HeadphoneMotionRawCapture(
            samples: samples,
            detections: detections,
            didTruncateSamples: didTruncateSamples,
            didTruncateDetections: didTruncateDetections
        )
    }
}
