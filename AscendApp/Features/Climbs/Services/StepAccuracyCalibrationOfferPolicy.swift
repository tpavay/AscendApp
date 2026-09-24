import Foundation

/// Decides whether the optional post-climb step-accuracy calibration prompt has anything worth
/// asking about. Pure and stateless so the trigger can be exercised without a live session - see
/// `StepAccuracyCalibrationOfferPolicyTests`.
///
/// `ClimbAttemptStatus` plays no part in this decision: a saved-progress (incomplete) climb's
/// recorded step count can be just as wrong as a completed climb's, so the prompt is offered for
/// both alike. The one thing that does matter is whether there is enough of a sample to compare -
/// a climb saved after only a handful of steps reads as noise, not a discrepancy worth reporting.
enum StepAccuracyCalibrationOfferPolicy {
    /// Below this many recorded steps, the app's own count is too small a sample to compare
    /// meaningfully against what the machine displayed. Named and centralized so it is a one-line
    /// change to retune.
    static let minimumRecordedSteps = 100

    static func shouldOffer(recordedSteps: Int) -> Bool {
        recordedSteps >= minimumRecordedSteps
    }
}
