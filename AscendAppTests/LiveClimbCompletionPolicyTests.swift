//
//  LiveClimbCompletionPolicyTests.swift
//  AscendAppTests
//

import Foundation
import Testing
@testable import AscendApp

struct LiveClimbCompletionPolicyTests {
    @Test
    func reachingTheStepTargetIsACompletion() {
        #expect(LiveClimbCompletionPolicy.isCompletion(steps: 1_000, targetStepCount: 1_000))
        #expect(LiveClimbCompletionPolicy.isCompletion(steps: 1_001, targetStepCount: 1_000))
        #expect(LiveClimbCompletionPolicy.isCompletion(steps: 999, targetStepCount: 1_000) == false)
    }

    @Test
    func missingStepTargetIsNeverACompletion() {
        #expect(LiveClimbCompletionPolicy.isCompletion(steps: 1_000, targetStepCount: nil) == false)
        #expect(LiveClimbCompletionPolicy.isCompletion(steps: 1_000, targetStepCount: 0) == false)
    }

    @Test
    func passingTheTargetResolvesOnlyAManualStopToTargetReached() {
        #expect(
            LiveClimbCompletionPolicy.resolvedStopReason(
                .userStopped,
                steps: 1_000,
                targetStepCount: 1_000
            ) == .targetReached
        )
    }

    /// Publication is gated on this value, so a hand-typed recovery step count must not be able
    /// to turn an interrupted session into a First Ascent claim.
    @Test
    func passingTheTargetLeavesANonManualStopReasonAlone() {
        #expect(
            LiveClimbCompletionPolicy.resolvedStopReason(
                .interrupted,
                steps: 1_200,
                targetStepCount: 1_000
            ) == .interrupted
        )
        #expect(
            LiveClimbCompletionPolicy.resolvedStopReason(
                .discarded,
                steps: 1_200,
                targetStepCount: 1_000
            ) == .discarded
        )
        #expect(
            LiveClimbCompletionPolicy.resolvedStopReason(
                .targetReached,
                steps: 1_200,
                targetStepCount: 1_000
            ) == .targetReached
        )
    }

    /// Narrowing the reason upgrade must not narrow what counts: an interrupted session past the
    /// target is still a finish, because status reads steps rather than the stop reason.
    @Test
    func anInterruptedSessionPastTheTargetIsStillACompletion() {
        let metadata = makeMetadata(stopReason: .interrupted, climbTargetStepCount: 1_000)

        #expect(LiveClimbCompletionPolicy.attemptStatus(for: metadata, steps: 1_200) == .completed)
    }

    @Test
    func fallingShortOfTheTargetPreservesTheRecordedStopReason() {
        #expect(
            LiveClimbCompletionPolicy.resolvedStopReason(
                .userStopped,
                steps: 800,
                targetStepCount: 1_000
            ) == .userStopped
        )
    }

    @Test
    func metadataStatusRanksStepsAheadOfAStaleStopReason() {
        let metadata = makeMetadata(stopReason: .userStopped, climbTargetStepCount: 1_000)

        #expect(LiveClimbCompletionPolicy.attemptStatus(for: metadata, steps: 1_000) == .completed)
        #expect(LiveClimbCompletionPolicy.attemptStatus(for: metadata, steps: 999) == .failed)
    }

    @Test
    func metadataStatusPrefersTheClimbTargetOverTheSessionTarget() {
        let metadata = makeMetadata(
            stopReason: .userStopped,
            targetStepCount: 400,
            climbTargetStepCount: 1_000
        )

        #expect(LiveClimbCompletionPolicy.attemptStatus(for: metadata, steps: 500) == .failed)
    }

    @Test
    func metadataStatusFallsBackToStopReasonWhenNoTargetWasRecorded() {
        let reached = makeMetadata(
            stopReason: .targetReached,
            targetStepCount: nil,
            climbTargetStepCount: nil
        )
        let stopped = makeMetadata(
            stopReason: .userStopped,
            targetStepCount: nil,
            climbTargetStepCount: nil
        )

        #expect(LiveClimbCompletionPolicy.attemptStatus(for: reached, steps: 1_000) == .completed)
        #expect(LiveClimbCompletionPolicy.attemptStatus(for: stopped, steps: 1_000) == .failed)
    }

    @Test
    func recordedStepsStopAtTheTarget() {
        #expect(LiveClimbCompletionPolicy.recordedSteps(steps: 1_010, targetStepCount: 1_000) == 1_000)
        #expect(LiveClimbCompletionPolicy.recordedSteps(steps: 800, targetStepCount: 1_000) == 800)
    }

    @Test
    func recordedStepsKeepTheRawCountWhenNoTargetWasRecorded() {
        #expect(LiveClimbCompletionPolicy.recordedSteps(steps: 1_010, targetStepCount: nil) == 1_010)
        #expect(LiveClimbCompletionPolicy.recordedSteps(steps: 1_010, targetStepCount: 0) == 1_010)
    }

    @Test
    func metadataTargetPrefersTheClimbTargetOverTheSessionTarget() {
        let metadata = makeMetadata(
            stopReason: .userStopped,
            targetStepCount: 400,
            climbTargetStepCount: 1_000
        )
        let sessionOnly = makeMetadata(
            stopReason: .userStopped,
            targetStepCount: 400,
            climbTargetStepCount: nil
        )
        let untargeted = makeMetadata(
            stopReason: .userStopped,
            targetStepCount: nil,
            climbTargetStepCount: nil
        )

        #expect(LiveClimbCompletionPolicy.targetStepCount(for: metadata) == 1_000)
        #expect(LiveClimbCompletionPolicy.targetStepCount(for: sessionOnly) == 400)
        #expect(LiveClimbCompletionPolicy.targetStepCount(for: untargeted) == nil)
    }

    private func makeMetadata(
        stopReason: HeadphoneMotionSessionStopReason,
        targetStepCount: Int? = 1_000,
        climbTargetStepCount: Int?
    ) -> HeadphoneMotionWorkoutMetadata {
        HeadphoneMotionWorkoutMetadata(
            sampleCount: 500,
            climbId: "policy-climb",
            targetStepCount: targetStepCount,
            climbTargetStepCount: climbTargetStepCount,
            stopReason: stopReason
        )
    }
}
