import Foundation
import Testing
@testable import AscendApp

struct StepAccuracyRawCaptureRetentionPolicyTests {
    @Test
    func retainsAnUndercountAtOrAboveThirty() {
        #expect(StepAccuracyRawCaptureRetentionPolicy.shouldRetain(
            machineReportedSteps: 630,
            discrepancyAbs: 30,
            wasHeadphoneConnectedThroughoutClimb: true
        ))
    }

    @Test
    func retainsAnOvercountAtOrAboveThirty() {
        // The app counted 30 more steps than the machine - the other direction from the
        // undercount case, and equally worth debugging.
        #expect(StepAccuracyRawCaptureRetentionPolicy.shouldRetain(
            machineReportedSteps: 500,
            discrepancyAbs: 30,
            wasHeadphoneConnectedThroughoutClimb: true
        ))
    }

    @Test
    func discardsJustBelowTheThirtyStepBoundary() {
        #expect(StepAccuracyRawCaptureRetentionPolicy.shouldRetain(
            machineReportedSteps: 629,
            discrepancyAbs: 29,
            wasHeadphoneConnectedThroughoutClimb: true
        ) == false)
    }

    @Test
    func discardsWhenHeadphonesDidNotStayConnectedThroughout() {
        #expect(StepAccuracyRawCaptureRetentionPolicy.shouldRetain(
            machineReportedSteps: 630,
            discrepancyAbs: 130,
            wasHeadphoneConnectedThroughoutClimb: false
        ) == false)
    }

    @Test
    func discardsWhenConnectionContinuityIsUnknown() {
        // A payload written before tracking-integrity fields existed resolves this to `nil`,
        // which must fail closed rather than uploading unverified data.
        #expect(StepAccuracyRawCaptureRetentionPolicy.shouldRetain(
            machineReportedSteps: 630,
            discrepancyAbs: 130,
            wasHeadphoneConnectedThroughoutClimb: nil
        ) == false)
    }

    @Test
    func discardsWhenNoMachineCountWasEntered() {
        #expect(StepAccuracyRawCaptureRetentionPolicy.shouldRetain(
            machineReportedSteps: nil,
            discrepancyAbs: 130,
            wasHeadphoneConnectedThroughoutClimb: true
        ) == false)
    }

    @Test
    func discardsWhenMachineCountIsZero() {
        #expect(StepAccuracyRawCaptureRetentionPolicy.shouldRetain(
            machineReportedSteps: 0,
            discrepancyAbs: 130,
            wasHeadphoneConnectedThroughoutClimb: true
        ) == false)
    }

    @Test
    func discardsWhenDiscrepancyIsUnresolved() {
        #expect(StepAccuracyRawCaptureRetentionPolicy.shouldRetain(
            machineReportedSteps: 630,
            discrepancyAbs: nil,
            wasHeadphoneConnectedThroughoutClimb: true
        ) == false)
    }
}
