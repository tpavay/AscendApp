import Foundation
import SwiftUI
import Testing
@testable import AscendApp

struct RoutineTimelineMotionTests {
    /// Reduce Motion is a must-have on this screen. Every animation here moves geometry - block
    /// width, block height, the reorder lift, the neighbours parting - and an easing curve is
    /// still motion, so the reduced answer is no animation at all and the change lands in one
    /// frame.
    @Test
    func reduceMotionLeavesNothingAnimatingTheTimeline() {
        #expect(RoutineTimelineMotion.selection(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.resize(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.reorder(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.coachMark(reduceMotion: true) == nil)
    }

    /// The springs are the approved design, so reduced mode is the only thing that turns them
    /// off - this is what stops a "fix" from flattening the timeline for everyone.
    @Test
    func everyMotionStillSpringsWhenReduceMotionIsOff() {
        #expect(RoutineTimelineMotion.selection(reduceMotion: false) == .spring(response: 0.3, dampingFraction: 0.62))
        #expect(RoutineTimelineMotion.resize(reduceMotion: false) == .spring(response: 0.42, dampingFraction: 0.85))
        #expect(RoutineTimelineMotion.reorder(reduceMotion: false) == .spring(response: 0.36, dampingFraction: 0.78))
        #expect(RoutineTimelineMotion.coachMark(reduceMotion: false) == .easeInOut(duration: 0.2))
    }

    /// The contract above only binds the editor while the editor has no animation of its own.
    /// A literal written straight into a `withAnimation` or an `.animation(_:value:)` there
    /// would animate whatever Reduce Motion says, so the editor may not contain one: every
    /// animation it runs has to come through `RoutineTimelineMotion`.
    @Test
    func theTimelineEditorHoldsNoAnimationOfItsOwn() throws {
        let source = try String(contentsOf: Self.timelineEditorSource, encoding: .utf8)

        for literal in [".spring(", ".easeInOut(", ".easeIn(", ".easeOut(", ".linear(", ".bouncy", ".smooth", ".snappy"] {
            #expect(
                !source.contains(literal),
                "RoutineTimelineEditor names an animation itself: \(literal)"
            )
        }

        #expect(source.contains("RoutineTimelineMotion."))
    }

    /// Resolved from this file's own location, so the guard reads the source that shipped
    /// alongside it rather than a copy that may have drifted.
    private static var timelineEditorSource: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "AscendApp/Features/Routines/Views/Components/RoutineTimelineEditor.swift")
    }
}
