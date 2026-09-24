import Foundation

/// The uploaded payload for a badly-miscounted climb: the raw motion capture plus the climb and
/// telemetry context already produced by the step-accuracy calibration flow
/// (`HeadphoneMotionWorkoutMetadata`), so the two never have to be joined by hand from separate
/// records to make sense of one climb. Private to its owner - see `storage.rules`
/// `step_accuracy_debug`.
struct StepAccuracyRawCaptureBlob: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let workoutId: String
    let climbId: String?
    let trackingMode: HeadphoneMotionWorkoutTrackingMode?

    let appSteps: Int
    let machineReportedSteps: Int
    let stepDiscrepancyAbs: Int
    let stepDiscrepancyPercent: Double?
    /// Every mid-climb step-sync correction, in full - `appSteps` includes them, the detections
    /// do not, so reconciling the two needs every one rather than metadata's bounded suffix.
    let stepCorrections: [HeadphoneMotionStepCorrection]
    /// The session's total motion sample count, including any recorded before a resume.
    let sampleCount: Int
    /// Set when the session was recovered from a draft after the app was killed: the capture
    /// then starts at the resume, and these are the steps and samples it cannot replay.
    let resumeBase: HeadphoneMotionRawCaptureResumeBase?
    /// Whether the capture misses part of the climb - a resumed session, or a buffer cap hit -
    /// so a gap between the detections and `appSteps` is not read as an algorithm miss.
    let isPartialCapture: Bool

    let headphoneRouteAtStart: HeadphoneAudioRouteSnapshot?
    let headphoneRouteAtSave: HeadphoneAudioRouteSnapshot?
    let isMotionCapableHeadphoneConnectedAtStart: Bool?
    let isMotionCapableHeadphoneConnectedAtSave: Bool?
    let didHeadphoneMotionDataFlow: Bool?

    let detectorThresholds: HeadphoneMotionDetectorThresholds
    let samples: [HeadphoneMotionRawCaptureSample]
    let detections: [HeadphoneMotionRawStepDetectionRecord]
    let didTruncateSamples: Bool
    let didTruncateDetections: Bool

    init(
        schemaVersion: Int = StepAccuracyRawCaptureBlob.currentSchemaVersion,
        workoutId: String,
        metadata: HeadphoneMotionWorkoutMetadata,
        appSteps: Int,
        machineReportedSteps: Int,
        stepDiscrepancyAbs: Int,
        stepCorrections: [HeadphoneMotionStepCorrection],
        detectorThresholds: HeadphoneMotionDetectorThresholds = .current,
        rawCapture: HeadphoneMotionRawCapture
    ) {
        self.schemaVersion = schemaVersion
        self.workoutId = workoutId
        self.climbId = metadata.climbId
        self.trackingMode = metadata.trackingMode
        self.appSteps = appSteps
        self.machineReportedSteps = machineReportedSteps
        self.stepDiscrepancyAbs = stepDiscrepancyAbs
        self.stepDiscrepancyPercent = metadata.stepDiscrepancyPercent
        self.stepCorrections = stepCorrections
        self.sampleCount = metadata.sampleCount
        self.resumeBase = rawCapture.resumeBase
        self.isPartialCapture = rawCapture.resumeBase != nil
            || rawCapture.didTruncateSamples
            || rawCapture.didTruncateDetections
        self.headphoneRouteAtStart = metadata.headphoneRouteAtStart
        self.headphoneRouteAtSave = metadata.headphoneRouteAtSave
        self.isMotionCapableHeadphoneConnectedAtStart = metadata.isMotionCapableHeadphoneConnectedAtStart
        self.isMotionCapableHeadphoneConnectedAtSave = metadata.isMotionCapableHeadphoneConnectedAtSave
        self.didHeadphoneMotionDataFlow = metadata.didHeadphoneMotionDataFlow
        self.detectorThresholds = detectorThresholds
        self.samples = rawCapture.samples
        self.detections = rawCapture.detections
        self.didTruncateSamples = rawCapture.didTruncateSamples
        self.didTruncateDetections = rawCapture.didTruncateDetections
    }
}
