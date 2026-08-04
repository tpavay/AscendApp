import Foundation

/// One drawn bar in `RoutineIntensityBarChart`, either a saved interval or the live draft ghost.
struct RoutineIntensityChartSegment: Identifiable, Equatable {
    let interval: RoutineInterval
    let isGhost: Bool

    var id: UUID {
        interval.id
    }

    /// Places the draft ghost at its own `order` rather than after everything else.
    /// Appending it unconditionally drew the interval being edited as the last bar,
    /// so editing interval 2 of 5 rendered it fifth.
    static func segments(
        intervals: [RoutineInterval],
        ghostInterval: RoutineInterval?
    ) -> [RoutineIntensityChartSegment] {
        var segments = intervals.map { interval in
            RoutineIntensityChartSegment(interval: interval, isGhost: false)
        }

        guard let ghostInterval else { return segments }

        let insertionIndex = min(max(ghostInterval.order, 0), segments.count)
        segments.insert(
            RoutineIntensityChartSegment(interval: ghostInterval, isGhost: true),
            at: insertionIndex
        )
        return segments
    }
}
