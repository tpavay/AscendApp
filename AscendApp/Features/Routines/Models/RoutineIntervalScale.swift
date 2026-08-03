import Foundation

/// How a routine interval's level becomes a drawn block, and what the drag gestures are
/// allowed to write back. Height and colour both come off the level on 25 steps, so a
/// block at level 16 never draws the same as a block at level 20.
enum RoutineIntervalScale {
    static let levelRange = 1...25

    /// The stored duration grid, unchanged: `stride(from: 30, through: 1800, by: 30)`.
    static let durationStep: TimeInterval = 30
    static let durationRange: ClosedRange<TimeInterval> = 30...1800

    /// Level 1 maps to 0 and level 25 to 1 - the same normalisation `SegmentedHeatmapSlider`
    /// uses, so a block and the slider agree on colour for the same level.
    static func normalizedLevel(_ level: Int) -> Double {
        let span = Double(levelRange.upperBound - levelRange.lowerBound)
        return Double(SPMMappingService.clampedLevel(level) - levelRange.lowerBound) / span
    }

    /// Level 1 keeps a fifth of the plot so the lightest interval still reads as a block;
    /// level 25 fills it.
    static func heightFraction(forLevel level: Int) -> Double {
        0.2 + normalizedLevel(level) * 0.8
    }

    static func clampedDuration(_ duration: TimeInterval) -> TimeInterval {
        min(max(duration, durationRange.lowerBound), durationRange.upperBound)
    }

    /// Durations only ever exist on the 30-second grid, whatever a drag lands on.
    static func snappedDuration(_ duration: TimeInterval) -> TimeInterval {
        clampedDuration((duration / durationStep).rounded() * durationStep)
    }
}
