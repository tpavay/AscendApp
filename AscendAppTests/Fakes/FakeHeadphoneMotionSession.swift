import Foundation
@testable import AscendApp

@MainActor
final class FakeHeadphoneMotionSession: HeadphoneMotionSessionServicing {
    var duration: TimeInterval = 0
    var isMotionAccessDenied = false
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
    /// What the last start was asked to resume from: nil for a fresh session, the recovered
    /// draft's checkpoint for one restored after the app was killed.
    private(set) var lastResumeState: HeadphoneMotionSessionResumeState?

    /// What `applyStepCorrection` hands back. Left nil, a correction is refused the way the real
    /// service refuses one outside a recording.
    var correctionResult: HeadphoneMotionStepCorrection?
    /// The last correction asked for, whatever the answer.
    private(set) var lastCorrection: (correctedSteps: Int, trackingGapDuration: TimeInterval?)?

    func applyStepCorrection(
        correctedSteps: Int,
        trackingGapDuration: TimeInterval?
    ) -> HeadphoneMotionStepCorrection? {
        lastCorrection = (correctedSteps, trackingGapDuration)
        guard let correctionResult else { return nil }
        stepCount = correctionResult.correctedSteps
        stepCorrectionsSnapshot.append(correctionResult)
        return correctionResult
    }

    private var stepSampleHandler: ((LiveClimbStepSample) -> Void)?

    func setStepSampleHandler(_ handler: ((LiveClimbStepSample) -> Void)?) {
        stepSampleHandler = handler
    }

    /// Delivers a step sample the way the sensor does, stamped with the whole elapsed second.
    func emitStepSample() {
        stepSampleHandler?(LiveClimbStepSample(
            elapsedSeconds: Int(duration.rounded(.down)),
            cumulativeSteps: stepCount,
            source: .headphoneMotion
        ))
    }

    func pauseRecording() throws {
        guard status.isRecording else { throw HeadphoneMotionSessionError.notRecording }
        status = .paused
    }

    func resumeRecording() throws {
        guard status.isPaused else { throw HeadphoneMotionSessionError.notRecording }
        status = .recording
    }

    func startRecording(
        targetStepCount: Int?,
        resumeState: HeadphoneMotionSessionResumeState?
    ) throws {
        startRecordingCallCount += 1
        lastResumeState = resumeState
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
