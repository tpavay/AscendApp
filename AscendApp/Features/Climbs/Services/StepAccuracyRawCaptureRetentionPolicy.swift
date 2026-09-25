import Foundation

/// Decides whether a climb's buffered raw motion capture is worth keeping for step-counting
/// algorithm debugging. Pure and stateless so the trigger can be exercised without a live
/// headphone-motion session - see `StepAccuracyRawCaptureRetentionPolicyTests`.
///
/// Every buffered capture is discarded unless it clears all three gates: a machine count was
/// entered, the discrepancy against it is large enough to be worth investigating, and headphones
/// stayed connected the whole climb so the miss is attributable to the algorithm rather than to a
/// dropout. `LiveClimbSessionViewModel.submitStepAccuracyCalibration` is the only caller; the
/// buffer is simply never uploaded on any other path, which is what "discard" means here - there
/// is no separate deletion step because nothing was ever persisted.
enum StepAccuracyRawCaptureRetentionPolicy {
    /// The minimum `|app steps - machine steps|`, in either direction, before a raw capture is
    /// worth keeping. Below this a discrepancy reads as ordinary algorithm noise rather than a
    /// miscount worth debugging. Named and centralized so it is a one-line change to retune.
    static let minimumDiscrepancyAbs = 30

    static func shouldRetain(
        machineReportedSteps: Int?,
        discrepancyAbs: Int?,
        wasHeadphoneConnectedThroughoutClimb: Bool?
    ) -> Bool {
        guard let machineReportedSteps, machineReportedSteps > 0 else { return false }
        guard let discrepancyAbs, discrepancyAbs >= minimumDiscrepancyAbs else { return false }
        // A gap that isn't provably a fully-connected session fails closed rather than uploading
        // a capture that might just be explaining a dropout.
        guard wasHeadphoneConnectedThroughoutClimb == true else { return false }
        return true
    }
}
