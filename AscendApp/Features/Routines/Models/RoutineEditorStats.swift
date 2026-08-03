import Foundation

/// The four numbers above the timeline. Every one is derived from the intervals - nothing
/// here is stored.
struct RoutineEditorStats: Equatable {
    enum Key: CaseIterable {
        case total
        case intervalCount
        case averageLevel
        case peakLevel
    }

    let totalDuration: TimeInterval
    let intervalCount: Int
    let averageLevel: Int
    let peakLevel: Int

    static let empty = RoutineEditorStats(
        totalDuration: 0,
        intervalCount: 0,
        averageLevel: 0,
        peakLevel: 0
    )

    init(totalDuration: TimeInterval, intervalCount: Int, averageLevel: Int, peakLevel: Int) {
        self.totalDuration = totalDuration
        self.intervalCount = intervalCount
        self.averageLevel = averageLevel
        self.peakLevel = peakLevel
    }

    init(intervals: [RoutineInterval]) {
        guard !intervals.isEmpty else {
            self = .empty
            return
        }

        let totals = intervals.reduce(into: (weightedLevel: 0.0, duration: 0.0)) { result, interval in
            result.weightedLevel += Double(interval.resolvedLevel) * interval.duration
            result.duration += interval.duration
        }

        // Weighted by duration: five minutes at level 20 should move the average more than
        // thirty seconds at level 4.
        let average = totals.duration > 0 ? (totals.weightedLevel / totals.duration).rounded() : 0

        self.init(
            totalDuration: totals.duration,
            intervalCount: intervals.count,
            averageLevel: Int(average),
            peakLevel: intervals.map(\.resolvedLevel).max() ?? 0
        )
    }

    var isEmpty: Bool {
        intervalCount == 0
    }

    /// Whole minutes, so a routine at 18:30 still reads 18.
    var totalMinutes: Int {
        Int(totalDuration) / 60
    }

    /// Which numbers moved during the gesture in progress - those are the ones drawn live.
    func changedKeys(comparedTo other: RoutineEditorStats) -> Set<Key> {
        var changed: Set<Key> = []

        if totalMinutes != other.totalMinutes { changed.insert(.total) }
        if intervalCount != other.intervalCount { changed.insert(.intervalCount) }
        if averageLevel != other.averageLevel { changed.insert(.averageLevel) }
        if peakLevel != other.peakLevel { changed.insert(.peakLevel) }

        return changed
    }
}
