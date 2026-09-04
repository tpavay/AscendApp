import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the completion summary's rank-first hierarchy.
///
/// These tests host the shipping `LiveClimbCompletionSummaryView` in a real
/// `UIWindow` through `RenderedScreen` and read the copy back off the
/// accessibility tree. Nothing is reproduced from source: the ordinal, the field
/// line and any board label all come from `LiveClimbSummaryRankHero` through the
/// view's own rank hero.
///
/// The standing is handed in through the view's caller-supplied slot, which is
/// the only rank source a test can drive - the frozen snapshot reaches the view
/// from `LiveClimbPublicResultSyncStore.shared`, a Firestore-backed singleton
/// with no injection point. Same `Basis`, same `standings` resolution, same
/// rendered `Text`, so the screen is the screen the climb surface produces.
/// The climb slot is left `nil` for the same reason, with the session's own
/// completion wording supplied through the override the live surfaces pass.
///
/// PNGs land in `ASCEND_EVIDENCE_DIR` when set and are not drawn otherwise.
@MainActor
@Suite(.hostsAWindow)
struct LiveClimbSummaryRankHeroRenderEvidenceTests {
    /// The captain's row, verified against staging: the frozen snapshot holds
    /// rank 1 / completedCount 1 from 2026-06-11.
    private static let frozenRank = 1
    private static let frozenTotal = 1

    /// What the same attempt computes against today's rows - the counterfactual
    /// run with the snapshot doc absent.
    private static let currentRank = 29
    private static let currentTotal = 50

    /// A standing measured against a field the hero can name states that ordering
    /// once, in plain language, with no label row repeating the ordinal in words.
    @Test
    func aStandingWithAFieldSizeStatesThatFieldInPlainLanguage() async throws {
        let fixedText = try await summaryCopy(
            basis: .atCompletion,
            rank: Self.frozenRank,
            total: Self.frozenTotal,
            moment: .retrospective,
            photographedAs: "live-climb-summary-rank-hero-fixed"
        )

        #expect(fixedText.contains("fastest of 1"))
        #expect(!fixedText.contains("climb rank"))
        #expect(!fixedText.contains("rank when you finished"))
        #expect(!fixedText.contains("current leaderboard rank"))

        // The model assertion pins the ordinal's value while the on-screen field line
        // verifies the denominator.
        #expect(renderedHero(basis: .atCompletion, rank: Self.frozenRank, total: Self.frozenTotal)?.standing?.rank == 1)
        #expect(renderedHero(basis: .atCompletion, rank: Self.frozenRank, total: Self.frozenTotal)?.total == 1)
    }

    /// A live session's population is its own race window, which the hero cannot
    /// characterise. Pairing that rank with a field ordering would assert a placement
    /// the screen cannot substantiate, so the session's own completion copy stands.
    @Test
    func aLiveSessionStandingNeverClaimsAFieldOrdering() async throws {
        let reportedText = try await summaryCopy(
            basis: .liveSession,
            rank: Self.frozenRank,
            total: Self.frozenTotal,
            moment: .retrospective,
            photographedAs: "live-climb-summary-rank-hero-reported"
        )

        #expect(reportedText.contains("live climb complete"))
        #expect(!reportedText.contains("fastest"))
        #expect(!reportedText.contains("most steps"))
    }

    /// The denominator is genuinely optional - a routine board with no window, a
    /// publish status that froze a rank without a count. A bare "FASTEST" under the
    /// ordinal would read as a claim to have won it, so the basis wording stands
    /// instead, in the tense the moment calls for.
    @Test
    func aStandingWithNoFieldSizeFallsBackToTheBasisWording() async throws {
        let freshText = try await summaryCopy(
            basis: .atCompletion,
            rank: 4,
            total: nil,
            moment: .freshCompletion,
            photographedAs: "live-climb-summary-rank-hero-fresh"
        )
        let savedText = try await summaryCopy(
            basis: .atCompletion,
            rank: 4,
            total: nil,
            moment: .retrospective,
            photographedAs: "live-climb-summary-rank-hero-no-field-size"
        )

        #expect(freshText.contains("rank you just earned"))
        #expect(!freshText.contains("fastest"))
        #expect(savedText.contains("rank when you finished"))
        #expect(!savedText.contains("fastest"))
    }

    /// A routine ranks on a board of its own, so it keeps the label that names it
    /// and the completion copy that describes its session.
    @Test
    func aRoutineStandingKeepsItsOwnBoardAndCompletionCopy() async throws {
        let text = try await summaryCopy(
            basis: .liveSession,
            rank: 3,
            total: 18,
            moment: .freshCompletion,
            labelOverride: "ROUTINE RANK",
            completedDetailOverride: "ROUTINE COMPLETE",
            photographedAs: "routine-summary-rank-hero"
        )

        #expect(text.contains("routine rank"))
        #expect(text.contains("routine complete"))
        #expect(text.contains("3rd"))
        #expect(!text.contains("fastest"))
    }

    /// The counterfactual the investigation ran against real staging rows: with
    /// the frozen snapshot absent the hero falls through to the recomputed rank,
    /// which agrees with the climb detail's 50 - and states that field plainly.
    ///
    /// Read by OCR, not off the tree: this test also holds that no "SUMMARY" heading
    /// is on the screen, and the header's back chevron publishes an accessibility
    /// label ("Close summary") that replaces its visible glyph, so the tree cannot
    /// answer what the climber sees.
    @Test
    func aRecomputedStandingStatesItsFieldWithoutJargon() async throws {
        let currentText = try await RenderedScreen.host(
            summary(
                basis: .current,
                rank: Self.currentRank,
                total: Self.currentTotal,
                moment: .retrospective
            ),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.recognizedText(scale: 3)
            try screen.photograph(named: "live-climb-summary-rank-hero-current")
            return text
        }

        #expect(currentText.contains("29th"))
        #expect(currentText.contains("fastest of 50"))
        #expect(!currentText.contains("current leaderboard rank"))
        #expect(!currentText.contains("climb rank"))
        #expect(renderedHero(basis: .current, rank: Self.currentRank, total: Self.currentTotal)?.total == 50)

        #expect(currentText.contains("cn tower live climb"))
        #expect(!currentText.contains("summary"))
        #expect(appearsBefore("29th", "total steps", in: currentText))
        #expect(currentText.contains("81 avg spm"))
        #expect(!currentText.contains("avg 81 spm"))
        #expect(occurrenceCount(of: "avg spm", in: currentText) == 1)
        #expect(appearsBefore("share", "done", in: currentText))
    }

    /// One set a reviewer can read end to end: the frozen standing that can name
    /// its field, the live session that cannot, the standing with no denominator,
    /// and the recomputed standing that agrees with climb detail - each screen
    /// photographed whole when `ASCEND_EVIDENCE_DIR` is set. The proof is that the
    /// four bases resolve to four different heroes, which is what makes them worth
    /// reading side by side.
    @Test
    func proofSheetShowsEveryHeroBasisSideBySide() async throws {
        let panels: [(name: String, basis: LiveClimbSummaryRankHero.Basis, rank: Int, total: Int?, moment: LiveClimbSummaryRankHero.Moment)] = [
            ("live-climb-summary-rank-hero-proof-1-saved-summary", .atCompletion, Self.frozenRank, Self.frozenTotal, .retrospective),
            ("live-climb-summary-rank-hero-proof-2-session-standing", .liveSession, Self.frozenRank, Self.frozenTotal, .retrospective),
            ("live-climb-summary-rank-hero-proof-3-no-field-size", .atCompletion, 4, nil, .freshCompletion),
            ("live-climb-summary-rank-hero-proof-4-current-standing", .current, Self.currentRank, Self.currentTotal, .retrospective)
        ]

        let heroes = panels.map { panel in
            renderedHero(basis: panel.basis, rank: panel.rank, total: panel.total, moment: panel.moment)
        }
        let renderings = Set(heroes.map { hero in
            "\(hero?.label ?? "")|\(hero?.detail ?? "")|\(String(describing: hero?.value))"
        })
        #expect(renderings.count == panels.count, "two bases resolved to the same hero: \(heroes)")

        guard RenderedScreen.isPhotographing else { return }
        for panel in panels {
            try await RenderedScreen.host(
                summary(basis: panel.basis, rank: panel.rank, total: panel.total, moment: panel.moment),
                size: Self.screenSize
            ) { screen in
                try screen.photograph(named: panel.name)
            }
        }
    }

    @Test
    func aSettledRankWithoutAStandingKeepsTheUnresolvedStateVisible() async throws {
        let hero = try #require(
            LiveClimbSummaryRankHero.make(
                isClimbContext: true,
                standings: [],
                sync: LiveClimbSummaryRankHero.SyncState(
                    phase: nil,
                    hasRankContext: true,
                    rankResolution: .settled
                ),
                copy: LiveClimbSummaryRankHero.Copy()
            )
        )
        let text = try await RenderedScreen.host(
            LiveClimbSummaryRankHeroView(
                hero: hero,
                rankingMetric: .fastestCompletion,
                fieldPopulation: .climbers,
                onRetrySync: {}
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()
            try screen.photograph(named: "live-climb-summary-rank-unresolved")
            return text
        }

        #expect(text.contains("check leaderboard later"))
        #expect(!text.contains("climb rank"))
        #expect(!text.contains("fastest"))
    }

    @Test
    func aStepsBasedStandingNamesTheBasisThatActuallyRanksIt() async throws {
        let hero = try #require(
            LiveClimbSummaryRankHero.make(
                isClimbContext: false,
                standings: [
                    LiveClimbSummaryRankHero.Standing(rank: 3, total: 18, basis: .current)
                ],
                sync: LiveClimbSummaryRankHero.SyncState(
                    phase: nil,
                    hasRankContext: true,
                    rankResolution: .settled
                ),
                copy: LiveClimbSummaryRankHero.Copy()
            )
        )
        let text = try await RenderedScreen.host(
            LiveClimbSummaryRankHeroView(
                hero: hero,
                rankingMetric: .mostSteps,
                fieldPopulation: .climbers,
                onRetrySync: {}
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy()
            try screen.photograph(named: "routine-summary-rank-most-steps")
            return text
        }

        #expect(text.contains("3rd"))
        #expect(text.contains("most steps of 18"))
        #expect(!text.contains("fastest"))
    }

    // MARK: - Hosting the shipping screen

    private func summary(
        basis: LiveClimbSummaryRankHero.Basis,
        rank: Int,
        total: Int?,
        moment: LiveClimbSummaryRankHero.Moment,
        labelOverride: String? = nil,
        completedDetailOverride: String? = "LIVE CLIMB COMPLETE"
    ) throws -> some View {
        let container = try makeContainer()
        let workout = makeWorkout()

        return LiveClimbCompletionSummaryView(
            climb: nil,
            workout: workout,
            leaderboardRank: rank,
            leaderboardTotal: total,
            leaderboardRankBasis: basis,
            // The hero only renders where there is a population to rank against, so the
            // screen needs a context even though the standing is handed in directly.
            leaderboardContext: .justClimbGlobal(targetSteps: 2_579),
            moment: moment,
            rankingLabelOverride: labelOverride,
            completedDetailOverride: completedDetailOverride,
            onDone: { _ in }
        )
        .modelContainer(container)
    }

    /// The summary's on-screen copy, lowercased, off the accessibility tree - and the
    /// screen photographed under `name` when this run keeps evidence.
    private func summaryCopy(
        basis: LiveClimbSummaryRankHero.Basis,
        rank: Int,
        total: Int?,
        moment: LiveClimbSummaryRankHero.Moment,
        labelOverride: String? = nil,
        completedDetailOverride: String? = "LIVE CLIMB COMPLETE",
        photographedAs name: String
    ) async throws -> String {
        try await RenderedScreen.host(
            summary(
                basis: basis,
                rank: rank,
                total: total,
                moment: moment,
                labelOverride: labelOverride,
                completedDetailOverride: completedDetailOverride
            ),
            size: Self.screenSize
        ) { screen in
            let text = try await screen.copy { $0.contains("done") }
            try screen.photograph(named: name)
            return text
        }
    }

    private static let screenSize = CGSize(width: 393, height: 852)

    /// The hero the hosted screen resolves for the same inputs, for the parts of it
    /// a test pins as a value rather than as copy.
    private func renderedHero(
        basis: LiveClimbSummaryRankHero.Basis,
        rank: Int,
        total: Int?,
        moment: LiveClimbSummaryRankHero.Moment = .retrospective
    ) -> LiveClimbSummaryRankHero? {
        let sources = LiveClimbSummaryRankHero.Sources(
            callerSupplied: LiveClimbSummaryRankHero.Standing(rank: rank, total: total, basis: basis)
        )

        return LiveClimbSummaryRankHero.make(
            isClimbContext: false,
            moment: moment,
            standings: LiveClimbSummaryRankHero.standings(isClimbContext: false, sources: sources),
            sync: LiveClimbSummaryRankHero.SyncState(
                phase: nil,
                hasRankContext: true,
                rankResolution: .settled
            ),
            copy: LiveClimbSummaryRankHero.Copy()
        )
    }

    // MARK: - Fixtures

    /// A CN Tower-shaped Live Climb: 144 floors, 2,579 steps, finished in 31:48.
    private func makeWorkout() -> Workout {
        Workout(
            name: "CN Tower Live Climb",
            duration: 1_908,
            steps: 2_579,
            floors: 144,
            caloriesBurned: 486,
            source: .headphoneMotion
        )
    }

    /// Held for the process, not per render. The summary carries a `@Query`, and SwiftUI keeps
    /// observing SwiftData for a beat after the host is torn down - against a container that has
    /// already gone, that observer traps on the next save any other suite performs.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        ClimbAttempt.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    private func makeContainer() throws -> ModelContainer {
        try #require(Self.container, "The evidence suite needs an in-memory model container")
    }

    // MARK: - Reading the copy

    private func appearsBefore(_ first: String, _ second: String, in text: String) -> Bool {
        guard let firstRange = text.range(of: first), let secondRange = text.range(of: second) else {
            return false
        }
        return firstRange.lowerBound < secondRange.lowerBound
    }

    private func occurrenceCount(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
