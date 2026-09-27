import Foundation

/// What a splits surface says about a climb recorded before splits ran past the hour.
///
/// The pre-fix sampler kept nothing after 59:50 but the climb's total, so that stretch is one row
/// holding its real steps and its average pace. Every surface that draws it labels it as an average
/// and says why, rather than presenting it as a segment's own pace.
enum LiveClimbPaceSplitCopy {
    /// Stands where a measured row says `SPM`.
    static let unsplitPaceUnit = "AVG"

    /// The note under a splits list that ends in an unsplit row.
    static func unsplitStretchNote(fromClockText clockText: String) -> String {
        "Recorded before splits ran past the hour. The last row is the average pace from \(clockText) to the finish."
    }

    /// What VoiceOver reads for a row, measured or not.
    static func accessibilityLabel(for split: LiveClimbPaceSplit, timeRangeText: String) -> String {
        let steps = "\(split.steps.formatted()) steps"
        let pace = "\(Int(split.stepsPerMinute.rounded()).formatted()) steps per minute"
        guard split.isMeasured else {
            return "\(timeRangeText), \(steps), averaging \(pace), not split"
        }

        return "\(timeRangeText), \(steps), \(pace)"
    }
}
