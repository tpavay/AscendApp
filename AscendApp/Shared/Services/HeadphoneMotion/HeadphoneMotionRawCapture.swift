import Foundation

/// One raw headphone-motion sample as fed to `HeadphoneMotionStepDetector`, plus the vertical
/// acceleration the detector derives from it - the exact input the algorithm consumed.
struct HeadphoneMotionRawCaptureSample: Codable, Equatable, Sendable {
    let timestamp: TimeInterval
    let userAcceleration: HeadphoneMotionVector
    let rotationRate: HeadphoneMotionVector
    let gravity: HeadphoneMotionVector
    let verticalAcceleration: Double

    init(sample: HeadphoneMotionSample) {
        timestamp = sample.timestamp
        userAcceleration = sample.userAcceleration
        rotationRate = sample.rotationRate
        gravity = sample.gravity
        verticalAcceleration = HeadphoneMotionStepDetector.verticalAcceleration(from: sample)
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
    /// enough to cover the overwhelming majority of Live Climb attempts in full, while keeping
    /// the gzip-compressed upload (see `StepAccuracyRawCaptureStorageRepository`) well under its
    /// own size cap even for noisy, poorly-compressible motion data.
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

    static let empty = HeadphoneMotionRawCapture(
        samples: [],
        detections: [],
        didTruncateSamples: false,
        didTruncateDetections: false
    )
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
