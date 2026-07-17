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
    func passingTheTargetResolvesAManualStopToTargetReached() {
        #expect(
            LiveClimbCompletionPolicy.resolvedStopReason(
                .userStopped,
                steps: 1_000,
                targetStepCount: 1_000
            ) == .targetReached
        )
        #expect(
            LiveClimbCompletionPolicy.resolvedStopReason(
                .interrupted,
                steps: 1_200,
                targetStepCount: 1_000
            ) == .targetReached
        )
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
