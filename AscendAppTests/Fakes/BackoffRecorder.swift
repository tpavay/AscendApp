import Foundation

/// Stands in for a retry backoff's sleep: records each requested delay and returns at once, so a
/// test walks the whole retry schedule without spending its seconds on the clock.
actor BackoffRecorder {
    private(set) var delays: [Duration] = []

    var count: Int { delays.count }

    /// Records `delay` and returns how many backoffs have been requested so far, this one included.
    @discardableResult
    func record(_ delay: Duration) -> Int {
        delays.append(delay)
        return delays.count
    }
}
