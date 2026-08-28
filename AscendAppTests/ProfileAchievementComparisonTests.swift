import Foundation
import Testing
@testable import AscendApp

/// The profile comparison's ACHIEVEMENTS section, decided without a view tree.
///
/// The screen's grammar is left-is-you / right-is-them, and before this the section drew one
/// unattributed shelf of the *other* climber's badges - so half the comparison was missing and
/// a decorated climber saw no section at all opposite a brand-new one.
@Suite
struct ProfileAchievementComparisonTests {
    /// One champion, two seconds, one third, one top-ten and one top-hundred finish.
    /// Cumulative bands land on top1 1, top3 4, top10 5, top100 6.
    static let decorated = ProfileAchievementLadder(
        records: [
            record(id: "champion", type: .weeklyTop1, rank: 1),
            record(id: "second-a", type: .monthlyTop3, rank: 2),
            record(id: "second-b", type: .yearlyTop3, rank: 2),
            record(id: "third", type: .weeklyTop3, rank: 3),
            record(id: "top-ten", type: .weeklyTop10, rank: 7),
            record(id: "top-hundred", type: .weeklyTop100, rank: 55)
        ]
    )

    static func record(
        id: String,
        type: ProfileAchievementType,
        rank: Int?
    ) -> ProfileAchievementRecord {
        ProfileAchievementRecord(
            id: id,
            type: type,
            scope: .global,
            metric: .steps,
            climbId: nil,
            periodKey: nil,
            periodStartAt: nil,
            periodEndAt: nil,
            earnedAt: Date(timeIntervalSince1970: 1_754_000_000),
            rank: rank,
            value: 12_000,
            valueUnit: "steps"
        )
    }

    private func entries(
        viewer: ProfileAchievementLadder,
        other: ProfileAchievementLadder
    ) -> [ProfileAchievementComparisonEntry] {
        ProfileAchievementCatalogue.comparisonEntries(
            viewer: ProfileAchievementTally(ladder: viewer),
            other: ProfileAchievementTally(ladder: other)
        )
    }

    private func presentation(
        viewer: ProfileAchievementLadder,
        other: ProfileAchievementLadder,
        isOtherLoading: Bool = false
    ) -> PublicProfileAchievementPresentation {
        PublicProfileAchievementPresentation(
            viewer: ProfileAchievementTally(ladder: viewer),
            other: ProfileAchievementTally(ladder: other),
            isOtherLoading: isOtherLoading
        )
    }

    // MARK: - The four matchups

    @Test
    func bothPopulatedCountsEverySharedBadgeOnBothSides() {
        let viewer = ProfileAchievementLadder(
            records: [
                Self.record(id: "v-champ-a", type: .weeklyTop1, rank: 1),
                Self.record(id: "v-champ-b", type: .monthlyTop1, rank: 1),
                Self.record(id: "v-third", type: .weeklyTop3, rank: 3)
            ]
        )

        let rows = entries(viewer: viewer, other: Self.decorated)

        #expect(rows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
        #expect(rows.map(\.viewerCount) == [2, 0, 1, 3, 3])
        #expect(rows.map(\.otherCount) == [1, 2, 1, 5, 6])
    }

    /// The defect the captain found on 2026-08-25: the section used to hide entirely on the
    /// other climber's emptiness, so a three-time champion opening a brand-new climber's
    /// profile saw no ACHIEVEMENTS at all.
    @Test
    func aDecoratedViewerAgainstAnEmptyClimberStillDrawsTheViewersBadges() {
        let rows = entries(viewer: Self.decorated, other: .empty)

        #expect(rows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
        #expect(rows.map(\.viewerCount) == [1, 2, 1, 5, 6])
        #expect(rows.allSatisfy { $0.otherCount == 0 })
    }

    @Test
    func anEmptyViewerAgainstADecoratedClimberStillDrawsTheOtherSide() {
        let rows = entries(viewer: .empty, other: Self.decorated)

        #expect(rows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
        #expect(rows.allSatisfy { $0.viewerCount == 0 })
        #expect(rows.map(\.otherCount) == [1, 2, 1, 5, 6])
    }

    /// Two new climbers meeting must not get a monument to things neither of them has done.
    @Test
    func twoEmptyClimbersProduceNoRowsAtAll() {
        #expect(entries(viewer: .empty, other: .empty).isEmpty)
    }

    // MARK: - Presentation

    @Test
    func theSectionHidesOnlyWhenNeitherClimberHoldsABadge() {
        #expect(
            presentation(viewer: .empty, other: .empty) == .hidden
        )
    }

    @Test
    func theSectionStaysVisibleWhenOnlyTheViewerHoldsBadges() {
        guard case .visible(let rows) = presentation(viewer: Self.decorated, other: .empty) else {
            Issue.record("A decorated viewer must keep the section, whoever they are looking at")
            return
        }
        #expect(rows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
    }

    @Test
    func theSectionStaysVisibleWhenOnlyTheOtherClimberHoldsBadges() {
        #expect(presentation(viewer: .empty, other: Self.decorated) != .hidden)
    }

    /// The row set depends on both sides, so nothing can be drawn honestly mid-load. Half a
    /// comparison would print zeroes nobody read.
    @Test
    func theSectionHidesWhileTheOtherClimbersSnapshotIsStillLoading() {
        #expect(
            presentation(
                viewer: Self.decorated,
                other: Self.decorated,
                isOtherLoading: true
            ) == .hidden
        )
    }

    // MARK: - What a ladder cannot say

    /// A banded profile carries no second-versus-third breakdown, so neither side can be given
    /// a zero it did not earn the right to claim. The row is dropped, not ghosted.
    @Test
    func aBandedOpponentDropsThePlacementRowsRatherThanGhostingThem() {
        let banded = ProfileAchievementLadder(
            bandedCounters: ProfileAchievementCounts(top1: 2, top3: 9, top10: 14, top100: 30)
        )

        let rows = entries(viewer: Self.decorated, other: banded)

        #expect(rows.map(\.id) == ["top1", "top10", "top100"])
        #expect(rows.map(\.otherCount) == [2, 14, 30])
    }

    /// A banded ladder can still answer at zero: every second and third also counts toward
    /// `top3`, so a `top3` holding nothing beyond the champion finishes proves the podium below
    /// first is empty. Without this, a viewer whose only badge is a #2 would lose their row to a
    /// brand-new climber - the same defect in a narrower disguise.
    @Test
    func aBandedLadderWithNothingBelowFirstStillAnswersThePlacements() {
        let bandedEmpty = ProfileAchievementLadder(
            bandedCounters: ProfileAchievementCounts(top1: 1, top3: 1, top10: 4, top100: 9)
        )

        #expect(bandedEmpty.secondPlaceFinishes == 0)
        #expect(bandedEmpty.thirdPlaceFinishes == 0)

        let rows = entries(viewer: Self.decorated, other: bandedEmpty)
        #expect(rows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
    }

    @Test
    func aBandedLadderWithFinishesBelowFirstWithholdsThePlacements() {
        let banded = ProfileAchievementLadder(
            bandedCounters: ProfileAchievementCounts(top1: 1, top3: 3, top10: 4, top100: 9)
        )

        #expect(banded.secondPlaceFinishes == nil)
        #expect(banded.thirdPlaceFinishes == nil)
    }

    // MARK: - The catalogue

    @Test
    func theCatalogueScopesFirstAscentsToTheOwnProfileOnly() {
        let comparison = ProfileAchievementCatalogue.definitions(for: .comparison).map(\.id)
        let ownProfile = ProfileAchievementCatalogue.definitions(for: .ownProfile).map(\.id)

        #expect(comparison == ["top1", "place2", "place3", "top10", "top100"])
        #expect(ownProfile == ["first-ascents", "top1", "place2", "place3", "top10", "top100"])
    }

    /// Display order is the array's order, so the shelf and the comparison rows cannot drift.
    @Test
    func everySurfaceDrawsTheCatalogueInItsDeclaredOrder() {
        for surface in ProfileAchievementSurface.allCases {
            let scoped = ProfileAchievementCatalogue.definitions(for: surface).map(\.id)
            let expected = ProfileAchievementCatalogue.all
                .filter { $0.surfaces.contains(surface) }
                .map(\.id)

            #expect(scoped == expected)
        }
    }

    @Test
    func theOwnProfileShelfCountsFirstAscentsFromTheSummariesBesideTheLadder() {
        let tokens = ProfilePrestigeToken.tokens(
            for: ProfileAchievementTally(ladder: Self.decorated, firstAscentsHeld: 2),
            surface: .ownProfile
        )

        #expect(tokens.map(\.id) == ["first-ascents", "top1", "place2", "place3", "top10", "top100"])
        #expect(tokens.first?.label == "First Ascents")
        #expect(tokens.first?.count == 2)
    }

    @Test
    func aSingleFirstAscentReadsInTheSingular() {
        let tokens = ProfilePrestigeToken.tokens(
            for: ProfileAchievementTally(ladder: .empty, firstAscentsHeld: 1),
            surface: .ownProfile
        )

        #expect(tokens.map(\.label) == ["First Ascent"])
    }

    // MARK: - A ladder nobody read

    /// The hole a confident zero left: `.empty` is a measured zero, and a failed read used to
    /// borrow it. An unreadable ladder answers `nil` for the *bands* too, not only the exact
    /// placements, or the comparison would still ghost a decorated climber's crown.
    @Test
    func anUnreadableLadderAnswersNothingAtAll() {
        let unreadable = ProfileAchievementLadder.unreadable

        #expect(unreadable.isReadable == false)
        #expect(unreadable.hasAny == false)
        #expect(unreadable.bandFinishes(.top1) == nil)
        #expect(unreadable.bandFinishes(.top3) == nil)
        #expect(unreadable.bandFinishes(.top10) == nil)
        #expect(unreadable.bandFinishes(.top100) == nil)
        #expect(unreadable.secondPlaceFinishes == nil)
        #expect(unreadable.thirdPlaceFinishes == nil)
        #expect(unreadable != .empty)
    }

    /// A measured zero stays a measured zero, which is what makes the dash mean something.
    @Test
    func anEmptyLadderStillAnswersZeroForEveryBadge() {
        let empty = ProfileAchievementLadder.empty

        #expect(empty.isReadable)
        #expect(empty.bandFinishes(.top1) == 0)
        #expect(empty.bandFinishes(.top100) == 0)
        #expect(empty.secondPlaceFinishes == 0)
        #expect(empty.thirdPlaceFinishes == 0)
    }

    @Test
    func anUnreadableViewerKeepsTheDecoratedClimbersRowsAndDashesTheirOwnSide() {
        let rows = entries(viewer: .unreadable, other: Self.decorated)

        #expect(rows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
        #expect(rows.allSatisfy { $0.viewerCount == nil })
        #expect(rows.map(\.otherCount) == [1, 2, 1, 5, 6])
    }

    @Test
    func anUnreadableClimberKeepsTheViewersRowsAndDashesTheirSide() {
        let rows = entries(viewer: Self.decorated, other: .unreadable)

        #expect(rows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
        #expect(rows.map(\.viewerCount) == [1, 2, 1, 5, 6])
        #expect(rows.allSatisfy { $0.otherCount == nil })
    }

    /// Nobody is known to hold anything, so there is nothing to compare and nothing to draw.
    @Test
    func twoUnreadableLaddersProduceNoRowsAndHideTheSection() {
        #expect(entries(viewer: .unreadable, other: .unreadable).isEmpty)
        #expect(presentation(viewer: .unreadable, other: .unreadable) == .hidden)
    }

    @Test
    func anUnreadableLadderAgainstAProvenEmptyOneProducesNoRows() {
        #expect(entries(viewer: .unreadable, other: .empty).isEmpty)
        #expect(entries(viewer: .empty, other: .unreadable).isEmpty)
        #expect(presentation(viewer: .unreadable, other: .empty) == .hidden)
    }

    /// The two silences stay distinguishable. A banded ladder was *read* - its taxonomy is
    /// simply coarser than a #2 - so its placement rows are dropped rather than dashed, which
    /// is the settled design and not the same thing as a failed read.
    @Test
    func aBandedLadderDropsThePlacementsWhileAnUnreadableOneDashesThem() {
        let banded = ProfileAchievementLadder(
            bandedCounters: ProfileAchievementCounts(top1: 1, top3: 3, top10: 4, top100: 9)
        )

        let bandedRows = entries(viewer: Self.decorated, other: banded)
        #expect(bandedRows.map(\.id) == ["top1", "top10", "top100"])
        #expect(bandedRows.allSatisfy { $0.otherCount != nil })

        let unreadableRows = entries(viewer: Self.decorated, other: .unreadable)
        #expect(unreadableRows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
    }
}
