import Foundation
@testable import AscendApp

@MainActor
final class FakeHeadphoneMotionSession: HeadphoneMotionSessionServicing {
    var duration: TimeInterval = 0
    var lastResolvedTrackingGap: HeadphoneMotionResolvedTrackingGap?
    var sampleCount = 0
    var status: HeadphoneMotionSessionStatus = .idle
    var stepCorrectionsSnapshot: [HeadphoneMotionStepCorrection] = []
    var stepCount = 0
    var targetReached = false
    var trackingIntegrity: HeadphoneMotionTrackingIntegrity = .verified
    var startError: (any Error)?
    var onStartRecording: (() -> Void)?
    private(set) var startRecordingCallCount = 0

    func applyStepCorrection(
        correctedSteps: Int,
        trackingGapDuration: TimeInterval?
    ) -> HeadphoneMotionStepCorrection? {
        nil
    }

    func setStepSampleHandler(_ handler: ((LiveClimbStepSample) -> Void)?) {}

    func startRecording(
        targetStepCount: Int?,
        resumeState: HeadphoneMotionSessionResumeState?
    ) throws {
        startRecordingCallCount += 1
        onStartRecording?()
        if let startError {
            throw startError
        }
        status = .waitingForMotion
    }

    func stopRecording(
        reason: HeadphoneMotionSessionStopReason
    ) async throws -> HeadphoneMotionSessionResult {
        throw HeadphoneMotionSessionError.notRecording
    }
}
