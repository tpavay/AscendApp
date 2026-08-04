import SwiftUI

/// Every animation the routine builder runs, and the one place its Reduce Motion answer is
/// decided. With Reduce Motion on nothing animates: a block takes its new size, its new place
/// and its new order in a single frame. The builder reads its animations from here and names
/// none of its own, so no path can reintroduce motion the climber asked not to see.
enum RoutineTimelineMotion {
    /// Selection and the reorder lift: short, with a little overshoot.
    static func selection(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.62)
    }

    /// A block taking or giving up width and height while its neighbours compress.
    static func resize(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.85)
    }

    /// Neighbours parting for a lifted block, and the block settling back onto the baseline.
    static func reorder(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78)
    }

    /// The walkthrough moving from one spotlight to the next.
    static func coachMark(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    /// Advanced Settings opening and closing under the timeline.
    static func sectionReveal(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }
}
