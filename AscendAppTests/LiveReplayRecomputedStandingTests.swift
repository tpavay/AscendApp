import Foundation
import Testing
@testable import AscendApp

/// The `.current` recomputed standing, and the bound on the diagnostic that
/// reports the finished-row reads it races beside.
///
/// The completion hero takes its noun from `collapsesRepeatFinishers`, so a
/// board that says CLIMBERS has to have counted climbers. The frozen `.atCompletion`
/// basis has done that since the captain settled it on 2026-08-29; this pins the
/// other basis to the same rule, because a summary preview that resolves before
/// the server has ranked the attempt renders through this arithmetic instead.
struct LiveReplayRecomputedStandingTests {
    private typealias Repository = FirestoreLiveReplayLeaderboardRepository

    // MARK: - Which population a recomputed standing counts

    @Test
    func aCollapsingBoardRecomputesAStandingOverClimbers() {
        let climb = LiveReplayLeaderboardContext.liveClimb(
            climbId: "st-peters-basilica",
            targetSteps: 551
        )

        #expect(Repository.recomputedFieldPopulation(for: climb) == .climbers)
    }

    @Test
    func anOpenJustClimbRecomputesAStandingOverCompletions() {
        let justClimb = LiveReplayLeaderboardContext.justClimbGlobal(targetSteps: 551)

        #expect(Repository.recomputedFieldPopulation(for: justClimb) == .completions)
    }

    @Test(arguments: LiveReplayLeaderboardContextType.allCases)
    func theRecomputedPopulationIsTheOneTheHeroNames(
        type: LiveReplayLeaderboardContextType
    ) {
        // The invariant the field line asserts, held across both bases: the noun
        // and the recomputed count resolve from one predicate, so neither can
        // drift into naming a population nothing counted.
        let context = Self.context(for: type)

        #expect(Repository.recomputedFieldPopulation(for: context) == type.fieldPopulation)
    }

    // MARK: - The climbers arithmetic

    @Test
    func aRepeatClimberIsOneRowInTheFieldTheyAreRankedAgainst() {
        // Two rivals ahead on their own bests, the climber already standing in
        // the field: third of three people, not of however many runs they took.
        let standing = Repository.climberStanding(
            betterClimberCount: 2,
            raceFieldCount: 3,
            climberAlreadyInField: true
        )

        #expect(standing.rank == 3)
        #expect(standing.completedCount == 3)
    }

    @Test
    func aFirstTimeClimberJoinsTheFieldTheyAreRankedAgainst() {
        let standing = Repository.climberStanding(
            betterClimberCount: 2,
            raceFieldCount: 2,
            climberAlreadyInField: false
        )

        #expect(standing.rank == 3)
        #expect(standing.completedCount == 3)
    }

    @Test
    func climbersTiedOnTheMetricShareARank() {
        let standing = Repository.climberStanding(
            betterClimberCount: 0,
            raceFieldCount: 3,
            climberAlreadyInField: true
        )

        #expect(standing.rank == 1)
        #expect(standing.completedCount == 3)
    }

    // MARK: - Which time a climber's rank is computed on

    /// Settled by the captain on 2026-09-01: "You use the time from the given
    /// climb for the rank. You don't use the all-time best for the rank."
    ///
    /// Every completion summary is a permanent record of the climb it sits on,
    /// so a 9:40 shows the rank a 9:40 earned and an 8:12 shows the rank an 8:12
    /// earned on the day it landed. Ranking a repeat on its climber's all-time
    /// best instead reads as generous and is worse than the bug it looks like a
    /// fix for: it tells a climber their slower run came first on a board where
    /// somebody beat that run.
    @Test
    func aRepeatIsRankedOnTheTimeItJustPostedAndNotOnItsClimbersBest() {
        // The captain's St Peter's pair - 346.66s banked, 399.22s publishing now
        // - on a board where one rival holds 370s. Counting best-per-user rows
        // ahead of the 399.22 finds both the rival and the climber's own row.
        let betterClimberRows = 2
        let ownLeadingRows = Repository.ownLeadingRowCount(
            metric: .fastestCompletion,
            storedBest: 346.66,
            attemptRankingValue: 399.22
        )

        let standing = Repository.climberStanding(
            betterClimberCount: betterClimberRows - ownLeadingRows,
            raceFieldCount: 2,
            climberAlreadyInField: true
        )

        // Second, because a 399.22 loses to the rival's 370 - not first, which
        // is what ranking on the banked 346.66 would have claimed.
        #expect(standing.rank == 2)
        #expect(standing.completedCount == 2)
    }

    /// A board showing one row per climber must never seat a climber behind
    /// themselves, which is the whole job of removing their own leading row.
    @Test
    func aClimbersOwnLeadingRowIsNotCountedAgainstThem() {
        #expect(
            Repository.ownLeadingRowCount(
                metric: .fastestCompletion,
                storedBest: 346.66,
                attemptRankingValue: 399.22
            ) == 1
        )
    }

    @Test
    func aFasterRepeatHasNoLeadingRowToRemove() {
        #expect(
            Repository.ownLeadingRowCount(
                metric: .fastestCompletion,
                storedBest: 399.22,
                attemptRankingValue: 346.66
            ) == 0
        )
    }

    @Test
    func aRoutineClimberLeadsOnTheTallerRun() {
        // A routine fixes the clock, so more steps is better in both directions.
        #expect(
            Repository.ownLeadingRowCount(
                metric: .mostSteps,
                storedBest: 1_900,
                attemptRankingValue: 1_840
            ) == 1
        )
        #expect(
            Repository.ownLeadingRowCount(
                metric: .mostSteps,
                storedBest: 1_840,
                attemptRankingValue: 1_900
            ) == 0
        )
    }

    @Test
    func aFirstTimeClimberHasNoRowToRemove() {
        #expect(
            Repository.ownLeadingRowCount(
                metric: .fastestCompletion,
                storedBest: nil,
                attemptRankingValue: 399.22
            ) == 0
        )
    }

    // MARK: - The attempts arithmetic stays as it was

    @Test
    func anOpenBoardStillCountsEveryAttemptAsItsOwnOpponent() {
        let standing = Repository.attemptStanding(
            betterAttemptCount: 5,
            publishedCount: 5,
            attemptAlreadyPublished: false
        )

        #expect(standing.rank == 6)
        #expect(standing.completedCount == 6)
    }

    @Test
    func aRepublishedAttemptIsAlreadyOneOfTheAttemptsCounted() {
        let standing = Repository.attemptStanding(
            betterAttemptCount: 5,
            publishedCount: 6,
            attemptAlreadyPublished: true
        )

        #expect(standing.rank == 6)
        #expect(standing.completedCount == 6)
    }

    // MARK: - The finished-row diagnostic bound

    @Test
    func eachFinishedRowReadReportsOnceAndThenStaysQuiet() {
        // fetchWindow runs on a ~10s bucket clock and can be forced far more
        // often during a race. A missing composite index is a deployment fact,
        // not an event, so the second report carries nothing the first did not -
        // and unbounded recordError is the Fatal App Hang hazard.
        var diagnostics = LiveReplayFinishedRowDiagnostics()
        let reports = (0..<3).map { _ in diagnostics.shouldReport(.aheadFetch) }

        #expect(reports == [true, false, false])
    }

    @Test
    func eachFinishedRowReadIsBoundedSeparately() {
        var diagnostics = LiveReplayFinishedRowDiagnostics()
        let firstPass = LiveReplayFinishedRowRead.allCases.map {
            diagnostics.shouldReport($0)
        }
        let secondPass = LiveReplayFinishedRowRead.allCases.map {
            diagnostics.shouldReport($0)
        }

        #expect(firstPass.allSatisfy { $0 })
        #expect(secondPass.allSatisfy { !$0 })
    }

    @Test
    func everyFinishedRowReadCarriesItsOwnCrashlyticsCode() {
        let codes = Set(LiveReplayFinishedRowRead.allCases.map(\.rawValue))

        #expect(codes.count == LiveReplayFinishedRowRead.allCases.count)
    }

    // MARK: - Fixtures

    private static func context(
        for type: LiveReplayLeaderboardContextType
    ) -> LiveReplayLeaderboardContext {
        switch type {
        case .liveClimb:
            return .liveClimb(climbId: "st-peters-basilica", targetSteps: 551)
        case .justClimb:
            return .justClimbGlobal(targetSteps: 551)
        case .routineTemplate:
            return .routineTemplate(
                templateId: "social-pyramid-20",
                targetSteps: 1_900
            )
        case .routine:
            return .routine(
                routineId: UUID(uuidString: "6E1B0C1E-0E1A-4E5B-9C2E-0C6F0B7A1D22")!,
                targetSteps: 1_900
            )
        }
    }
}
