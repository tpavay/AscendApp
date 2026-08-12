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
    /// What the sensor hands back when the session is stopped. Left nil, stopping still refuses
    /// the way a session that was never recording does.
    var stopResult: HeadphoneMotionSessionResult?
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
        guard let stopResult else {
            throw HeadphoneMotionSessionError.notRecording
        }

        status = .idle
        return stopResult
    }
}
