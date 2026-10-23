import Foundation

/// What a resumed session tells the climber the moment it is counting again: how long Ascend was
/// not counting, why when it knows, and the two honest ways to settle the gap.
struct HeadphoneSessionResumeNotice: Identifiable, Equatable, Sendable {
    /// Where a step count for the gap came from, for the record and the funnel.
    enum GapSource: String, Sendable {
        /// Only wall clock was credited; the step count stayed at the draft's.
        case wallClock = "wall_clock"
        /// The phone's own motion coprocessor counted steps across the gap.
        case pedometer
        /// The climber typed the machine's number.
        case machine
    }

    let id = UUID()
    let gap: TimeInterval
    let lossReason: HeadphoneSessionLossReason
    /// The steps the draft held when the process died - the number the field starts from when the
    /// phone has no estimate of its own.
    let detectedSteps: Int
    /// The phone's own pedometer count over the gap (`PhoneStepEstimating`), when the coprocessor
    /// had one. Zero for a powered-off phone; possibly non-zero for a killed process whose owner
    /// kept stepping with the phone on them. Labelled as the phone's estimate, never as the
    /// machine's number.
    var phoneEstimateSteps: Int?

    var gapMinutes: Int {
        max(Int((gap / 60).rounded()), 1)
    }

    /// What the step field opens with: the draft's count plus the phone's estimate when it has one.
    var suggestedSteps: Int {
        guard let phoneEstimateSteps, phoneEstimateSteps > 0 else { return detectedSteps }
        return detectedSteps + phoneEstimateSteps
    }

    /// The session's count a settled field stands for. The field is a count at the resume moment -
    /// the draft's number, the phone's estimate on top, or the machine's - while the sensor has
    /// kept counting under the sheet since, so every step it counted after the resume is kept.
    func correctedSteps(enteredSteps: Int, sensorStepsNow: Int) -> Int {
        enteredSteps + max(sensorStepsNow - detectedSteps, 0)
    }

    var suggestedStepsSource: GapSource {
        guard let phoneEstimateSteps, phoneEstimateSteps > 0 else { return .wallClock }
        return .pedometer
    }

    var headline: String {
        "Ascend stopped counting for \(gapMinutes) \(gapMinutes == 1 ? "minute" : "minutes")."
    }

    var explanation: String {
        let clause = lossReason.climberFacingClause
        let credit = "The time counts. Enter the machine's step count to credit the steps, or keep climbing from \(detectedSteps.formatted())."
        return "\(clause) and the climb kept going without it. \(credit)"
    }
}
