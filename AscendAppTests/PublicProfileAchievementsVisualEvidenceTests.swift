import Foundation
import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import AscendApp

/// Photographs the shipping public-profile achievements section in the three states a viewer can
/// land on, so a reviewer can see another climber's crown without running the app - and proves
/// each state off the presentation the section resolves, so a run that keeps no photographs
/// still holds the claim.
///
/// Drawn through a live `UIWindow` (`RenderedScreen`) rather than `ImageRenderer`: the badge
/// shelf is a horizontal `ScrollView`, and `ImageRenderer` draws its content as blank. The window
/// is brought up only when `ASCEND_EVIDENCE_DIR` is set, or when an assertion needs the laid-out
/// shelf.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct PublicProfileAchievementsVisualEvidenceTests {
    /// Three champion periods, two seconds, one third, and a long tail of ranked finishes.
    private static let champion = ProfileAchievementLadder(records: championRecords())

    /// One champion period, one third place, and a shorter tail - so every comparison row has
    /// two different numbers on it and the bar actually leans.
    private static let viewerChampion = ProfileAchievementLadder(
        records: [
            record(id: "viewer-champion-1", type: .weeklyTop1, rank: 1),
            record(id: "viewer-third-1", type: .monthlyTop3, rank: 3),
            record(id: "viewer-top-ten-1", type: .weeklyTop10, rank: 6),
            record(id: "viewer-top-ten-2", type: .weeklyTop10, rank: 9),
            record(id: "viewer-top-hundred-1", type: .weeklyTop100, rank: 44)
        ]
    )

    private static func championRecords() -> [ProfileAchievementRecord] {
        var records: [ProfileAchievementRecord] = []

        for index in 1...3 {
            records.append(record(id: "champion-\(index)", type: .weeklyTop1, rank: 1))
        }
        for index in 1...2 {
            records.append(record(id: "second-\(index)", type: .monthlyTop3, rank: 2))
        }
        records.append(record(id: "third-1", type: .weeklyTop3, rank: 3))
        for index in 1...6 {
            records.append(record(id: "top-ten-\(index)", type: .weeklyTop10, rank: 4 + index))
        }
        for index in 1...29 {
            records.append(
                record(id: "top-hundred-\(index)", type: .weeklyTop100, rank: 20 + index)
            )
        }

        return records
    }

    private static func record(
        id: String,
        type: ProfileAchievementType,
        rank: Int
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

    @Test
    func twoDecoratedClimbersSplitEveryBadgeRowLeftAndRight() async throws {
        let entries = try comparisonEntries(viewer: Self.viewerChampion, other: Self.champion)
        #expect(
            !entries.isEmpty && entries.allSatisfy { $0.viewerCount != nil && $0.otherCount != nil },
            "every row carries a known count on both sides: \(entries)"
        )

        try await Self.photographComparison(
            name: "public-profile-achievements-both-decorated",
            caption: "Both decorated: one row per badge, your count left, theirs right, lime/blue bar underneath",
            viewer: Self.viewerChampion,
            other: Self.champion,
            isOtherLoading: false
        )
    }

    /// The lopsided case, which is the normal one. A ghosted badge over a real `0` reads as a
    /// slot not yet filled; a blank half would read as a rendering failure and a dash would
    /// claim we did not know.
    @Test
    func aDecoratedViewerAgainstANewClimberGhostsTheirSide() async throws {
        let entries = try comparisonEntries(viewer: Self.champion, other: .empty)
        #expect(
            !entries.isEmpty && entries.allSatisfy { $0.otherCount == 0 },
            "the new climber's side is a real zero on every row, never a dash: \(entries)"
        )

        try await Self.photographComparison(
            name: "public-profile-achievements-viewer-decorated",
            caption: "Decorated viewer, brand-new climber: your badges still drawn, their side ghosted at a real 0",
            viewer: Self.champion,
            other: .empty,
            isOtherLoading: false
        )
    }

    @Test
    func aNewViewerAgainstADecoratedClimberGhostsTheViewersSide() async throws {
        let entries = try comparisonEntries(viewer: .empty, other: Self.champion)
        #expect(
            !entries.isEmpty && entries.allSatisfy { $0.viewerCount == 0 },
            "the new viewer's side is a real zero on every row, never a dash: \(entries)"
        )

        try await Self.photographComparison(
            name: "public-profile-achievements-other-decorated",
            caption: "Brand-new viewer, decorated climber: their badges attributed to the right, your side ghosted at 0",
            viewer: .empty,
            other: Self.champion,
            isOtherLoading: false
        )
    }

    /// A read that failed is not a climber with nothing. The unreadable side carries a dash,
    /// which is what a dash already means on every other row of this screen, and the bar sits in
    /// its dimmed neutral state because it cannot weigh a number nobody read.
    @Test
    func anUnreadableViewerLadderDashesTheViewersSide() async throws {
        let entries = try comparisonEntries(viewer: .unreadable, other: Self.champion)
        #expect(
            !entries.isEmpty && entries.allSatisfy { $0.viewerCount == nil },
            "an unreadable viewer ladder draws a dash on every row, never a zero: \(entries)"
        )

        try await Self.photographComparison(
            name: "public-profile-achievements-viewer-unreadable",
            caption: "Your ladder could not be read: your side is a dash, not a 0, and the bar stays neutral",
            viewer: .unreadable,
            other: Self.champion,
            isOtherLoading: false
        )
    }

    @Test
    func anUnreadableOtherLadderDashesTheOtherClimbersSide() async throws {
        let entries = try comparisonEntries(viewer: Self.champion, other: .unreadable)
        #expect(
            !entries.isEmpty && entries.allSatisfy { $0.otherCount == nil },
            "an unreadable other ladder draws a dash on every row, never a zero: \(entries)"
        )

        try await Self.photographComparison(
            name: "public-profile-achievements-other-unreadable",
            caption: "Their ladder could not be read: their side is a dash, your real counts stay drawn",
            viewer: Self.champion,
            other: .unreadable,
            isOtherLoading: false
        )
    }

    @Test
    func loadedProfileWithNoAchievementsShowsNoSection() async throws {
        #expect(
            Self.presentation(viewer: .empty, other: .empty, isOtherLoading: false) == .hidden,
            "two climbers with nothing to compare get no ACHIEVEMENTS section at all"
        )

        try await Self.photographComparison(
            name: "public-profile-achievements-loaded-empty",
            caption: "Neither climber holds a badge: no heading, no shell, the screen ends at ALL-TIME",
            viewer: .empty,
            other: .empty,
            isOtherLoading: false
        )
    }

    @Test
    func loadingProfileShowsNothingUntilTheCountsResolve() async throws {
        #expect(
            Self.presentation(viewer: Self.champion, other: Self.champion, isOtherLoading: true) == .hidden,
            "two decorated ladders still draw nothing while the other side is loading"
        )

        try await Self.photographComparison(
            name: "public-profile-achievements-loading",
            caption: "Snapshot still loading: no row drawn until both sides' counts resolve",
            viewer: Self.champion,
            other: Self.champion,
            isOtherLoading: true
        )
    }

    @Test
    func ownProfileShelfShowsFirstAscentsThenTheFullLadder() async throws {
        let held = [
            firstAscent(id: "eiffel", name: "Eiffel Tower"),
            firstAscent(id: "cn", name: "CN Tower")
        ]
        #expect(
            Self.shelfTokens(achievements: Self.champion, held: held).map(\.id)
                == ["first-ascents", "top1", "place2", "place3", "top10", "top100"]
        )

        try await Self.photographOwnShelf(
            name: "own-profile-achievements-full-ladder",
            caption: "Own profile, records loaded: First Ascents, CHAMPION, #2, #3, TOP 10, TOP 100",
            achievements: Self.champion,
            held: held
        )
    }

    @Test
    func ownProfileShelfWithoutRecordsShowsOnlyTheBandsItCanProve() async throws {
        let banded = ProfileAchievementLadder(
            bandedCounters: ProfileAchievementCounts(top1: 3, top3: 6, top10: 12, top100: 41)
        )
        #expect(
            Self.shelfTokens(achievements: banded, held: []).map(\.id) == ["top1", "top10", "top100"],
            "a banded ladder cannot prove a #2 or a #3, so neither badge is drawn"
        )

        try await Self.photographOwnShelf(
            name: "own-profile-achievements-banded-fallback",
            caption: "Records missing, banded counters only: no #2 and no #3, because neither can be proven",
            achievements: banded,
            held: []
        )
    }

    /// The shelf scrolls horizontally, so a phone-width photograph cuts the tail off. This one
    /// is drawn wide enough to hold all six badges at once, which is the only frame that shows
    /// the ladder's order end to end and that every badge, TOP 10 and TOP 100 included, now
    /// stands free as cut-out art with no tile and no stroke.
    ///
    /// Hosted whether or not a photograph is kept, at 1x: the claim is a layout fact, that every
    /// badge sits inside the wide window, which only the laid-out shelf can answer.
    @Test
    func theWholeOwnProfileLadderFitsInOneReviewableFrame() async throws {
        let held = [
            firstAscent(id: "eiffel", name: "Eiffel Tower"),
            firstAscent(id: "cn", name: "CN Tower")
        ]
        let content = Self.ownShelfContent(
            caption: "Own profile, whole shelf unscrolled: First Ascents · CHAMPION · #2 · #3 · TOP 10 · TOP 100, every badge free-standing",
            achievements: Self.champion,
            held: held,
            open: [],
            width: 680
        )
        let badges = Self.shelfTokens(achievements: Self.champion, held: held)
            .map { "\($0.accessibilityName), \($0.count)".lowercased() }

        try await Self.host(content, width: 680) { screen in
            let onScreen = try await screen.texts { texts in
                badges.allSatisfy { badge in texts.contains { $0.text.lowercased().contains(badge) } }
            }
            let missing = badges.filter { badge in
                !onScreen.contains { $0.text.lowercased().contains(badge) }
            }
            #expect(missing.isEmpty, "badges pushed outside the wide frame: \(missing)")

            try screen.photograph(named: "own-profile-achievements-full-ladder-wide")
        }
    }

    @Test
    func theWholeComparisonLadderFitsInOneReviewableFrame() async throws {
        let entries = try comparisonEntries(viewer: Self.viewerChampion, other: Self.champion)
        #expect(
            entries.map(\.id) == ["top1", "place2", "place3", "top10", "top100"],
            "the comparison ladder runs CHAMPION, #2, #3, TOP 10, TOP 100 with no TOP 3 row"
        )

        try await Self.photographComparison(
            name: "public-profile-achievements-full-ladder-wide",
            caption: "Whole comparison ladder: CHAMPION · #2 · #3 · TOP 10 · TOP 100, no TOP 3",
            viewer: Self.viewerChampion,
            other: Self.champion,
            isOtherLoading: false,
            width: 680
        )
    }

    /// The activation state stands the same cut-out flag beside its copy. It carries no circle
    /// clip and no stroke, because clipping a cut-out to a circle slices the flag off.
    @Test
    func theActivationStateStandsTheFirstAscentFlagFree() async throws {
        #expect(
            Self.shelfTokens(achievements: .empty, held: []).isEmpty,
            "nothing earned resolves to no badge, which is what puts the activation state up"
        )

        try await Self.photographOwnShelf(
            name: "own-profile-achievements-activation-empty",
            caption: "Nothing earned yet: the First Ascent flag stands free, no circle clip, no stroke",
            achievements: .empty,
            held: [],
            open: [firstAscent(id: "burj", name: "Burj Khalifa")]
        )
    }

    private func firstAscent(id: String, name: String) -> ProfileFirstAscentSummary {
        ProfileFirstAscentSummary(
            climbId: id,
            climbName: name,
            locationText: "Paris, France",
            tier: .gold,
            targetSteps: 1_665,
            kind: .held(claimedAt: Date(timeIntervalSince1970: 1_754_000_000))
        )
    }

    // MARK: - What the section resolves

    private static func presentation(
        viewer: ProfileAchievementLadder,
        other: ProfileAchievementLadder,
        isOtherLoading: Bool
    ) -> PublicProfileAchievementPresentation {
        PublicProfileAchievementPresentation(
            viewer: ProfileAchievementTally(ladder: viewer),
            other: ProfileAchievementTally(ladder: other),
            isOtherLoading: isOtherLoading
        )
    }

    /// The rows a loaded comparison draws, or a failure when it draws none.
    private func comparisonEntries(
        viewer: ProfileAchievementLadder,
        other: ProfileAchievementLadder
    ) throws -> [ProfileAchievementComparisonEntry] {
        guard case .visible(let entries) = Self.presentation(
            viewer: viewer,
            other: other,
            isOtherLoading: false
        ) else {
            throw EvidenceError.sectionHidden
        }
        return entries
    }

    /// The badges the own-profile shelf draws for this ladder, in shelf order.
    private static func shelfTokens(
        achievements: ProfileAchievementLadder,
        held: [ProfileFirstAscentSummary]
    ) -> [ProfilePrestigeToken] {
        ProfilePrestigeToken.tokens(
            for: ProfileAchievementTally(ladder: achievements, firstAscentsHeld: held.count),
            surface: .ownProfile
        )
    }

    private enum EvidenceError: Error {
        case sectionHidden
    }

    // MARK: - The photographs

    private static func photographOwnShelf(
        name: String,
        caption: String,
        achievements: ProfileAchievementLadder,
        held: [ProfileFirstAscentSummary],
        open: [ProfileFirstAscentSummary] = [],
        width: CGFloat = 402
    ) async throws {
        guard RenderedScreen.isPhotographing else { return }

        try await host(
            ownShelfContent(
                caption: caption,
                achievements: achievements,
                held: held,
                open: open,
                width: width
            ),
            width: width
        ) { screen in
            try screen.photograph(named: name)
        }
    }

    private static func photographComparison(
        name: String,
        caption: String,
        viewer: ProfileAchievementLadder = .empty,
        other: ProfileAchievementLadder,
        isOtherLoading: Bool,
        width: CGFloat = 402
    ) async throws {
        guard RenderedScreen.isPhotographing else { return }

        try await host(
            comparisonContent(
                caption: caption,
                viewer: viewer,
                other: other,
                isOtherLoading: isOtherLoading,
                width: width
            ),
            width: width
        ) { screen in
            try screen.photograph(named: name)
        }
    }

    private static func ownShelfContent(
        caption: String,
        achievements: ProfileAchievementLadder,
        held: [ProfileFirstAscentSummary],
        open: [ProfileFirstAscentSummary],
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ascendAccent)
                .fixedSize(horizontal: false, vertical: true)

            PrestigeSection(
                held: held,
                open: open,
                achievements: achievements,
                mode: .own,
                notificationState: ClimbDropNotificationState(
                    client: EvidenceNotificationStateClient(),
                    observesEnvironmentChanges: false
                )
            )
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .background(ProfileVisualStyle.background)
        .environment(\.colorScheme, .dark)
    }

    private static func comparisonContent(
        caption: String,
        viewer: ProfileAchievementLadder,
        other: ProfileAchievementLadder,
        isOtherLoading: Bool,
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ascendAccent)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 30) {
                ProfileComparisonSection(title: "PROFILE") {
                    Text("Age · Height · Weight · Best streak")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                }

                ProfileComparisonSection(title: "ALL-TIME") {
                    Text("Steps · Climbs · Duration · Avg steps/min")
                        .font(.montserratRegular(size: 13))
                        .foregroundStyle(ProfileVisualStyle.secondaryText)
                }

                PublicProfileAchievementsSection(
                    viewer: ProfileAchievementTally(ladder: viewer),
                    other: ProfileAchievementTally(ladder: other),
                    isOtherLoading: isOtherLoading
                )
            }
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .background(ProfileVisualStyle.background)
        .environment(\.colorScheme, .dark)
    }

    /// Hosts `content` in a window as tall as the content fits, so a photograph carries no
    /// empty band beneath the section.
    private static func host(
        _ content: some View,
        width: CGFloat,
        _ body: @MainActor (HostedScreen) async throws -> Void
    ) async throws {
        let controller = UIHostingController(rootView: content)
        controller.overrideUserInterfaceStyle = .dark
        let fitted = controller.sizeThatFits(
            in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        ).height
        let height = fitted.isFinite && fitted > 0 ? ceil(fitted) : 500

        try await RenderedScreen.host(
            controller,
            size: CGSize(width: width, height: height),
            body
        )
    }
}

/// Keeps the shelf's `.task` off the simulator's real notification centre and off the
/// process-wide shared state: this suite photographs badges, it does not test prompting.
@MainActor
private final class EvidenceNotificationStateClient: ClimbDropNotificationStateClient {
    let isPreferenceEnabled = true

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestDuringOnboarding() async -> UNAuthorizationStatus { .authorized }
    func enable() async -> UNAuthorizationStatus { .authorized }
    func disable() async -> UNAuthorizationStatus { .authorized }
    func openSystemNotificationSettings() {}
}
