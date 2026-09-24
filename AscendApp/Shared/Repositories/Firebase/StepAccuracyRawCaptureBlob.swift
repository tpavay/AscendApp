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
