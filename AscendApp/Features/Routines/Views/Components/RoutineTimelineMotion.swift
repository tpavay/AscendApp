import SwiftUI

/// Motion is the substance of the timeline editor, which is exactly why every animation here
/// has a Reduce Motion answer. Springs become nothing, and a resizing block crossfades
/// instead of overshooting.
enum RoutineTimelineMotion {
    /// Selection and the reorder lift: short, with a little overshoot.
    static func selection(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.62)
    }

    /// A block taking or giving up width and height while its neighbours compress.
    static func resize(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.85)
    }

    /// Neighbours parting for a lifted block, and the block settling back onto the baseline.
    static func reorder(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.78)
    }

    /// The walkthrough moving from one spotlight to the next.
    static func coachMark(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }
}
