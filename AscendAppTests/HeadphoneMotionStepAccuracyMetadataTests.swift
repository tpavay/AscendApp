import Foundation
import Testing
@testable import AscendApp

struct HeadphoneMotionStepAccuracyMetadataTests {
    @Test
    func calibrationComputesAbsoluteAndSignedPercentDiscrepancy() throws {
        var metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 100,
            climbId: nil,
            targetStepCount: nil,
            stopReason: .userStopped
        )

        // The reported example: app counted 500, the machine showed 605 - roughly a 17% undercount.
        metadata.applyMachineStepCalibration(machineReportedSteps: 605, appSteps: 500)

        #expect(metadata.machineReportedSteps == 605)
        #expect(metadata.stepDiscrepancyAbs == 105)
        let percent = try #require(metadata.stepDiscrepancyPercent)
        #expect(abs(percent - (-17.4)) < 0.05)
    }

    @Test
    func calibrationReportsPositivePercentWhenAppOvercounts() throws {
        var metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 100,
            climbId: nil,
            targetStepCount: nil,
            stopReason: .userStopped
        )

        metadata.applyMachineStepCalibration(machineReportedSteps: 400, appSteps: 500)

        #expect(metadata.stepDiscrepancyAbs == 100)
        let percent = try #require(metadata.stepDiscrepancyPercent)
        #expect(percent > 0)
    }

    @Test
    func calibrationNeverTouchesUnrelatedFields() {
        var metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 42,
            climbId: "climb-1",
            targetStepCount: 1000,
            stopReason: .targetReached
        )

        metadata.applyMachineStepCalibration(machineReportedSteps: 950, appSteps: 1000)

        #expect(metadata.sampleCount == 42)
        #expect(metadata.climbId == "climb-1")
        #expect(metadata.stopReason == .targetReached)
    }

    @Test
    func decodeIsSymmetricWithJsonString() throws {
        var metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 10,
            climbId: nil,
            targetStepCount: nil,
            stopReason: .userStopped,
            headphoneRoute: HeadphoneAudioRouteSnapshot(
                rawPortName: "AirPods Pro",
                rawPortType: "BluetoothA2DPOutput",
                family: .airPodsPro,
                isHeadphoneClassOutputConnected: true
            ),
            isMotionCapableHeadphoneConnected: true,
            didHeadphoneMotionDataFlow: true
        )
        metadata.applyMachineStepCalibration(machineReportedSteps: 100, appSteps: 90)

        let jsonString = try #require(metadata.jsonString)
        let decoded = try #require(HeadphoneMotionWorkoutMetadata.decode(from: jsonString))

        #expect(decoded == metadata)
    }

    @Test
    func decodeToleratesAPayloadWrittenBeforeStepAccuracyFieldsExisted() throws {
        // Every field the calibration/telemetry work added is optional so a payload from an
        // older build - carrying none of them - still decodes cleanly.
        let legacyJSON = """
        {"algorithmVersion":1,"sampleCount":10,"sampleRateAssumptionHz":50,\
        "source":"headphone_motion","stopReason":"user_stopped"}
        """

        let decoded = try #require(HeadphoneMotionWorkoutMetadata.decode(from: legacyJSON))

        #expect(decoded.headphoneRoute == nil)
        #expect(decoded.isMotionCapableHeadphoneConnected == nil)
        #expect(decoded.didHeadphoneMotionDataFlow == nil)
        #expect(decoded.machineReportedSteps == nil)
    }

    @Test
    func decodeReturnsNilForMalformedPayload() {
        #expect(HeadphoneMotionWorkoutMetadata.decode(from: "not json") == nil)
        #expect(HeadphoneMotionWorkoutMetadata.decode(from: nil) == nil)
    }

    @Test
    func stepCorrectionsAreCappedAtTwentyForSerialization() {
        let corrections = (0..<50).map { index in
            HeadphoneMotionStepCorrection(
                elapsedSeconds: index,
                detectedSteps: index,
                correctedSteps: index,
                deltaSteps: 0,
                trackingGapDurationSeconds: 1,
                totalUnavailableDurationSeconds: 1,
                interruptionCount: 1
            )
        }

        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 10,
            climbId: nil,
            targetStepCount: nil,
            stopReason: .userStopped,
            stepCorrections: corrections
        )

        #expect(metadata.stepCorrections?.count == 20)
        // The most recent corrections are kept, not the earliest.
        #expect(metadata.stepCorrections?.last?.elapsedSeconds == 49)
    }
}
