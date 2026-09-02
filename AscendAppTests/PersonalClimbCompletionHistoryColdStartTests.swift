import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// What the finish card is allowed to claim on a device that has only just been
/// handed the climber's history.
///
/// Both regressions this suite pins reproduce ONLY after a reinstall or on a
/// fresh device, which is why every other suite missed them.
/// `ClimbCompletionRepository.reconcile` rebuilds a tower whose workouts could
/// not be restored as ONE `ClimbAttempt` carrying the aggregate in
/// `sessionsCount`, only `bestWorkoutId` in `appliedWorkoutIds`, only the best
/// duration, and no `globalCompletionOrder` at all. On that row the gold
/// `FIRST ASCENT CLAIMED` card rendered for every run on the tower, and a
/// climber's slowest run ever was announced as a flattering middle ordinal.
///
/// The rule both answer to: a claim needs evidence, and where the evidence runs
/// out the card withholds or takes last - never the number that flatters.
@MainActor
struct PersonalClimbCompletionHistoryColdStartTests {
    typealias Hero = LiveClimbSummaryRankHero

    private let climbId = "st-peters-basilica"
    private let restoredAt = Date(timeIntervalSince1970: 1_777_000_000)

    // MARK: - The collapsed history

    /// The reconciled stand-in says so, rather than passing itself off as the
    /// whole history.
    @Test
    func aReconciledStandInReportsPartialEvidence() throws {
        let context = try makeModelContext()
        context.insert(collapsedAttempt(completions: 6, bestDurationSeconds: 492))

        let history = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: UUID(),
                completedAt: restoredAt.addingTimeInterval(90_000),
                modelContext: context
            )
        )

        #expect(history.durationEvidence == .partial)
        #expect(history.otherCompletionsCount == 5)
    }

    /// No run on that tower may claim the First Ascent from a collapsed history:
    /// the device cannot say which one came first, and it was never told the
    /// finisher order. It rendered the gold card on all six.
    @Test
    func noRunOnACollapsedTowerClaimsTheFirstAscent() throws {
        let context = try makeModelContext()
        context.insert(collapsedAttempt(completions: 6, bestDurationSeconds: 492))

        for dayOffset in 0..<6 {
            let history = try #require(
                ClimbService.shared.personalCompletionHistory(
                    forClimbId: climbId,
                    workoutId: UUID(),
                    completedAt: restoredAt.addingTimeInterval(Double(dayOffset) * 86_400),
                    modelContext: context
                )
            )

            #expect(history.isEarliestCompletionHere == false)
            #expect(history.claimsFirstAscent == false)
        }
    }

    /// The card that would have rendered. A field of one climber with the claim
    /// unproven withholds - it does not fall through to the gold flag, and it
    /// does not fall through to `1st of your 1 climb` either.
    @Test
    func aCollapsedTowerRendersNoGoldCard() throws {
        let context = try makeModelContext()
        context.insert(collapsedAttempt(completions: 6, bestDurationSeconds: 492))

        let history = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: UUID(),
                completedAt: restoredAt.addingTimeInterval(90_000),
                modelContext: context
            )
        )
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(
                durationSeconds: 580,
                otherCompletions: history
            ),
            claimsFirstAscent: history.claimsFirstAscent,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value != .firstAscent)
        #expect(hero.detail != Hero.firstAscentDetail)
    }

    /// The slowest run ever, on a tower this device holds only a stand-in for.
    /// It used to read `2ND OF YOUR 6 CLIMBS`.
    @Test
    func aSlowestEverRunOnACollapsedTowerRendersLast() throws {
        let context = try makeModelContext()
        context.insert(collapsedAttempt(completions: 6, bestDurationSeconds: 492))

        let history = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: UUID(),
                completedAt: restoredAt.addingTimeInterval(90_000),
                modelContext: context
            )
        )
        let placing = try #require(
            PersonalClimbPlacing(durationSeconds: 840, otherCompletions: history)
        )

        #expect(placing.total == 6)
        #expect(placing.ordinal == 6)
        #expect(placing.achievementTitle == "6TH OF YOUR 6 CLIMBS")
    }

    /// The other end of the same rule: beating the one duration the stand-in
    /// kept is provable, so the personal best is still stated.
    @Test
    func aProvablePersonalBestOnACollapsedTowerStillRendersFirst() throws {
        let context = try makeModelContext()
        context.insert(collapsedAttempt(completions: 6, bestDurationSeconds: 492))

        let history = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: UUID(),
                completedAt: restoredAt.addingTimeInterval(90_000),
                modelContext: context
            )
        )
        let placing = try #require(
            PersonalClimbPlacing(durationSeconds: 460, otherCompletions: history)
        )

        #expect(placing.ordinal == 1)
        #expect(placing.total == 6)
    }

    // MARK: - Workouts that did restore

    /// The normal restored path. `WorkoutHydrationService` rebuilds one attempt
    /// per restored live-climb workout, each carrying its own duration and date,
    /// so the evidence is complete and the ordinal is exact again.
    @Test
    func restoredWorkoutsRebuildCompleteEvidence() throws {
        let context = try makeModelContext()
        let placedWorkoutId = UUID()
        let placedCompletedAt = restoredAt.addingTimeInterval(3 * 86_400)
        context.insert(restoredAttempt(
            workoutId: UUID(),
            durationSeconds: 492,
            completedAt: restoredAt
        ))
        context.insert(restoredAttempt(
            workoutId: UUID(),
            durationSeconds: 640,
            completedAt: restoredAt.addingTimeInterval(86_400)
        ))
        context.insert(restoredAttempt(
            workoutId: placedWorkoutId,
            durationSeconds: 580,
            completedAt: placedCompletedAt
        ))

        let history = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: placedWorkoutId,
                completedAt: placedCompletedAt,
                modelContext: context
            )
        )
        let placing = try #require(
            PersonalClimbPlacing(durationSeconds: 580, otherCompletions: history)
        )

        #expect(history.durationEvidence == .complete)
        #expect(history.isEarliestCompletionHere == false)
        #expect(placing.ordinal == 2)
        #expect(placing.total == 3)
    }

    /// A First Ascent survives the restore, but only on the run that earned it,
    /// and only where the finisher order came with it.
    @Test
    func aRestoredFirstAscentIsClaimedByTheEarliestRunAlone() throws {
        let context = try makeModelContext()
        let firstWorkoutId = UUID()
        let laterWorkoutId = UUID()
        let firstCompletedAt = restoredAt
        let laterCompletedAt = restoredAt.addingTimeInterval(86_400)

        let first = restoredAttempt(
            workoutId: firstWorkoutId,
            durationSeconds: 492,
            completedAt: firstCompletedAt
        )
        first.globalCompletionOrder = 1
        let later = restoredAttempt(
            workoutId: laterWorkoutId,
            durationSeconds: 580,
            completedAt: laterCompletedAt
        )
        later.globalCompletionOrder = 1
        context.insert(first)
        context.insert(later)

        let earliest = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: firstWorkoutId,
                completedAt: firstCompletedAt,
                modelContext: context
            )
        )
        let repeatRun = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: laterWorkoutId,
                completedAt: laterCompletedAt,
                modelContext: context
            )
        )

        #expect(earliest.claimsFirstAscent)
        #expect(repeatRun.claimsFirstAscent == false)
    }

    /// A finisher order this device was never told is not evidence of holding
    /// one. The claim is permanent and unreclaimable, so it withholds.
    @Test
    func anUnknownFinisherOrderWithholdsTheClaim() throws {
        let context = try makeModelContext()
        let workoutId = UUID()
        context.insert(restoredAttempt(
            workoutId: workoutId,
            durationSeconds: 492,
            completedAt: restoredAt
        ))

        let history = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: workoutId,
                completedAt: restoredAt,
                modelContext: context
            )
        )

        #expect(history.isEarliestCompletionHere)
        #expect(history.globalCompletionOrder == nil)
        #expect(history.claimsFirstAscent == false)
    }

    // MARK: - Nothing to assert from

    /// A history that could not resolve leaves the hero waiting. It used to
    /// settle on `1st / OF YOUR 1 CLIMB`, the one placing the design spends on
    /// the flag instead.
    @Test
    func anUnresolvedHistoryMakesTheHeroWaitRatherThanAssert() throws {
        let pending = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: nil,
            claimsFirstAscent: false,
            sync: Hero.SyncState(
                phase: .published,
                hasRankContext: true,
                rankResolution: .resolving
            ),
            copy: Hero.Copy()
        ))
        let settled = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: nil,
            claimsFirstAscent: false,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(pending.value == .loading)
        #expect(settled.value == .unranked)
        #expect(settled.value != .rank(1))

        // A blank slot is honest; sending a climber alone on a tower to check a
        // leaderboard containing only them is not.
        #expect(pending.detail == Hero.soloResolvingDetail)
        #expect(settled.detail == Hero.soloUnverifiedDetail)
        #expect(settled.detail != "CHECK LEADERBOARD LATER")
        #expect(pending.detail != "LOOKING FOR YOUR RANK")
    }

    /// The zero-evidence end of the same rule, all the way through: a rebuilt row
    /// whose duration the projection never carried places nobody, and the card it
    /// produces says the one thing that is true rather than naming a leaderboard.
    @Test
    func aCollapsedTowerWithNoDurationWithholdsThePlacingAndTheLeaderboardCopy() throws {
        let context = try makeModelContext()
        context.insert(collapsedAttempt(completions: 3, bestDurationSeconds: 0))

        let history = try #require(
            ClimbService.shared.personalCompletionHistory(
                forClimbId: climbId,
                workoutId: UUID(),
                completedAt: restoredAt.addingTimeInterval(90_000),
                modelContext: context
            )
        )
        let placing = PersonalClimbPlacing(durationSeconds: 580, otherCompletions: history)
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: placing,
            claimsFirstAscent: history.claimsFirstAscent,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(history.durationEvidence == .partial)
        #expect(placing == nil)
        #expect(hero.value == .unranked)
        #expect(hero.detail == Hero.soloUnverifiedDetail)
        #expect(hero.detail != "CHECK LEADERBOARD LATER")
    }

    /// The same refusal when a placing exists but counts only this one climb: a
    /// field of one of the climber's own climbs is the flag's slot, so an
    /// unproven claim withholds instead of writing `1st of your 1 climb` into it.
    @Test
    func aLoneClimbWithNoProvenClaimNeverRendersFirstOfOne() throws {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            standings: [Hero.Standing(rank: 1, total: 1, basis: .atCompletion)],
            personalPlacing: PersonalClimbPlacing(ordinal: 1, total: 1),
            claimsFirstAscent: false,
            sync: publishedSync(),
            copy: Hero.Copy()
        ))

        #expect(hero.value == .unranked)
        #expect(hero.detail != "OF YOUR 1 CLIMB")
        #expect(hero.detail == Hero.soloUnverifiedDetail)
        #expect(hero.detail != "CHECK LEADERBOARD LATER")
    }

    // MARK: - Helpers

    /// The row `ClimbCompletionRepository.reconcile` materialises: the aggregate
    /// count in `sessionsCount`, the best workout alone in `appliedWorkoutIds`,
    /// the best duration, and no finisher order.
    private func collapsedAttempt(
        completions: Int,
        bestDurationSeconds: Int
    ) -> ClimbAttempt {
        ClimbAttempt(
            climbId: climbId,
            status: .completed,
            startedAt: restoredAt,
            endedAt: restoredAt.addingTimeInterval(Double(completions) * 86_400),
            completedAt: restoredAt,
            accumulatedSteps: 0,
            accumulatedDurationSeconds: bestDurationSeconds,
            sessionsCount: completions,
            appliedWorkoutIds: [UUID().uuidString],
            bestCompletionDurationSeconds: bestDurationSeconds
        )
    }

    /// The row `WorkoutHydrationService.restoreLiveClimbAttemptIfNeeded` rebuilds
    /// from a restored workout: one completion, named, with its own duration.
    private func restoredAttempt(
        workoutId: UUID,
        durationSeconds: Int,
        completedAt: Date
    ) -> ClimbAttempt {
        ClimbAttempt(
            climbId: climbId,
            status: .completed,
            startedAt: completedAt.addingTimeInterval(-Double(durationSeconds)),
            endedAt: completedAt,
            completedAt: completedAt,
            accumulatedSteps: 551,
            accumulatedDurationSeconds: durationSeconds,
            sessionsCount: 1,
            appliedWorkoutIds: [workoutId.uuidString],
            bestCompletionDurationSeconds: durationSeconds
        )
    }

    private func publishedSync() -> Hero.SyncState {
        Hero.SyncState(
            phase: .published,
            hasRankContext: true,
            rankResolution: .settled
        )
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ClimbAttempt.self,
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
