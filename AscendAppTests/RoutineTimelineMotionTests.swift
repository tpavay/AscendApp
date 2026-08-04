import SwiftUI
import Testing
@testable import AscendApp

struct RoutineTimelineMotionTests {
    /// A resize is the one change Reduce Motion does not simply drop: the size lands in a frame
    /// and the block crossfades between the two states, so the change stays legible. An easing
    /// curve on the geometry would be motion, and nothing at all would be a hard cut.
    @Test
    func aResizeCrossfadesUnderReduceMotionInsteadOfMovingOrCutting() {
        #expect(
            RoutineTimelineMotion.resizeTreatment(reduceMotion: true)
                == .crossfade(.easeInOut(duration: 0.15))
        )
        #expect(RoutineTimelineMotion.resizeCrossfade(reduceMotion: true) == .easeInOut(duration: 0.15))
        #expect(RoutineTimelineMotion.resize(reduceMotion: true) == nil)
    }

    /// The crossfade is the reduced answer only. With motion allowed the geometry springs and
    /// there is nothing to fade, or the block would both move and blink.
    @Test
    func theCrossfadeIsNotTakenWhenMotionIsAllowed() {
        #expect(
            RoutineTimelineMotion.resizeTreatment(reduceMotion: false)
                == .animatedGeometry(.spring(response: 0.42, dampingFraction: 0.85))
        )
        #expect(RoutineTimelineMotion.resizeCrossfade(reduceMotion: false) == nil)
        #expect(RoutineTimelineMotion.resize(reduceMotion: false) == .spring(response: 0.42, dampingFraction: 0.85))
    }

    /// Geometry and opacity are exclusive: whichever carries the resize, the other stays out of
    /// it, so no path can ever both move a block and fade it.
    @Test
    func onlyOneOfGeometryAndOpacityEverCarriesAResize() {
        for reduceMotion in [true, false] {
            let geometry = RoutineTimelineMotion.resize(reduceMotion: reduceMotion)
            let crossfade = RoutineTimelineMotion.resizeCrossfade(reduceMotion: reduceMotion)

            #expect((geometry == nil) != (crossfade == nil))
        }
    }

    /// Selection and the reorder lift move geometry with no second way to read them, so those
    /// stop outright.
    @Test
    func reduceMotionLeavesSelectionAndReorderAnimatingNothing() {
        #expect(RoutineTimelineMotion.selection(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.reorder(reduceMotion: true) == nil)
        #expect(RoutineTimelineMotion.coachMark(reduceMotion: true) == nil)
    }

    /// The springs are the approved design, so reduced mode is the only thing that turns them
    /// off - this is what stops a "fix" from flattening the timeline for everyone.
    @Test
    func everyMotionStillSpringsWhenReduceMotionIsOff() {
        #expect(RoutineTimelineMotion.selection(reduceMotion: false) == .spring(response: 0.3, dampingFraction: 0.62))
        #expect(RoutineTimelineMotion.reorder(reduceMotion: false) == .spring(response: 0.36, dampingFraction: 0.78))
        #expect(RoutineTimelineMotion.coachMark(reduceMotion: false) == .easeInOut(duration: 0.2))
    }
}
