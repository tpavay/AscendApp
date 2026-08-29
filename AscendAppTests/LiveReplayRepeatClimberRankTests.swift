import Foundation
import Testing
@testable import AscendApp

/// The captain's second St Peter's Basilica climb, reproduced from the rows
/// production actually held.
///
/// He held the First Ascent at 346.66s over 35 split buckets and ran it again in
/// 399.22s over 40. Three things went wrong on the live board and its completion
/// summary while Climb Detail - reading the same completions - stayed right:
///
/// 1. His earlier row was parsed as a stranger's, so it wore initials, a
///    demographic subtitle and a link to another climber's profile - his own.
/// 2. From bucket 35 his earlier attempt had no entry at all, because a
///    published attempt writes one entry per bucket it ran for and not one more.
///    The row vanished and the run still going took first.
/// 3. The frozen summary counted climbers rather than completions and then
///    subtracted his own faster row back out, freezing "1st of 1" on the slower
///    run.
///
/// The fixtures below use his real numbers so the arithmetic is checkable
/// against `live_replay_leaderboards/live_climb__st-peters-basilica`.
struct LiveReplayRepeatClimberRankTests {
    private static let climberId = "kC8GSV7hCDZY9waZhIS9CimQ70y2"
    private static let targetSteps = 551
    private static let bucketIntervalSeconds = 10
    /// 346.66s over 35 buckets: present in 0...34, absent from 35 onwards.
    private static let firstAttemptBucketCount = 35

    private static let context = LiveReplayLeaderboardContext.liveClimb(
        climbId: "st-peters-basilica",
        targetSteps: targetSteps,
        bucketIntervalSeconds: bucketIntervalSeconds
    )

    // MARK: - The row that vanished

    @Test
    func aFinishedAttemptStaysAheadOfTheRunStillGoing() {
        // Bucket 35: his first attempt is home at 551 and has no entry here, so
        // the running half of the read comes back empty.
        let finished = [firstAttempt(atSteps: 551).holdingFinalSteps(currentSteps: 497)]
        let rows = FirestoreLiveReplayLeaderboardRepository.mergedAheadRows(
            running: [],
            finished: finished,
            limit: 8
        )

        #expect(rows.map(\.id) == ["first-attempt"])
        #expect(rows.first?.stepsAtBucket == 551)
        #expect(
            FirestoreLiveReplayLeaderboardRepository.aheadCount(
                running: 0,
                finished: 1,
                fetchedRows: rows
            ) == 1
        )
    }

    @Test
    func aFinishedAttemptHoldsItsFinalStepsRatherThanItsFirstBucket() {
        // The finished half is read out of bucket zero, where his first attempt
        // had taken 14 steps. Left as read, a climber who had already finished
        // would re-enter the race ten seconds into it.
        let bucketZeroRow = firstAttempt(atSteps: 14)

        let held = bucketZeroRow.holdingFinalSteps(currentSteps: 497)

        #expect(held.stepsAtBucket == 551)
        #expect(held.deltaFromUser == 54)
    }

    @Test
    func mergingKeepsTheRowsNearestTheLiveAttempt() {
        // Two rivals still climbing just ahead, three already home. The window
        // holds three rows, so it keeps the three the climber is closing on -
        // both runners and one finisher, not the three finishers.
        let running = [
            competitor(id: "running-low", steps: 500),
            competitor(id: "running-high", steps: 520)
        ]
        let finished = (0..<3).map { index in
            competitor(id: "finished-\(index)", steps: 551)
        }

        let rows = FirestoreLiveReplayLeaderboardRepository.mergedAheadRows(
            running: running,
            finished: finished,
            limit: 3
        )

        #expect(rows.map(\.stepsAtBucket) == [500, 520, 551])
        #expect(rows.map(\.id) == ["running-low", "running-high", "finished-0"])
    }

    @Test
    func aFinishedAttemptBelowTheLiveClimberStaysOnTheBoard() {
        // The same vanishing, on the other side of the row. A landmark climb
        // hides it - every completion is at or past the target, so a finisher
        // is always ahead - but an open Just Climb has no target, so a rival who
        // stopped at 200 steps has no entry in any bucket past their own and
        // disappears entirely the moment the climber passes 200.
        let stopped = stoppedRival(id: "stopped-at-200", finalSteps: 200)
            .holdingFinalSteps(currentSteps: 260)

        let rows = FirestoreLiveReplayLeaderboardRepository.mergedBehindRows(
            running: [],
            finished: [stopped],
            limit: 8
        )

        #expect(rows.map(\.id) == ["stopped-at-200"])
        #expect(rows.first?.stepsAtBucket == 200)
        #expect(rows.first?.deltaFromUser == -60)
    }

    @Test
    func mergingBehindKeepsTheRowsNearestBelowRatherThanTheSlowest() {
        // Two rivals still climbing just below, three already stopped further
        // down. The window holds three rows, so it keeps the three closest
        // behind - the twin of the ahead merge, sorted the other way.
        let running = [
            stoppedRival(id: "running-240", finalSteps: 240),
            stoppedRival(id: "running-210", finalSteps: 210)
        ]
        let finished = [200, 120, 60].map { steps in
            stoppedRival(id: "finished-\(steps)", finalSteps: steps)
        }

        let rows = FirestoreLiveReplayLeaderboardRepository.mergedBehindRows(
            running: running,
            finished: finished,
            limit: 3
        )

        #expect(rows.map(\.stepsAtBucket) == [240, 210, 200])
        #expect(rows.map(\.id) == ["running-240", "running-210", "finished-200"])
    }

    @Test
    func aFailedCountFallsBackToTheRowsOnScreenRatherThanHalfAField() {
        // Summing a real count with a fallback would report a rank measured
        // against a population nothing counted.
        let rows = [competitor(id: "finished-0", steps: 551)]

        #expect(
            FirestoreLiveReplayLeaderboardRepository.aheadCount(
                running: nil,
                finished: 4,
                fetchedRows: rows
            ) == 1
        )
        #expect(
            FirestoreLiveReplayLeaderboardRepository.aheadCount(
                running: 7,
                finished: nil,
                fetchedRows: rows
            ) == 1
        )
    }

    // MARK: - Ranking the live attempt against his own finished one

    @Test
    func theSlowerRepeatAttemptSitsSecondBehindHisOwnRecord() {
        let window = windowChasingHisOwnRecord(currentSteps: 497)

        let rows = window.locallyRankedRows(
            currentSteps: 497,
            currentElapsedSeconds: 350,
            displayName: "Tyler Pavay"
        )

        #expect(rows.map(\.id) == ["first-attempt", "current-user"])
        #expect(rows.map { $0.rank ?? -1 } == [1, 2])
    }

    @Test
    func bothRowsBelongToTheViewerButOnlyOneIsTheAttemptInProgress() throws {
        let rows = windowChasingHisOwnRecord(currentSteps: 497).locallyRankedRows(
            currentSteps: 497,
            currentElapsedSeconds: 350,
            displayName: "Tyler Pavay"
        )

        #expect(rows.allSatisfy { $0.isCurrentUser })
        #expect(rows.filter(\.isLiveAttempt).map(\.id) == ["current-user"])

        // Through the one resolver every identity surface renders from: the
        // history row keeps his name and his photo rather than being redrawn as
        // a stranger wearing initials.
        let history = try #require(rows.first { $0.id == "first-attempt" })
        let moderated = CrossUserIdentityAdapter.replayRow(
            history,
            blockedUserIds: [],
            isBlockListHydrated: true
        )

        #expect(moderated.isCurrentUser)
        #expect(!moderated.isLiveAttempt)
        #expect(moderated.identity.displayName == "Tyler Pavay")
        #expect(moderated.identity.photoURL != nil)
        #expect(!moderated.identity.isHidden)
    }

    @Test
    func matchingHisOwnRecordStillLeavesTheFinishedAttemptInFront() {
        // A dead heat on steps at the same bucket: the attempt already banked
        // stays ahead of the one still on the machine.
        let rows = windowChasingHisOwnRecord(currentSteps: 551).locallyRankedRows(
            currentSteps: 551,
            currentElapsedSeconds: 350,
            displayName: "Tyler Pavay"
        )

        #expect(rows.map(\.id) == ["first-attempt", "current-user"])
        #expect(rows.map { $0.rank ?? -1 } == [1, 2])
    }

    @Test
    func aFasterRepeatAttemptTakesTheLead() {
        // Same board, but this run is ahead of where the record was at this
        // bucket. Passing your own ghost has to move you in front of it.
        let window = LiveReplayLeaderboardWindow(
            context: Self.context,
            bucketIndex: 20,
            currentSteps: 340,
            fetchedAt: Date(timeIntervalSince1970: 1_787_957_000),
            rows: [firstAttempt(atSteps: 320)],
            currentUserRank: 1,
            totalClimbers: 1
        )

        let rows = window.locallyRankedRows(
            currentSteps: 340,
            currentElapsedSeconds: 200,
            displayName: "Tyler Pavay"
        )

        #expect(rows.map(\.id) == ["current-user", "first-attempt"])
        #expect(rows.map { $0.rank ?? -1 } == [1, 2])
    }

    @Test
    func aFirstTimeClimberOnAnEmptyBoardStillRanksFirst() {
        // The case that always worked, pinned so the fix cannot buy the repeat
        // climber's rank at a first-timer's expense.
        let window = LiveReplayLeaderboardWindow(
            context: Self.context,
            bucketIndex: 12,
            currentSteps: 180,
            fetchedAt: Date(timeIntervalSince1970: 1_787_957_000),
            rows: [],
            currentUserRank: 1,
            totalClimbers: 1
        )

        let rows = window.locallyRankedRows(
            currentSteps: 180,
            currentElapsedSeconds: 120,
            displayName: "Tyler Pavay"
        )

        #expect(rows.map(\.id) == ["current-user"])
        #expect(rows.first?.rank == 1)
        #expect(rows.first?.isLiveAttempt == true)
    }

    // MARK: - Fixtures

    /// The board as it stood from bucket 35 on: his first attempt home at the
    /// target, read out of the finished half, with the run still going second.
    private func windowChasingHisOwnRecord(
        currentSteps: Int
    ) -> LiveReplayLeaderboardWindow {
        LiveReplayLeaderboardWindow(
            context: Self.context,
            bucketIndex: Self.firstAttemptBucketCount,
            currentSteps: currentSteps,
            fetchedAt: Date(timeIntervalSince1970: 1_787_957_195),
            rows: [firstAttempt(atSteps: 551).holdingFinalSteps(currentSteps: currentSteps)],
            currentUserRank: 2,
            totalClimbers: 1
        )
    }

    private func firstAttempt(atSteps steps: Int) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: "first-attempt",
            rank: nil,
            displayName: "Tyler Pavay",
            avatarToken: "TP",
            photoURL: URL(string: "https://firebasestorage.googleapis.com/photo.jpg"),
            stepsAtBucket: steps,
            finalSteps: Self.targetSteps,
            deltaFromUser: 0,
            isCurrentUser: true,
            isPersonalBest: false,
            completionDurationSeconds: 346.66342401504517,
            userId: Self.climberId,
            gender: "man",
            age: 27,
            locationCity: "Chicago"
        )
    }

    /// A rival who stopped short of any target, held at the steps they stopped
    /// on - the shape the finished half of an open Just Climb read returns.
    private func stoppedRival(id: String, finalSteps: Int) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: id,
            rank: nil,
            displayName: "Rival",
            avatarToken: "RV",
            photoURL: nil,
            stepsAtBucket: finalSteps,
            finalSteps: finalSteps,
            deltaFromUser: 0,
            isCurrentUser: false,
            isPersonalBest: false,
            completionDurationSeconds: 320
        )
    }

    private func competitor(id: String, steps: Int) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: id,
            rank: nil,
            displayName: "Rival",
            avatarToken: "RV",
            photoURL: nil,
            stepsAtBucket: steps,
            finalSteps: Self.targetSteps,
            deltaFromUser: 0,
            isCurrentUser: false,
            isPersonalBest: false,
            completionDurationSeconds: 320
        )
    }
}
