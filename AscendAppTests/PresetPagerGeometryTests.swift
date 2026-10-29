import CoreGraphics
import Testing
@testable import AscendApp

/// The swipe's rules, from the captain's handoff (`SWIPE_SPEC.md`).
struct PresetPagerGeometryTests {
    private typealias Geometry = PresetPagerGeometry

    @Test @MainActor
    func pagesSitACardAndAGapApart() {
        #expect(Geometry.step == PresetCardView.designSize + 16)
    }

    @Test
    func theRowFollowsTheFingerOneForOneInTheMiddle() {
        #expect(Geometry.trackedOffset(translation: -80, index: 2, count: 5) == -80)
        #expect(Geometry.trackedOffset(translation: 80, index: 2, count: 5) == 80)
    }

    @Test
    func pullingPastEitherEndResistsAtFortyFivePercent() {
        #expect(Geometry.trackedOffset(translation: 100, index: 0, count: 5) == 45)
        #expect(Geometry.trackedOffset(translation: -100, index: 4, count: 5) == -45)
    }

    @Test
    func pullingTowardTheNeighbourAtAnEndIsStillOneForOne() {
        #expect(Geometry.trackedOffset(translation: -100, index: 0, count: 5) == -100)
        #expect(Geometry.trackedOffset(translation: 100, index: 4, count: 5) == 100)
    }

    @Test
    func aReleaseOverSixtyPointsPages() {
        #expect(Geometry.destination(index: 1, count: 5, translation: -61, velocity: 0) == 2)
        #expect(Geometry.destination(index: 1, count: 5, translation: 61, velocity: 0) == 0)
        #expect(Geometry.destination(index: 1, count: 5, translation: -60, velocity: 0) == 1)
        #expect(Geometry.destination(index: 1, count: 5, translation: 59, velocity: 0) == 1)
    }

    @Test
    func aFlickOverThreeHundredFiftyPointsASecondPagesFromAShortDrag() {
        #expect(Geometry.destination(index: 1, count: 5, translation: -12, velocity: -351) == 2)
        #expect(Geometry.destination(index: 1, count: 5, translation: 12, velocity: 351) == 0)
        #expect(Geometry.destination(index: 1, count: 5, translation: -12, velocity: -349) == 1)
    }

    @Test
    func aDragOneWayWithAFlickTheOtherWayStays() {
        #expect(Geometry.destination(index: 2, count: 5, translation: -90, velocity: 500) == 2)
    }

    @Test
    func aReleaseNeverMovesMoreThanOneCardOrPastAnEnd() {
        #expect(Geometry.destination(index: 2, count: 5, translation: -900, velocity: -4_000) == 3)
        #expect(Geometry.destination(index: 0, count: 5, translation: 400, velocity: 2_000) == 0)
        #expect(Geometry.destination(index: 4, count: 5, translation: -400, velocity: -2_000) == 4)
    }

    @Test
    func theCentredCardIsFullAndANeighbourRestsAtNinetyPercentScaleAndFortyFivePercentOpacity() {
        let centred = Geometry.depth(signedDistance: 0)
        #expect(centred.scale == 1 && centred.opacity == 1 && centred.shadow == 1)
        let neighbour = Geometry.depth(signedDistance: -1)
        #expect(abs(neighbour.scale - 0.9) < 0.0001)
        #expect(abs(neighbour.opacity - 0.45) < 0.0001)
        #expect(neighbour.shadow == 0)
    }

    @Test
    func depthFollowsTheDragAndStopsAtOnePageAway() {
        let halfway = Geometry.depth(signedDistance: 0.5)
        #expect(abs(halfway.scale - 0.95) < 0.0001)
        #expect(abs(halfway.opacity - 0.725) < 0.0001)
        #expect(Geometry.depth(signedDistance: 3).scale == Geometry.depth(signedDistance: 1).scale)
    }

    @Test
    func holdingHalfwayLeavesTwoCardsHalfWayFromTheCentre() {
        let offset = -Geometry.step / 2
        #expect(Geometry.signedDistance(page: 2, index: 2, offset: offset) == -0.5)
        #expect(Geometry.signedDistance(page: 3, index: 2, offset: offset) == 0.5)
    }

    @Test
    func thePageMarksAndCaptionFollowTheDrag() {
        let halfway = Geometry.position(index: 1, offset: -Geometry.step / 2)
        #expect(halfway == 1.5)
        #expect(Geometry.markWidth(page: 1, position: 1) == 18)
        #expect(Geometry.markWidth(page: 2, position: 1) == 6)
        #expect(Geometry.markWidth(page: 1, position: halfway) == 12)
        #expect(Geometry.markWidth(page: 2, position: halfway) == 12)
        #expect(Geometry.activePage(position: 1.4, count: 5) == 1)
        #expect(Geometry.activePage(position: 1.6, count: 5) == 2)
        #expect(Geometry.activePage(position: -0.4, count: 5) == 0)
        #expect(Geometry.activePage(position: 4.6, count: 5) == 4)
    }

    @Test
    func theWindowKeepsTwoCardsEachSideAndStopsAtTheEnds() {
        #expect(Geometry.window(index: 4, count: 9) == 2...6)
        #expect(Geometry.window(index: 0, count: 9) == 0...2)
        #expect(Geometry.window(index: 8, count: 9) == 6...8)
        #expect(Geometry.window(index: 0, count: 1) == 0...0)
    }
}
