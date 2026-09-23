import Foundation

/// The two paces the Just Me pace card (`LiveClimbJustMeView.paceCard`) states, and the one
/// place their rules live.
///
/// **Average** is the whole climb so far: total steps over elapsed minutes.
/// **Current** is the trailing `windowSeconds` of the climb: the steps gained since the
/// newest sample at least that old, over the time since it. A fresh climb has no sample that
/// old until the window has elapsed, so its current pace is the same climb-so-far ratio and
/// the two numbers agree until the climber's cadence actually diverges from it.
///
/// Both answer `nil` rather than a number until `minimumSpanSeconds` of evidence exist: a
/// single step in the first second is 60 steps per minute, and the card would flicker through
/// absurd values before the clock had anything to say. Neither can produce NaN or infinity - a
/// zero span is `nil`, never a division.
///
/// A value type, mutated by the session view model on every step and every one-second tick,
/// and reset by anything that rewrites the count it measures (a machine sync correction, or a
/// session starting from a recovered draft), because a pace read across a rewrite is a number
/// about the rewrite rather than the climber.
struct LiveClimbPaceWindow: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let elapsedSeconds: TimeInterval
        let steps: Int
    }

    static let defaultWindowSeconds: TimeInterval = 30
    static let minimumSpanSeconds: TimeInterval = 5

    let windowSeconds: TimeInterval
    private(set) var samples: [Sample] = []

    init(windowSeconds: TimeInterval = LiveClimbPaceWindow.defaultWindowSeconds) {
        self.windowSeconds = max(windowSeconds, 1)
    }

    /// Total steps over elapsed minutes, or `nil` before `minimumSpanSeconds` of climb exist.
    static func averageStepsPerMinute(steps: Int, elapsedSeconds: TimeInterval) -> Int? {
        stepsPerMinute(steps: steps, seconds: elapsedSeconds)
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    /// Records where the live counter stood at `elapsedSeconds`. A sample from before the
    /// newest one means the session clock restarted underneath the window, so the window
    /// restarts with it rather than measuring across two clocks.
    mutating func record(elapsedSeconds: TimeInterval, steps: Int) {
        let elapsed = max(elapsedSeconds, 0)
        if let newest = samples.last, elapsed < newest.elapsedSeconds {
            samples.removeAll(keepingCapacity: true)
        }
        samples.append(Sample(elapsedSeconds: elapsed, steps: max(steps, 0)))
        trim(to: elapsed)
    }

    /// The trailing-window pace as of the live counter at `elapsedSeconds`, or `nil` before
    /// `minimumSpanSeconds` of evidence exist.
    func currentStepsPerMinute(elapsedSeconds: TimeInterval, steps: Int) -> Int? {
        let elapsed = max(elapsedSeconds, 0)
        guard let anchor = anchor(for: elapsed) else {
            return Self.averageStepsPerMinute(steps: steps, elapsedSeconds: elapsed)
        }

        return Self.stepsPerMinute(
            steps: steps - anchor.steps,
            seconds: elapsed - anchor.elapsedSeconds
        )
    }

    /// The newest sample at least `windowSeconds` old, else the oldest sample there is.
    private func anchor(for elapsedSeconds: TimeInterval) -> Sample? {
        let windowStart = elapsedSeconds - windowSeconds
        return samples.last(where: { $0.elapsedSeconds <= windowStart }) ?? samples.first
    }

    /// Drops every sample older than the window's anchor for `elapsedSeconds`: the anchor
    /// itself stays, so the window always spans at least `windowSeconds` once it can.
    private mutating func trim(to elapsedSeconds: TimeInterval) {
        let windowStart = elapsedSeconds - windowSeconds
        guard let anchorIndex = samples.lastIndex(where: { $0.elapsedSeconds <= windowStart }),
              anchorIndex > 0 else {
            return
        }
        samples.removeFirst(anchorIndex)
    }

    private static func stepsPerMinute(steps: Int, seconds: TimeInterval) -> Int? {
        guard seconds >= minimumSpanSeconds else { return nil }
        return max(Int((Double(steps) / (seconds / 60)).rounded()), 0)
    }
}
