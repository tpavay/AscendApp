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
            PublicProfileAchievementPresentation(
                viewer: .empty,
                other: .empty,
                isOtherLoading: false
            ) == .hidden
        )
    }

    @Test
    func theSectionStaysVisibleWhenOnlyTheViewerHoldsBadges() {
        let presentation = PublicProfileAchievementPresentation(
            viewer: Self.decorated,
            other: .empty,
            isOtherLoading: false
        )

        guard case .visible(let rows) = presentation else {
            Issue.record("A decorated viewer must keep the section, whoever they are looking at")
            return
        }
        #expect(rows.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
    }

    @Test
    func theSectionStaysVisibleWhenOnlyTheOtherClimberHoldsBadges() {
        let presentation = PublicProfileAchievementPresentation(
            viewer: .empty,
            other: Self.decorated,
            isOtherLoading: false
        )

        #expect(presentation != .hidden)
    }

    /// The row set depends on both sides, so nothing can be drawn honestly mid-load. Half a
    /// comparison would print zeroes nobody read.
    @Test
    func theSectionHidesWhileTheOtherClimbersSnapshotIsStillLoading() {
        #expect(
            PublicProfileAchievementPresentation(
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
}
