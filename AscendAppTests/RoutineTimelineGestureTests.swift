import Foundation
import Testing
@testable import AscendApp

struct RoutineTimelineGestureTests {
    private let block = UUID()
    private let otherBlock = UUID()

    /// Also the cancelled-gesture case: `@GestureState` drops the session the moment the
    /// gesture stops being active, so the next touch - on the same block, from the same point -
    /// finds nothing in flight and re-reads the level and duration the block stands at now.
    @Test
    func aTouchWithNothingInFlightOpensASession() {
        #expect(RoutineTimelineGesture.startsNewSession(sessionId: nil, intervalId: block))
    }

    @Test
    func aCallbackFromTheSessionInFlightKeepsDrivingIt() {
        #expect(!RoutineTimelineGesture.startsNewSession(sessionId: block, intervalId: block))
    }

    /// A session must never author a block it does not name, or a drag lands the duration on
    /// whichever block was last held.
    @Test
    func aCallbackNamingAnotherBlockAlwaysOpensItsOwnSession() {
        #expect(RoutineTimelineGesture.startsNewSession(sessionId: block, intervalId: otherBlock))
    }
}
