import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// The one-time backfill behind onboarding's ADD TO MY HISTORY: what Health held before the climber
/// joined becomes climbs that fill history and records and never a leaderboard, once, and only when
/// everything the ordinary pass needs is in place.
@MainActor
@Suite(.serialized)
struct AppleHealthHistoryImportTests {
    private func switchedOff(_ flag: RemoteFeatureFlag) -> RemoteFeatureFlagStore {
        RemoteFeatureFlagStore(snapshot: RemoteFeatureFlagSnapshot.resolving(remoteValues: [flag.key: false]))
    }

    /// A climber who joined a month ago with `workouts` before and after that day.
    private func harnessWithHistory(
        featureFlags: RemoteFeatureFlagStore = RemoteFeatureFlagStore()
    ) throws -> (harness: AppleHealthImportHarness, old: [HealthWorkoutSnapshot], recent: HealthWorkoutSnapshot) {
        let harness = try AppleHealthImportHarness(featureFlags: featureFlags)
        let old = [
            harness.addWorkout(daysAgo: 60, steps: 3_000, minutes: 40),
            harness.addWorkout(daysAgo: 90, steps: nil, minutes: 35),
            harness.addWorkout(daysAgo: 400, steps: 12_000, minutes: 120)
        ]
        let recent = harness.addWorkout(daysAgo: 5, steps: 2_500, minutes: 30)
        return (harness, old, recent)
    }

    // MARK: - What lands

    @Test
    func olderWorkoutsBecomeOffBoardAppleHealthClimbs() async throws {
        let (harness, old, _) = try harnessWithHistory()

        let landed = await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(landed)
        let climbs = try harness.climbs()
        #expect(climbs.count == old.count)
        for climb in climbs {
            #expect(climb.source == .appleHealth)
            #expect(climb.leaderboardStatus == .excluded, "history never reaches a board")
        }
        let withSteps = try #require(climbs.first { $0.healthKitUUID == old[0].uuid.uuidString })
        #expect(withSteps.steps == 3_000)
        #expect(withSteps.date == old[0].startDate)
        let noSteps = try #require(climbs.first { $0.healthKitUUID == old[1].uuid.uuidString })
        #expect(noSteps.isMissingSteps, "unknown stays unknown and asks for its number")
    }

    @Test
    func historyFillsRecordsButAClimbWithNoStepsHoldsNone() async throws {
        let (harness, old, _) = try harnessWithHistory()
        await harness.service.importHistory(before: harness.referenceJoinDate)

        let climbs = try harness.climbs()
        let counted = try #require(climbs.first { $0.healthKitUUID == old[0].uuid.uuidString })
        let unknown = try #require(climbs.first { $0.healthKitUUID == old[1].uuid.uuidString })
        #expect(counted.canHoldRecords, "history fills personal bests")
        #expect(!unknown.canHoldRecords)
    }

    @Test
    func workoutsFromTheJoinDateOnAreLeftToThePass() async throws {
        let (harness, _, recent) = try harnessWithHistory()

        await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(try harness.climbs().allSatisfy { $0.healthKitUUID != recent.uuid.uuidString })
        #expect(try harness.record(recent) == nil)
    }

    @Test
    func itNeverMovesThePassAnchorAndAnnouncesNothing() async throws {
        let (harness, _, recent) = try harnessWithHistory()

        await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(harness.settings.anchorData(for: AppleHealthImportHarness.userID) == nil)
        #expect(harness.notifier.imported.isEmpty)
        #expect(harness.service.homeNotice == nil)

        // The pass still finds what arrived after the join, from nothing.
        await harness.service.syncNow()
        #expect(try harness.climbs().contains { $0.healthKitUUID == recent.uuid.uuidString })
    }

    @Test
    func itFilesTheWorkoutsThroughTheLedgerAsImported() async throws {
        let (harness, old, _) = try harnessWithHistory()

        await harness.service.importHistory(before: harness.referenceJoinDate)

        for snapshot in old {
            let record = try #require(try harness.record(snapshot))
            #expect(record.state == .imported)
            #expect(record.importedWorkoutID != nil)
        }
    }

    // MARK: - Never twice

    @Test
    func runningItAgainFilesNothingTwice() async throws {
        let (harness, old, _) = try harnessWithHistory()

        await harness.service.importHistory(before: harness.referenceJoinDate)
        let landedAgain = await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(landedAgain)
        #expect(try harness.climbs().count == old.count)
        #expect(try harness.records().count == old.count)
    }

    @Test
    func aClimbRemovedAfterwardsIsNeverBroughtBack() async throws {
        let (harness, old, _) = try harnessWithHistory()
        await harness.service.importHistory(before: harness.referenceJoinDate)
        let climb = try #require(try harness.climbs().first { $0.healthKitUUID == old[0].uuid.uuidString })

        await harness.service.removeImportedClimb(workoutID: climb.id)
        await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(try harness.climbs().allSatisfy { $0.healthKitUUID != old[0].uuid.uuidString })
        #expect(try harness.record(old[0])?.state == .skipped)
    }

    @Test
    func aWorkoutAClimbAlreadyCarriesIsNotImportedAgain() async throws {
        let (harness, old, _) = try harnessWithHistory()
        // The climber's account already holds a climb for this workout, restored from the cloud.
        let restored = Workout(
            name: HealthImportedClimb.workoutName,
            date: old[0].startDate,
            duration: old[0].duration,
            steps: 3_000,
            floors: Workout.stepsToFloors(3_000),
            source: .appleHealth,
            healthKitUUID: old[0].uuid.uuidString
        )
        harness.context.insert(restored)
        try harness.context.save()

        await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(try harness.climbs().filter { $0.healthKitUUID == old[0].uuid.uuidString }.count == 1)
    }

    // MARK: - Only what the climber was shown

    @Test
    func onlyTheWorkoutsTheClimberWasShownAreBroughtIn() async throws {
        let (harness, old, _) = try harnessWithHistory()

        await harness.service.importHistory(
            before: harness.referenceJoinDate,
            matching: [old[0].uuid.uuidString]
        )

        let climbs = try harness.climbs()
        #expect(climbs.count == 1)
        #expect(climbs.first?.healthKitUUID == old[0].uuid.uuidString)
    }

    @Test
    func aWorkoutThatCannotBeAClimbIsNeverFiled() async throws {
        let harness = try AppleHealthImportHarness()
        let tooLong = harness.addWorkout(daysAgo: 70, steps: 5_000, minutes: 25 * 60)

        await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(try harness.record(tooLong) == nil)
    }

    // MARK: - Deferral

    @Test
    func theKillSwitchDefersEverythingAndNothingIsLost() async throws {
        let off = switchedOff(.appleHealthHistoryImport)
        let (harness, old, _) = try harnessWithHistory(featureFlags: off)

        let landed = await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(!landed)
        #expect(try harness.climbs().isEmpty)
        #expect(try harness.records().isEmpty)
        // The same service with the switch on lands it, from the same Health database.
        let on = try AppleHealthImportHarness()
        for snapshot in old { on.reader.workouts.append(snapshot) }
        #expect(await on.service.importHistory(before: on.referenceJoinDate))
    }

    @Test
    func theImportSwitchStillGatesEveryClimbItCreates() async throws {
        let off = switchedOff(.appleHealthImport)
        let (harness, _, _) = try harnessWithHistory(featureFlags: off)

        let landed = await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(!landed)
        #expect(try harness.climbs().isEmpty)
    }

    @Test
    func itWaitsForTheCloudRestoreLikeTheFirstPassDoes() async throws {
        let (harness, _, _) = try harnessWithHistory()
        let unrestored = harness.relaunchedServiceWithoutCloudRestore()

        let landed = await unrestored.importHistory(before: harness.referenceJoinDate)

        #expect(!landed)
        #expect(try harness.climbs().isEmpty, "a climb the account already holds is the only thing that stops a second one")
    }

    @Test
    func itDefersWhenHealthIsNotConnected() async throws {
        let (harness, _, _) = try harnessWithHistory()
        harness.authorization.importConnectionState = .neverConnected

        let landed = await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(!landed)
        #expect(try harness.climbs().isEmpty)
    }

    @Test
    func itDefersWhenNobodyIsSignedIn() async throws {
        let (harness, _, _) = try harnessWithHistory()
        harness.userID = nil

        let landed = await harness.service.importHistory(before: harness.referenceJoinDate)

        #expect(!landed)
        #expect(try harness.records().isEmpty, "nothing is written before there is an account")
    }

    @Test
    func aFailedReadDefersAndTheNextRunLandsEverything() async throws {
        let (harness, old, _) = try harnessWithHistory()
        harness.reader.readError = NSError(domain: "HealthKit", code: 1)

        #expect(await harness.service.importHistory(before: harness.referenceJoinDate) == false)
        #expect(try harness.climbs().isEmpty)

        harness.reader.readError = nil
        #expect(await harness.service.importHistory(before: harness.referenceJoinDate))
        #expect(try harness.climbs().count == old.count)
    }

    @Test
    func noWorkoutsToBringInStillCountsAsLanded() async throws {
        let harness = try AppleHealthImportHarness()

        #expect(await harness.service.importHistory(before: harness.referenceJoinDate))
        #expect(try harness.climbs().isEmpty)
    }

    // MARK: - The server's rule, on the device

    @Test
    func editingTheStepsOfAHistoryClimbNeverPutsItOnABoard() async throws {
        let (harness, old, _) = try harnessWithHistory()
        await harness.service.importHistory(before: harness.referenceJoinDate)
        let climb = try #require(try harness.climbs().first { $0.healthKitUUID == old[1].uuid.uuidString })
        #expect(climb.isMissingSteps)

        climb.steps = 3_000
        climb.refreshLeaderboardStatus(accountCreatedAt: harness.referenceJoinDate)

        #expect(climb.leaderboardStatus == .excluded, "the climb is from before the account whatever its pace")
    }
}

extension AppleHealthImportHarness {
    /// A process that has not yet heard its climber's cloud restore finished.
    func relaunchedServiceWithoutCloudRestore() -> AppleHealthImportService {
        let service = relaunchedService()
        service.cancelInFlightWork()
        return service
    }
}
