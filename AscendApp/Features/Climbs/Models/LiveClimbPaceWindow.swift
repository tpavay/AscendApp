import Foundation

/// The two paces the Just Me pace card (`LiveClimbJustMeView.paceCard`) states, and the one
/// place their rules live.
///
/// **Average** is the whole climb so far: total steps over elapsed minutes. It answers from the
/// start - zero until the clock has run a full second, since there is no time to average over
/// before that - so the climber always has a pace to read.
/// **Current** is the trailing `windowSeconds` of the climb: the steps gained since the
/// newest sample at least that old, over the time since it. Until the window genuinely spans
/// `windowSeconds` - a sample that old exists - it answers `nil` and the card shows its
/// placeholder. It never borrows the average to fill the gap: a number labelled CURRENT in the
/// first half minute would be a claim about a window the climb has not had yet.
///
/// Neither can produce NaN or infinity: a span too short to divide by answers zero (average)
/// or `nil` (current), never a division.
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
    /// The shortest clock the average divides by; below it the average is zero.
    static let minimumAverageSpanSeconds: TimeInterval = 1

    let windowSeconds: TimeInterval
    private(set) var samples: [Sample] = []

    init(windowSeconds: TimeInterval = LiveClimbPaceWindow.defaultWindowSeconds) {
        self.windowSeconds = max(windowSeconds, 1)
    }

    /// Total steps over elapsed minutes, from the start: zero before `minimumAverageSpanSeconds`.
    static func averageStepsPerMinute(steps: Int, elapsedSeconds: TimeInterval) -> Int {
        guard elapsedSeconds.isFinite, elapsedSeconds >= minimumAverageSpanSeconds else { return 0 }
        return stepsPerMinute(steps: steps, seconds: elapsedSeconds)
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

    /// The trailing-window pace as of the live counter at `elapsedSeconds`, or `nil` until a
    /// sample at least `windowSeconds` old exists to measure it from.
    func currentStepsPerMinute(elapsedSeconds: TimeInterval, steps: Int) -> Int? {
        guard elapsedSeconds.isFinite else { return nil }
        let elapsed = max(elapsedSeconds, 0)
        guard let anchor = anchor(for: elapsed) else { return nil }

        return Self.stepsPerMinute(
            steps: steps - anchor.steps,
            seconds: elapsed - anchor.elapsedSeconds
        )
    }

    /// The newest sample at least `windowSeconds` old, or `nil` while the window is still
    /// shorter than that.
    private func anchor(for elapsedSeconds: TimeInterval) -> Sample? {
        let windowStart = elapsedSeconds - windowSeconds
        return samples.last(where: { $0.elapsedSeconds <= windowStart })
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

    /// Only ever called with `seconds` of at least one: the average guards its own span, and
    /// the current window spans `windowSeconds`.
    private static func stepsPerMinute(steps: Int, seconds: TimeInterval) -> Int {
        max(Int((Double(steps) / (seconds / 60)).rounded()), 0)
    }
}
