import Foundation

@MainActor
protocol HeadphoneMotionSessionServicing: AnyObject {
    var duration: TimeInterval { get }
    var lastResolvedTrackingGap: HeadphoneMotionResolvedTrackingGap? { get }
    var sampleCount: Int { get }
    var status: HeadphoneMotionSessionStatus { get }
    var stepCorrectionsSnapshot: [HeadphoneMotionStepCorrection] { get }
    var stepCount: Int { get }
    var targetReached: Bool { get }
    var trackingIntegrity: HeadphoneMotionTrackingIntegrity { get }

    func applyStepCorrection(
        correctedSteps: Int,
        trackingGapDuration: TimeInterval?
    ) -> HeadphoneMotionStepCorrection?
    func setStepSampleHandler(_ handler: ((LiveClimbStepSample) -> Void)?)
    func startRecording(
        targetStepCount: Int?,
        resumeState: HeadphoneMotionSessionResumeState?
    ) throws
    func stopRecording(
        reason: HeadphoneMotionSessionStopReason
    ) async throws -> HeadphoneMotionSessionResult
}

extension HeadphoneMotionSessionService: HeadphoneMotionSessionServicing {}
