import CoreGraphics
import Foundation
import Testing
@testable import AscendApp

struct RoutineTimelineGestureTests {
    private let block = UUID()
    private let otherBlock = UUID()

    @Test
    func theFirstCallbackOfAllOpensASession() {
        #expect(
            RoutineTimelineGesture.startsNewSession(
                sessionId: nil,
                sessionStartLocation: nil,
                intervalId: block,
                startLocation: CGPoint(x: 40, y: 90)
            )
        )
    }

    @Test
    func aCallbackFromTheSameTouchKeepsTheSessionItIsDriving() {
        #expect(
            !RoutineTimelineGesture.startsNewSession(
                sessionId: block,
                sessionStartLocation: CGPoint(x: 40, y: 90),
                intervalId: block,
                startLocation: CGPoint(x: 40, y: 90)
            )
        )
    }

    /// The cross-block case: a session cancelled on one block must never author the next drag
    /// on another, or the duration lands on whichever block was last held.
    @Test
    func aTouchOnAnotherBlockAlwaysOpensItsOwnSession() {
        #expect(
            RoutineTimelineGesture.startsNewSession(
                sessionId: block,
                sessionStartLocation: CGPoint(x: 40, y: 90),
                intervalId: otherBlock,
                startLocation: CGPoint(x: 40, y: 90)
            )
        )
    }

    /// The same-block case: a cancelled session is stale even when the next touch lands on the
    /// block that opened it, so a fresh touch re-reads the level the climber left it at.
    @Test
    func aSecondTouchOnTheSameBlockOpensAFreshSession() {
        #expect(
            RoutineTimelineGesture.startsNewSession(
                sessionId: block,
                sessionStartLocation: CGPoint(x: 40, y: 90),
                intervalId: block,
                startLocation: CGPoint(x: 41, y: 90)
            )
        )
        #expect(
            RoutineTimelineGesture.startsNewSession(
                sessionId: block,
                sessionStartLocation: CGPoint(x: 40, y: 90),
                intervalId: block,
                startLocation: CGPoint(x: 40, y: 91)
            )
        )
    }

    /// A long press reports its session before the drag under it has a location. That is the
    /// session still opening, not a second touch, so it keeps what it has.
    @Test
    func aSessionWaitingOnItsDragLocationIsNotTreatedAsANewTouch() {
        #expect(
            !RoutineTimelineGesture.startsNewSession(
                sessionId: block,
                sessionStartLocation: nil,
                intervalId: block,
                startLocation: CGPoint(x: 40, y: 90)
            )
        )
        #expect(
            !RoutineTimelineGesture.startsNewSession(
                sessionId: block,
                sessionStartLocation: CGPoint(x: 40, y: 90),
                intervalId: block,
                startLocation: nil
            )
        )
    }
}
