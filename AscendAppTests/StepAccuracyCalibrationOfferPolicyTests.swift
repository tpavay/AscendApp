import Testing

@testable import AscendApp

/// Pure trigger logic for the optional post-climb calibration prompt's minimum-step floor.
/// `LiveClimbSessionStepAccuracyCalibrationOfferTests` proves the view model actually wires this
/// in for both completed and incomplete/saved-progress sessions.
struct StepAccuracyCalibrationOfferPolicyTests {
    @Test("A recorded step count at or above the floor offers calibration")
    func offersAtOrAboveFloor() {
        #expect(StepAccuracyCalibrationOfferPolicy.shouldOffer(
            recordedSteps: StepAccuracyCalibrationOfferPolicy.minimumRecordedSteps
        ))
        #expect(StepAccuracyCalibrationOfferPolicy.shouldOffer(
            recordedSteps: StepAccuracyCalibrationOfferPolicy.minimumRecordedSteps + 1
        ))
        #expect(StepAccuracyCalibrationOfferPolicy.shouldOffer(recordedSteps: 2_000))
    }

    @Test("A trivially small recorded step count never offers calibration")
    func suppressesBelowFloor() {
        #expect(!StepAccuracyCalibrationOfferPolicy.shouldOffer(
            recordedSteps: StepAccuracyCalibrationOfferPolicy.minimumRecordedSteps - 1
        ))
        #expect(!StepAccuracyCalibrationOfferPolicy.shouldOffer(recordedSteps: 7))
        #expect(!StepAccuracyCalibrationOfferPolicy.shouldOffer(recordedSteps: 0))
    }
}
