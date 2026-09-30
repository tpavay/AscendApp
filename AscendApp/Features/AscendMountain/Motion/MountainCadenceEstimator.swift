import Foundation

/// How fast the climber's steps are arriving right now, for animation only (spec 8).
///
/// The workout's own pace (`LiveClimbPaceWindow`) is a 30-second window that says nothing for
/// the first half minute, which is right for a number on screen and far too slow to move an
/// avatar. This reads the last few step arrivals instead, and it decays as soon as the next
/// step is overdue, so an athlete who stops is seen to stop within a stride or two. It is never
/// shown as the climber's pace and never feeds back into the workout.
struct MountainCadenceEstimator: Equatable, Sendable {
    /// Assumed for the first step after standing still, before a second step gives an interval:
    /// 90 steps per minute, the spec's "normal climbing".
    static let nominalStepsPerSecond = 1.5
    /// Steps averaged over.
    static let windowSteps = 6
    /// A gap this long means the climber stopped; the next step starts a fresh estimate.
    static let restGapSeconds = 2.0
    /// The estimate fades to zero over the last part of the rest gap instead of dropping off.
    static let fadeSeconds = 0.5
    /// More steps than this in one observation is a correction or a jump, not a stride.
    static let burstLimit = 4
    static let maximumStepsPerSecond = 5.0

    private var arrivalTimes: [Double] = []
    private var lastObservedCount: Int?

    /// Feeds the authoritative step count as observed at `time` (seconds on any monotonic clock).
    mutating func observe(stepCount: Int, at time: Double) {
        defer { lastObservedCount = stepCount }
        guard let lastObservedCount else { return }

        let newSteps = stepCount - lastObservedCount
        guard newSteps > 0 else {
            if newSteps < 0 { arrivalTimes.removeAll(keepingCapacity: true) }
            return
        }
        guard newSteps <= Self.burstLimit else {
            arrivalTimes.removeAll(keepingCapacity: true)
            return
        }
        if let latest = arrivalTimes.last, time - latest > Self.restGapSeconds {
            arrivalTimes.removeAll(keepingCapacity: true)
        }

        arrivalTimes.append(contentsOf: repeatElement(time, count: newSteps))
        if arrivalTimes.count > Self.windowSteps {
            arrivalTimes.removeFirst(arrivalTimes.count - Self.windowSteps)
        }
    }

    func stepsPerSecond(at time: Double) -> Double {
        guard let latest = arrivalTimes.last else { return 0 }

        let sinceLatest = max(time - latest, 0)
        guard sinceLatest < Self.restGapSeconds else { return 0 }

        let measured = min(measuredStepsPerSecond, Self.maximumStepsPerSecond)
        // Once the next step is overdue, the honest rate is at most one step per elapsed gap.
        let overdueCeiling = sinceLatest > 0 ? 1 / sinceLatest : measured
        let fade = min(max((Self.restGapSeconds - sinceLatest) / Self.fadeSeconds, 0), 1)
        return min(measured, overdueCeiling) * fade
    }

    func stepsPerMinute(at time: Double) -> Double {
        stepsPerSecond(at: time) * 60
    }

    private var measuredStepsPerSecond: Double {
        guard let first = arrivalTimes.first, let last = arrivalTimes.last else { return 0 }
        let span = last - first
        // A pair that landed in the same frame has no interval to measure yet.
        guard arrivalTimes.count >= 2, span > 0.05 else { return Self.nominalStepsPerSecond }
        return Double(arrivalTimes.count - 1) / span
    }
}
