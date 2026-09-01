import Foundation
import Testing
@testable import AscendApp

/// What happens to a climber's own earlier completion on the board they are
/// racing on right now.
///
/// Locked with the captain on 2026-09-01 (`ghost-row-design-v2`,
/// `ghost-marker-line-geometry`, `just-me-tab-design`): the previous best is
/// **not a row**. It is a single marker inside the climber's own row, it holds no
/// rank, it is never tappable, and it is never counted - not in the rank, not in
/// the field size. Every comparison number that earlier drafts carried is
/// deleted.
///
/// Before this, `parseRow` marked nobody as the current user, so a repeat
/// climber's own best rendered as a stranger wearing their name, was ranked as a
/// rival ahead of them, and the same screen then pinned `1 CLIMBER` under two
/// rows.
struct LiveReplayPreviousBestMarkerTests {
    private let context = LiveReplayLeaderboardContext.liveClimb(
        climbId: "st-peters-basilica",
        targetSteps: 551
    )

    // MARK: - Not a row

    /// The solo repeat that started the whole task: one climber, their own best
    /// ahead of them, and a board that used to read "rank 2" over "1 CLIMBER".
    @Test
    func aSoloRepeatRacesAloneWithTheirOwnBestWithdrawnFromTheBoard() {
        let window = makeWindow(
            currentSteps: 347,
            rows: [ownPreviousBest(stepsAtBucket: 414)],
            currentUserRank: 2
        )

        let rows = window.locallyRankedRows(currentSteps: 347, currentElapsedSeconds: 300)

        #expect(rows.count == 1)
        #expect(rows.map(\.id) == ["current-user"])
        #expect(rows.first?.rank == 1)
    }

    /// The rank the Just Me tab's `CURRENT RANK` card reads. It used to say `#2`
    /// while the board beneath it counted one climber.
    @Test
    func theClimbersOwnBestIsNotCountedAsAClimberAheadOfThem() {
        let window = makeWindow(
            currentSteps: 347,
            rows: [
                rivalRow(id: "rival", rank: 1, stepsAtBucket: 500),
                ownPreviousBest(stepsAtBucket: 414)
            ],
            currentUserRank: 3
        )

        let rows = window.locallyRankedRows(currentSteps: 347, currentElapsedSeconds: 300)

        #expect(rows.map(\.id) == ["rival", "current-user"])
        #expect(rows.first(where: \.isCurrentUser)?.rank == 2)
    }

    /// Passing your own best changes nothing about the standings, because it never
    /// held one. The marker moves to the other side of the fill; that is the whole
    /// event.
    @Test
    func passingYourOwnBestDoesNotMoveYourRank() {
        let window = makeWindow(
            currentSteps: 347,
            rows: [
                rivalRow(id: "rival", rank: 1, stepsAtBucket: 500),
                ownPreviousBest(stepsAtBucket: 414)
            ],
            currentUserRank: 3
        )

        let behind = window.locallyRankedRows(currentSteps: 347, currentElapsedSeconds: 300)
        let ahead = window.locallyRankedRows(currentSteps: 430, currentElapsedSeconds: 300)

        #expect(behind.first(where: \.isCurrentUser)?.rank == 2)
        #expect(ahead.first(where: \.isCurrentUser)?.rank == 2)
    }

    /// A previous best sitting *behind* the climber was never counted ahead of
    /// them, so nothing comes out of the rank for it.
    @Test
    func aPreviousBestBehindTheClimberDoesNotDiscountTheRank() {
        let window = makeWindow(
            currentSteps: 430,
            rows: [
                rivalRow(id: "rival", rank: 1, stepsAtBucket: 500),
                ownPreviousBest(stepsAtBucket: 414)
            ],
            currentUserRank: 2
        )

        let rows = window.locallyRankedRows(currentSteps: 430, currentElapsedSeconds: 300)

        #expect(rows.map(\.id) == ["rival", "current-user"])
        #expect(rows.first(where: \.isCurrentUser)?.rank == 2)
    }

    /// A rival's rows are untouched by any of this. Only the viewer's own earlier
    /// completion is withdrawn - everyone else still races at their best.
    @Test
    func rivalsAreNeverWithdrawnFromTheBoard() {
        let window = makeWindow(
            currentSteps: 347,
            rows: [
                rivalRow(id: "rival-a", rank: 1, stepsAtBucket: 520),
                rivalRow(id: "rival-b", rank: 2, stepsAtBucket: 480),
                rivalRow(id: "rival-c", rank: 4, stepsAtBucket: 200)
            ],
            currentUserRank: 3
        )

        let rows = window.locallyRankedRows(currentSteps: 347, currentElapsedSeconds: 300)

        #expect(rows.map(\.id) == ["rival-a", "rival-b", "current-user", "rival-c"])
        #expect(rows.first(where: \.isCurrentUser)?.rank == 3)
    }

    // MARK: - The marker

    /// All the marker carries: a position. The row shows the climber's steps, the
    /// marker shows where their best was, and the visible gap is the message.
    @Test
    func theMarkerReportsAPositionAndNothingElse() throws {
        let window = makeWindow(
            currentSteps: 347,
            rows: [ownPreviousBest(stepsAtBucket: 414)],
            currentUserRank: 2
        )

        let steps = try #require(window.previousBestStepsAtBucket(currentElapsedSeconds: 300))

        #expect(steps == 414)
    }

    /// No previous completion on this tower, no marker. Nothing is synthesised
    /// from a rival's row or from a failed attempt.
    @Test
    func aBoardWithNoPreviousCompletionOfTheClimbersOwnHasNoMarker() {
        let window = makeWindow(
            currentSteps: 347,
            rows: [rivalRow(id: "rival", rank: 1, stepsAtBucket: 500)],
            currentUserRank: 2
        )

        #expect(window.previousBestStepsAtBucket(currentElapsedSeconds: 300) == nil)
        #expect(window.opponentRows.count == 1)
    }

    /// The marker travels: a completed curve is projected forward on the same
    /// clock the rival rows are, so the line advances as the race runs rather than
    /// freezing at whatever the last fetched bucket held.
    @Test
    func theMarkerAdvancesWithTheRaceRatherThanFreezingAtTheFetchedBucket() throws {
        let window = makeWindow(
            currentSteps: 100,
            rows: [
                ownPreviousBest(
                    stepsAtBucket: 200,
                    finalSteps: 551,
                    completionDurationSeconds: 492
                )
            ],
            currentUserRank: 2
        )

        let early = try #require(window.previousBestStepsAtBucket(currentElapsedSeconds: 120))
        let late = try #require(window.previousBestStepsAtBucket(currentElapsedSeconds: 360))

        #expect(early < late)
        #expect(late <= 551)
    }

    // MARK: - Helpers

    private func makeWindow(
        currentSteps: Int,
        rows: [LiveReplayLeaderboardRow],
        currentUserRank: Int
    ) -> LiveReplayLeaderboardWindow {
        LiveReplayLeaderboardWindow(
            context: context,
            bucketIndex: 30,
            currentSteps: currentSteps,
            fetchedAt: Date(timeIntervalSince1970: 1_777_777_777),
            rows: rows,
            currentUserRank: currentUserRank,
            totalClimbers: max(rows.count, 1)
        )
    }

    private func ownPreviousBest(
        stepsAtBucket: Int,
        finalSteps: Int? = nil,
        completionDurationSeconds: TimeInterval? = nil
    ) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: "own-best",
            rank: 1,
            displayName: "Tyler P.",
            avatarToken: "TP",
            photoURL: nil,
            stepsAtBucket: stepsAtBucket,
            finalSteps: finalSteps ?? stepsAtBucket,
            deltaFromUser: 0,
            isCurrentUser: false,
            isOwnPreviousCompletion: true,
            isPersonalBest: true,
            completionDurationSeconds: completionDurationSeconds,
            userId: "climber-self"
        )
    }

    private func rivalRow(
        id: String,
        rank: Int,
        stepsAtBucket: Int
    ) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: id,
            rank: rank,
            displayName: "M. Okafor",
            avatarToken: "MO",
            photoURL: nil,
            stepsAtBucket: stepsAtBucket,
            finalSteps: max(stepsAtBucket, 551),
            deltaFromUser: 0,
            isCurrentUser: false,
            isPersonalBest: false,
            completionDurationSeconds: nil,
            userId: "climber-\(id)"
        )
    }
}
