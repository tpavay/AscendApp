import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The `.current` recomputed standing, and the bound on the diagnostic that
/// reports the finished-row reads it races beside.
///
/// The completion hero takes its noun from the basis on show, so a board that
/// says CLIMBERS has to have counted climbers. The frozen `.atCompletion` basis
/// counts whatever the board it sits beside counts; a recomputed standing counts
/// climbers on every board, because it counts finisher documents. This pins both
/// halves, since a summary preview that resolves before the server has ranked the
/// attempt renders through this arithmetic instead.
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

    /// Settled by the captain on 2026-09-02: a board with 41 finishes from 16
    /// climbers renders "6th of 16" where five distinct climbers beat the run -
    /// never "13th of 16", never "13th of 41". An open Just Climb carries no
    /// `isBestForUser` flag on any entry, so the field it ranks against is the
    /// finishers subcollection, which is one document per climber everywhere.
    @Test
    func anOpenJustClimbRecomputesAStandingOverClimbers() {
        let justClimb = LiveReplayLeaderboardContext.justClimbGlobal(targetSteps: 551)

        #expect(Repository.recomputedFieldPopulation(for: justClimb) == .climbers)
    }

    @Test(arguments: LiveReplayLeaderboardContextType.allCases)
    func theRecomputedPopulationIsTheOneTheHeroNames(
        type: LiveReplayLeaderboardContextType
    ) {
        // The invariant the field line asserts: the noun a `.current` standing
        // is labelled with and the population that standing counted resolve from
        // one property, so neither can drift into naming a population nothing
        // counted.
        let context = Self.context(for: type)

        #expect(
            Repository.recomputedFieldPopulation(for: context) ==
                type.recomputedFieldPopulation
        )
    }

    @Test(arguments: LiveReplayLeaderboardContextType.allCases)
    func aRecomputedStandingAlwaysCountsClimbers(
        type: LiveReplayLeaderboardContextType
    ) {
        #expect(type.recomputedFieldPopulation == .climbers)
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

    // MARK: - The open-board arithmetic counts climbers too

    /// The captain's example: 41 finishes from 16 climbers, five of whom beat
    /// this run. Both halves count the same people, so it reads "6th of 16".
    @Test
    func anOpenBoardRanksAgainstUniqueClimbersAtTheirBest() {
        let standing = Repository.climberStanding(
            betterClimberCount: 5,
            raceFieldCount: 16,
            climberAlreadyInField: true
        )

        #expect(standing.rank == 6)
        #expect(standing.completedCount == 16)
    }

    /// A count of rivals ahead has no negative value, so a standing built from
    /// one can never render "#0" - the placement nobody holds.
    @Test
    func aStandingNeverSeatsAClimberAheadOfFirst() {
        let standing = Repository.climberStanding(
            betterClimberCount: -1,
            raceFieldCount: 3,
            climberAlreadyInField: true
        )

        #expect(standing.rank == 1)
        #expect(standing.completedCount == 3)
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

    /// A climber who loses signal mid-climb fails every one of these reads, and
    /// none of that is a deployment fact. Reporting it spent the budget on
    /// noise, so the missing index that arrived later in the same session was
    /// the one occurrence that went unreported.
    @Test
    func losingSignalNeitherReportsNorSpendsTheBudget() {
        var diagnostics = LiveReplayFinishedRowDiagnostics()

        #expect(!diagnostics.shouldReport(.aheadFetch, failing: firestoreError(.unavailable)))
        #expect(!diagnostics.shouldReport(.aheadFetch, failing: firestoreError(.deadlineExceeded)))
        #expect(!diagnostics.shouldReport(.aheadFetch, failing: firestoreError(.cancelled)))
        #expect(!diagnostics.shouldReport(.aheadFetch, failing: CancellationError()))

        #expect(diagnostics.shouldReport(.aheadFetch, failing: firestoreError(.failedPrecondition)))
        #expect(!diagnostics.shouldReport(.aheadFetch, failing: firestoreError(.failedPrecondition)))
    }

    @Test
    func onlyFirestoreRefusingTheQueryIsADeploymentFailure() {
        #expect(LiveReplayFinishedRowDiagnostics.isDeploymentFailure(
            firestoreError(.failedPrecondition)
        ))
        #expect(!LiveReplayFinishedRowDiagnostics.isDeploymentFailure(
            firestoreError(.permissionDenied)
        ))
        // The same code in another domain is somebody else's precondition.
        #expect(!LiveReplayFinishedRowDiagnostics.isDeploymentFailure(
            NSError(domain: NSURLErrorDomain, code: FirestoreErrorCode.failedPrecondition.rawValue)
        ))
    }

    private func firestoreError(_ code: FirestoreErrorCode) -> NSError {
        NSError(domain: FirestoreErrorDomain, code: code.rawValue)
    }

    @Test
    func everyFinishedRowReadCarriesItsOwnCrashlyticsCode() {
        let codes = Set(LiveReplayFinishedRowRead.allCases.map(\.rawValue))

        #expect(codes.count == LiveReplayFinishedRowRead.allCases.count)
    }

    // MARK: - The ghost is withdrawn on the inequality the ahead reads apply

    /// The running half counts a row at its steps this bucket, so a ghost still
    /// on the course is withdrawn at exactly those steps: one place while it is
    /// level or ahead, none once the live attempt has passed it.
    @Test
    func aGhostStillOnTheCourseIsWithdrawnAtItsStepsThisBucket() {
        let running = ghost(stepsAtBucket: 400, finalSteps: 551)

        #expect(Repository.ghostAhead(running, currentSteps: 399) == 1)
        #expect(Repository.ghostAhead(running, currentSteps: 400) == 1)
        #expect(Repository.ghostAhead(running, currentSteps: 401) == 0)
    }

    /// The finished half counts a row already home at its final steps, and
    /// `holdingFinalSteps` is what carries a home ghost at that number - so it
    /// is withdrawn on the same value the aggregation counted it on, never on the
    /// handful of steps its bucket-zero row happens to hold.
    @Test
    func aGhostAlreadyHomeIsWithdrawnAtItsFinalSteps() {
        let home = ghost(stepsAtBucket: 12, finalSteps: 551)
            .holdingFinalSteps(currentSteps: 500)

        #expect(Repository.ghostAhead(home, currentSteps: 551) == 1)
        #expect(Repository.ghostAhead(home, currentSteps: 552) == 0)
        #expect(Repository.ghostAhead(ghost(stepsAtBucket: 12, finalSteps: 551), currentSteps: 500) == 0)
    }

    @Test
    func noGhostSubtractsNothing() {
        #expect(Repository.ghostAhead(nil, currentSteps: 0) == 0)
        #expect(Repository.ghostAhead(nil, currentSteps: 551) == 0)
    }

    // MARK: - Fixtures

    private func ghost(stepsAtBucket: Int, finalSteps: Int) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: "own-best",
            rank: nil,
            displayName: "You",
            avatarToken: "Y",
            photoURL: nil,
            stepsAtBucket: stepsAtBucket,
            finalSteps: finalSteps,
            deltaFromUser: 0,
            isCurrentUser: true,
            isPersonalBest: true,
            completionDurationSeconds: 600,
            userId: "user-a"
        )
    }

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
