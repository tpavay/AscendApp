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

        // Weighted by duration: five minutes at level 20 should move the average more than
        // thirty seconds at level 4. The rule lives in `RoutineIntervalScale`, so the header
        // here, the card stripes and the hero cannot drift apart.
        self.init(
            totalDuration: intervals.reduce(0) { $0 + $1.duration },
            intervalCount: intervals.count,
            averageLevel: RoutineIntervalScale.roundedAverageLevel(of: intervals),
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
