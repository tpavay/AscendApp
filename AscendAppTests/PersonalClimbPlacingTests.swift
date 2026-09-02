import Foundation
import Testing
@testable import AscendApp

/// The ordinal that replaced `1st of 1 CLIMBER`.
///
/// The defect it exists to make impossible: a number that could not fall. "1st of
/// 1" was invariant across 8:12, 9:40 and 14:00 alike, so a repeat that went
/// slower was congratulated by the very screen holding the evidence. A placing
/// among the climber's own climbs answers the same question and *responds* -
/// which also collapses the personal-best state into it, because first of your
/// own climbs is a personal best.
struct PersonalClimbPlacingTests {
    /// The captain's St. Peter's case, in one assertion: five climbs on the
    /// tower, today's run second-fastest, so the hero can no longer say first.
    @Test
    func aSlowerRepeatPlacesBehindTheClimbersOwnFasterRuns() throws {
        let placing = try #require(
            PersonalClimbPlacing(
                durationSeconds: 580,
                otherCompletionDurationsSeconds: [492, 599, 640, 705]
            )
        )

        #expect(placing.ordinal == 2)
        #expect(placing.total == 5)
        #expect(placing.fieldLabel == "OF YOUR 5 CLIMBS")
        #expect(placing.achievementTitle == "2ND OF YOUR 5 CLIMBS")
    }

    /// Every earlier run was slower, so this one leads - and that *is* the
    /// personal-best state. There is no separate personal-best hero to build.
    @Test
    func theFastestRunLeadsTheClimbersOwnFieldAndThatIsThePersonalBest() throws {
        let placing = try #require(
            PersonalClimbPlacing(
                durationSeconds: 472,
                otherCompletionDurationsSeconds: [492, 580, 640]
            )
        )

        #expect(placing.ordinal == 1)
        #expect(placing.total == 4)
        #expect(placing.fieldLabel == "OF YOUR 4 CLIMBS")
    }

    /// The proof that the old number could not fall and this one can: the same
    /// climber, the same tower, three runs, three different heroes.
    @Test
    func theOrdinalRespondsToPerformanceWhereAFieldOfOneCouldNot() throws {
        let earlier = [492]

        let faster = try #require(
            PersonalClimbPlacing(durationSeconds: 460, otherCompletionDurationsSeconds: earlier)
        )
        let slower = try #require(
            PersonalClimbPlacing(durationSeconds: 580, otherCompletionDurationsSeconds: earlier)
        )
        let muchSlower = try #require(
            PersonalClimbPlacing(
                durationSeconds: 840,
                otherCompletionDurationsSeconds: earlier + [580]
            )
        )

        #expect(faster.ordinal == 1)
        #expect(slower.ordinal == 2)
        #expect(muchSlower.ordinal == 3)
    }

    /// A first-ever finish has nothing to be placed against. The hero spends that
    /// state on the First Ascent flag instead, so this only has to say which state
    /// it is.
    @Test
    func aFirstFinishOnTheTowerSaysSo() throws {
        let placing = try #require(
            PersonalClimbPlacing(durationSeconds: 492, otherCompletionDurationsSeconds: [])
        )

        #expect(placing.total == 1)
        #expect(placing.ordinal == 1)
        #expect(placing.isFirstCompletionHere)
        #expect(placing.fieldLabel == "OF YOUR 1 CLIMB")
    }

    /// A dead heat with an earlier run does not push the climber down: standard
    /// competition ranking, the same rule the boards use.
    @Test
    func aTiedRepeatSharesThePlacingRatherThanLosingIt() throws {
        let placing = try #require(
            PersonalClimbPlacing(
                durationSeconds: 492,
                otherCompletionDurationsSeconds: [492, 640]
            )
        )

        #expect(placing.ordinal == 1)
        #expect(placing.total == 3)
    }

    /// The caller hands over the *other* completions, so a list that already held
    /// this attempt would silently count it twice. Nothing in the arithmetic can
    /// notice that, which is why the boundary is stated on the initialiser and
    /// pinned here: the total is always one more than what it was given.
    @Test
    func theTotalCountsTheAttemptBeingPlacedExactlyOnce() throws {
        for otherCount in 0...6 {
            let placing = try #require(
                PersonalClimbPlacing(
                    durationSeconds: 500,
                    otherCompletionDurationsSeconds: Array(repeating: 700, count: otherCount)
                )
            )

            #expect(placing.total == otherCount + 1)
        }
    }

    /// A completion with no measured duration cannot be placed, and inventing a
    /// placing for it would put an unfalsifiable ordinal on the hero.
    @Test
    func anUnmeasuredCompletionProducesNoPlacing() {
        #expect(PersonalClimbPlacing(durationSeconds: 0, otherCompletionDurationsSeconds: [492]) == nil)
        #expect(PersonalClimbPlacing(durationSeconds: -12, otherCompletionDurationsSeconds: []) == nil)
    }

    /// Zero-duration rows in the climber's history are dropped rather than counted
    /// as impossibly fast runs ahead of them.
    @Test
    func unmeasuredEarlierCompletionsAreNotCountedAsAhead() throws {
        let placing = try #require(
            PersonalClimbPlacing(
                durationSeconds: 580,
                otherCompletionDurationsSeconds: [0, 0, 640]
            )
        )

        #expect(placing.ordinal == 1)
        #expect(placing.total == 2)
    }

    // MARK: - A history this device cannot fully account for

    /// The regression this rule exists to make impossible.
    ///
    /// A restored install that could not restore a tower's workouts holds one
    /// collapsed row: the true count, and the climber's best duration, and
    /// nothing else. Reading the count for the denominator while ordering only
    /// that one duration announced a climber's SLOWEST run ever as
    /// `2ND OF YOUR 6 CLIMBS` - the flattering ordinal that cannot fall, which is
    /// exactly the defect this type was built to delete. Past the known best the
    /// position is unknowable, so it takes last.
    @Test
    func aRunPastTheKnownBestTakesLastRatherThanAFlatteringMiddleOrdinal() throws {
        let placing = try #require(
            PersonalClimbPlacing(
                durationSeconds: 580,
                otherCompletions: collapsedHistory(
                    otherCompletionsCount: 5,
                    knownDurationsSeconds: [492]
                )
            )
        )

        #expect(placing.total == 6)
        #expect(placing.ordinal == 6)
        #expect(placing.achievementTitle == "6TH OF YOUR 6 CLIMBS")
    }

    /// The opposite error, guarded: a run at or inside the known best is
    /// *provably* the climber's fastest, and first of your own climbs IS the
    /// personal-best state. Refusing to say so would be as wrong as flattering.
    @Test
    func aRunInsideTheKnownBestStillStatesTheProvableFirst() throws {
        let faster = try #require(
            PersonalClimbPlacing(
                durationSeconds: 470,
                otherCompletions: collapsedHistory(
                    otherCompletionsCount: 5,
                    knownDurationsSeconds: [492]
                )
            )
        )
        let tied = try #require(
            PersonalClimbPlacing(
                durationSeconds: 492,
                otherCompletions: collapsedHistory(
                    otherCompletionsCount: 5,
                    knownDurationsSeconds: [492]
                )
            )
        )

        #expect(faster.ordinal == 1)
        #expect(faster.total == 6)
        #expect(tied.ordinal == 1)
    }

    /// A collapsed history with no duration at all proves nothing at either end,
    /// so there is no honest ordinal and the placing withholds.
    ///
    /// Taking last here would be the flattering claim's mirror image: the same
    /// climber's genuine personal best would be announced as `4TH OF YOUR 4
    /// CLIMBS`, and neither number can be substantiated. Reachable because the
    /// projection's best duration is nullable - a rebuilt row with no duration
    /// leaves nothing to compare against at all.
    @Test
    func aCollapsedHistoryWithNoDurationsWithholdsThePlacingEntirely() {
        let slower = PersonalClimbPlacing(
            durationSeconds: 580,
            otherCompletions: collapsedHistory(
                otherCompletionsCount: 3,
                knownDurationsSeconds: []
            )
        )
        let faster = PersonalClimbPlacing(
            durationSeconds: 300,
            otherCompletions: collapsedHistory(
                otherCompletionsCount: 3,
                knownDurationsSeconds: []
            )
        )

        #expect(slower == nil)
        #expect(faster == nil)
    }

    /// One duration on hand is enough to decide both ends, so the placing is
    /// still made. The withhold above is about having none at all.
    @Test
    func oneKnownDurationIsStillEnoughToPlace() throws {
        let placing = try #require(
            PersonalClimbPlacing(
                durationSeconds: 580,
                otherCompletions: collapsedHistory(
                    otherCompletionsCount: 3,
                    knownDurationsSeconds: [492]
                )
            )
        )

        #expect(placing.ordinal == 4)
        #expect(placing.total == 4)
    }

    /// A count that undersells the durations on hand cannot shrink the field
    /// beneath what is provably in it - a placing over a field smaller than its
    /// own evidence is the rank-outside-its-denominator defect again.
    @Test
    func aCountBelowTheDurationsOnHandNeverShrinksTheField() throws {
        let placing = try #require(
            PersonalClimbPlacing(
                durationSeconds: 580,
                otherCompletions: collapsedHistory(
                    otherCompletionsCount: 1,
                    knownDurationsSeconds: [492, 599, 640]
                )
            )
        )

        #expect(placing.total == 4)
        #expect(placing.ordinal == 4)
    }

    /// Complete evidence keeps the exact arithmetic: the ordinal counts the runs
    /// that really were faster, because every one of them is on hand.
    @Test
    func completeEvidenceStillPlacesExactly() throws {
        let placing = try #require(
            PersonalClimbPlacing(
                durationSeconds: 580,
                otherCompletions: PersonalClimbCompletionHistory(
                    otherCompletionsCount: 4,
                    otherCompletionDurationsSeconds: [492, 599, 640, 705],
                    durationEvidence: .complete,
                    isEarliestCompletionHere: false,
                    globalCompletionOrder: nil
                )
            )
        )

        #expect(placing.ordinal == 2)
        #expect(placing.total == 5)
    }

    private func collapsedHistory(
        otherCompletionsCount: Int,
        knownDurationsSeconds: [Int]
    ) -> PersonalClimbCompletionHistory {
        PersonalClimbCompletionHistory(
            otherCompletionsCount: otherCompletionsCount,
            otherCompletionDurationsSeconds: knownDurationsSeconds,
            durationEvidence: .partial,
            isEarliestCompletionHere: false,
            globalCompletionOrder: nil
        )
    }

    /// The ordinal can never exceed its own field: this is the class of pairing -
    /// a rank outside its denominator - that produced the original defect on the
    /// server side, and it is made unrepresentable here rather than clamped later.
    @Test
    func theOrdinalNeverEscapesItsOwnField() {
        let placing = PersonalClimbPlacing(ordinal: 9, total: 3)

        #expect(placing.ordinal == 3)
        #expect(placing.total == 3)
    }
}
