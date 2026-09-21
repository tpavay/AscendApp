import CoreGraphics
import Testing
@testable import AscendApp

/// The sheet's three resting heights and which of them a drag can reach. Home's sheet
/// drags down to `compact`; Browse only ever arrives there through a marker tap.
struct BrowseSheetDetentTests {
    private let homeDetents: [BrowseSheetDetent] = [.compact, .medium, .expanded]
    private let browseDetents: [BrowseSheetDetent] = [.medium, .expanded]

    @Test
    func homeDragsThroughAllThreePositions() {
        #expect(BrowseSheetDetent.compact.nextUp(in: homeDetents) == .medium)
        #expect(BrowseSheetDetent.medium.nextUp(in: homeDetents) == .expanded)
        #expect(BrowseSheetDetent.expanded.nextUp(in: homeDetents) == .expanded)
        #expect(BrowseSheetDetent.expanded.nextDown(in: homeDetents) == .medium)
        #expect(BrowseSheetDetent.medium.nextDown(in: homeDetents) == .compact)
        #expect(BrowseSheetDetent.compact.nextDown(in: homeDetents) == .compact)
    }

    @Test
    func browseNeverDragsDownToCompact() {
        #expect(BrowseSheetDetent.medium.nextDown(in: browseDetents) == .medium)
        #expect(BrowseSheetDetent.expanded.nextDown(in: browseDetents) == .medium)
        #expect(BrowseSheetDetent.compact.nextUp(in: browseDetents) == .medium)
    }

    @Test
    func theCompactHeightIsOneLineAndAGrabber() {
        let compact = BrowseSheetDetent.compact.height(containerHeight: 874, topInset: 59, bottomInset: 34)
        let medium = BrowseSheetDetent.medium.height(containerHeight: 874, topInset: 59, bottomInset: 34)
        let expanded = BrowseSheetDetent.expanded.height(containerHeight: 874, topInset: 59, bottomInset: 34)

        #expect(compact == CGFloat(86 + 34))
        #expect(compact < medium)
        #expect(medium < expanded)
        #expect(expanded == CGFloat(874))
    }

    @Test
    func nearestSettlesOnADraggableDetentOnly() {
        let compactOffset = BrowseSheetDetent.compact.offset(containerHeight: 874, topInset: 59, bottomInset: 34)
        let nearestForHome = BrowseSheetDetent.nearest(
            to: compactOffset,
            among: homeDetents,
            containerHeight: 874,
            topInset: 59,
            bottomInset: 34
        )
        let nearestForBrowse = BrowseSheetDetent.nearest(
            to: compactOffset,
            among: browseDetents,
            containerHeight: 874,
            topInset: 59,
            bottomInset: 34
        )
        #expect(nearestForHome == .compact)
        #expect(nearestForBrowse == .medium)
    }
}
