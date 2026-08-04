import CoreGraphics
import Foundation

/// The geometry of the routine timeline: how wide each block is drawn, and how far a finger
/// travels to move a value by one step. Pure maths so the drag can be reasoned about without
/// a view tree.
enum RoutineTimelineLayout {
    /// Nothing narrower than this, so every block holds its number and its tap target.
    /// The stored duration stays exact; this is a render rule only.
    static let minimumBlockWidth: CGFloat = 28
    static let blockSpacing: CGFloat = 3

    /// Where the drag stops getting more sensitive. Below this a 30-second step on a long
    /// routine would be a couple of points of travel, so one thumb-width would buy minutes.
    static let minimumPointsPerDurationStep: CGFloat = 8

    /// A block widened to the floor has room for its level but not its clock.
    static let minimumClockWidth: CGFloat = 38

    /// The movement caption sits on the block's floor, under a label stack that already draws
    /// the level and the clock from the top. Both have to fit or the two collide.
    static let minimumMovementLabelWidth: CGFloat = 56
    static let minimumMovementLabelHeight: CGFloat = 58

    static func showsDurationClock(blockWidth: CGFloat) -> Bool {
        blockWidth >= minimumClockWidth
    }

    static func showsMovementLabel(blockWidth: CGFloat, blockHeight: CGFloat) -> Bool {
        blockWidth >= minimumMovementLabelWidth && blockHeight >= minimumMovementLabelHeight
    }

    /// Fit to width: every block is its share of the routine, except that a block too short
    /// to hold its own label is widened to the floor and the rest give up the difference.
    static func blockWidths(durations: [TimeInterval], availableWidth: CGFloat) -> [CGFloat] {
        guard !durations.isEmpty else { return [] }

        let contentWidth = availableWidth - blockSpacing * CGFloat(durations.count - 1)
        guard contentWidth > 0 else {
            return Array(repeating: 0, count: durations.count)
        }

        // Too many blocks for the floor to hold: share what there is rather than overflow.
        guard contentWidth > minimumBlockWidth * CGFloat(durations.count) else {
            return Array(repeating: contentWidth / CGFloat(durations.count), count: durations.count)
        }

        let totalDuration = durations.reduce(0, +)
        guard totalDuration > 0 else {
            return Array(repeating: contentWidth / CGFloat(durations.count), count: durations.count)
        }

        var widths = durations.map { contentWidth * CGFloat($0 / totalDuration) }
        var flooredIndices: Set<Int> = []

        // Widening one block pushes the others down, which can drop a new one under the
        // floor, so keep going until nobody else falls through.
        while true {
            let fallingThrough = widths.indices.filter { index in
                !flooredIndices.contains(index) && widths[index] < minimumBlockWidth
            }
            guard !fallingThrough.isEmpty else { break }

            flooredIndices.formUnion(fallingThrough)

            let shareableWidth = contentWidth - minimumBlockWidth * CGFloat(flooredIndices.count)
            let shareableDuration = durations.indices
                .filter { !flooredIndices.contains($0) }
                .reduce(0) { $0 + durations[$1] }

            guard shareableDuration > 0, shareableWidth > 0 else {
                return widths.indices.map { flooredIndices.contains($0) ? minimumBlockWidth : 0 }
            }

            for index in widths.indices {
                widths[index] = flooredIndices.contains(index)
                    ? minimumBlockWidth
                    : shareableWidth * CGFloat(durations[index] / shareableDuration)
            }
        }

        return widths
    }

    /// A drag across the whole plot spans all 25 levels, so the step is the same fraction of
    /// the finger's travel whatever height the plot is given.
    static func pointsPerLevel(plotHeight: CGFloat) -> CGFloat {
        guard plotHeight > 0 else { return 1 }
        return plotHeight / CGFloat(RoutineIntervalScale.levelRange.count)
    }

    /// Hybrid: the block edge tracks the finger until a 30-second step would cost less than
    /// 8pt of travel, then the step is clamped so one thumb-width never buys minutes.
    static func pointsPerDurationStep(contentWidth: CGFloat, totalDuration: TimeInterval) -> CGFloat {
        guard contentWidth > 0, totalDuration > 0 else { return minimumPointsPerDurationStep }

        let trackingWidth = contentWidth * CGFloat(RoutineIntervalScale.durationStep / totalDuration)
        return max(minimumPointsPerDurationStep, trackingWidth)
    }

    /// Where a lifted block lands, as an index into the list with that block already removed.
    static func reorderDestinationIndex(
        draggedIndex: Int,
        draggedCenterX: CGFloat,
        widths: [CGFloat]
    ) -> Int {
        guard widths.indices.contains(draggedIndex) else { return draggedIndex }

        var centers: [CGFloat] = []
        var x: CGFloat = 0
        for width in widths {
            centers.append(x + width / 2)
            x += width + blockSpacing
        }

        return widths.indices
            .filter { $0 != draggedIndex && centers[$0] < draggedCenterX }
            .count
    }

    /// The leading edge of a block, used to place a lifted block against its neighbours.
    static func blockOriginX(at index: Int, widths: [CGFloat]) -> CGFloat {
        guard widths.indices.contains(index) else { return 0 }
        return widths[..<index].reduce(0) { $0 + $1 + blockSpacing }
    }
}
