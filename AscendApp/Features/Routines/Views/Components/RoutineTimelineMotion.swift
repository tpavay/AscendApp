import SwiftUI

/// Motion is the substance of the timeline editor, which is exactly why every animation here
/// has a Reduce Motion answer. Selection and the reorder lift simply stop. A resize keeps its
/// meaning a different way: the new size lands in a single frame and the block's own pixels
/// fade from the old state to the new, so the change is still legible with nothing moving.
enum RoutineTimelineMotion {
    /// How a block shows that its level or its duration changed. The two cases are exclusive:
    /// either the geometry carries the change, or opacity does, and never both.
    enum ResizeTreatment: Equatable {
        /// The block springs to its new size.
        case animatedGeometry(Animation)
        /// The size lands at once and the block crossfades between the two states.
        case crossfade(Animation)
    }

    static func resizeTreatment(reduceMotion: Bool) -> ResizeTreatment {
        reduceMotion
            ? .crossfade(.easeInOut(duration: 0.15))
            : .animatedGeometry(.spring(response: 0.42, dampingFraction: 0.85))
    }

    /// What the block's geometry is allowed to animate with - nothing, when opacity is
    /// carrying the change instead.
    static func resize(reduceMotion: Bool) -> Animation? {
        guard case .animatedGeometry(let animation) = resizeTreatment(reduceMotion: reduceMotion) else {
            return nil
        }
        return animation
    }

    /// What the block's crossfade runs with - nothing, when the geometry is carrying it.
    static func resizeCrossfade(reduceMotion: Bool) -> Animation? {
        guard case .crossfade(let animation) = resizeTreatment(reduceMotion: reduceMotion) else {
            return nil
        }
        return animation
    }

    /// Selection and the reorder lift: short, with a little overshoot.
    static func selection(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.62)
    }

    /// Neighbours parting for a lifted block, and the block settling back onto the baseline.
    static func reorder(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78)
    }

    /// The walkthrough moving from one spotlight to the next.
    static func coachMark(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }
}
