import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct WeeklyTargetTests {
    private let calendar = WeekConfiguration.calendar(timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    // MARK: - The value

    @Test
    func aTargetIsOneToSevenDaysAndNothingElse() {
        for days in 1...7 { #expect(WeeklyTarget(days: days)?.days == days) }
        for days in [-1, 0, 8, 100] { #expect(WeeklyTarget(days: days) == nil) }
    }

    @Test
    func theTierNamesFollowTheDesign() {
        #expect(WeeklyTarget(days: 1)?.tier.title == "EASE IN")
        #expect(WeeklyTarget(days: 2)?.tier.title == "EASE IN")
        #expect(WeeklyTarget(days: 3)?.tier.title == "STEADY CLIMBER")
        #expect(WeeklyTarget(days: 4)?.tier.title == "STEADY CLIMBER")
        #expect(WeeklyTarget(days: 5)?.tier.title == "SERIOUS")
        #expect(WeeklyTarget(days: 6)?.tier.title == "ALL IN")
        #expect(WeeklyTarget(days: 7)?.tier.title == "ALL IN")
    }

    // MARK: - The ring's count

    @Test
    func noTargetMeansNoProgressAtAll() {
        let progress = WeeklyTargetProgress.current(
            target: nil,
            climbDates: [date(2026, 11, 3)],
            referenceDate: date(2026, 11, 4),
            calendar: calendar
        )
        #expect(progress == nil)
    }

    @Test
    func twoClimbsOnOneDayAreOneDay() throws {
        let target = try #require(WeeklyTarget(days: 3))
        let progress = WeeklyTargetProgress.current(
            target: target,
            climbDates: [date(2026, 11, 3, hour: 7), date(2026, 11, 3, hour: 19), date(2026, 11, 4)],
            referenceDate: date(2026, 11, 4, hour: 20),
            calendar: calendar
        )
        #expect(progress?.daysClimbed == 2)
        #expect(progress?.daysRemaining == 1)
        #expect(progress?.isMet == false)
    }

    /// 2026-11-01 is a Sunday: the last day of the Monday week that began 2026-10-26, so a climb on
    /// it counts for that week and not for the one that starts the next morning.
    @Test
    func theWeekTurnsOverOnMondayMorning() throws {
        let target = try #require(WeeklyTarget(days: 3))
        let climbs = [date(2026, 10, 26), date(2026, 10, 28), date(2026, 11, 1), date(2026, 11, 2)]

        let sunday = WeeklyTargetProgress.current(
            target: target, climbDates: climbs, referenceDate: date(2026, 11, 1, hour: 22), calendar: calendar
        )
        #expect(sunday?.daysClimbed == 3)
        #expect(sunday?.isMet == true)

        let monday = WeeklyTargetProgress.current(
            target: target, climbDates: climbs, referenceDate: date(2026, 11, 2, hour: 8), calendar: calendar
        )
        #expect(monday?.daysClimbed == 1)
        #expect(monday?.isMet == false)
    }

    @Test
    func theRingFillsToOneAndNoFurtherWhenThePlanIsBeaten() throws {
        let target = try #require(WeeklyTarget(days: 2))
        let progress = try #require(WeeklyTargetProgress.current(
            target: target,
            climbDates: [date(2026, 11, 2), date(2026, 11, 3), date(2026, 11, 4)],
            referenceDate: date(2026, 11, 4, hour: 20),
            calendar: calendar
        ))
        #expect(progress.fraction == 1)
        #expect(progress.daysRemaining == 0)
        #expect(HomeWeeklyTargetCopy(progress: progress).detail == "Week closed. Climb again to go past it.")
    }

    @Test
    func theCardSaysHowManyDaysCloseTheWeek() throws {
        let one = WeeklyTargetProgress(target: try #require(WeeklyTarget(days: 3)), daysClimbed: 2)
        let two = WeeklyTargetProgress(target: try #require(WeeklyTarget(days: 3)), daysClimbed: 1)
        #expect(HomeWeeklyTargetCopy(progress: one).title == "2 of 3 days")
        #expect(HomeWeeklyTargetCopy(progress: one).detail == "1 more day closes your week")
        #expect(HomeWeeklyTargetCopy(progress: two).detail == "2 more days close your week")
    }

    @Test(arguments: [0, 1])
    func aOneDayTargetSaysDay(daysClimbed: Int) throws {
        let copy = HomeWeeklyTargetCopy(progress: WeeklyTargetProgress(target: try #require(WeeklyTarget(days: 1)), daysClimbed: daysClimbed))
        #expect(copy.title == "\(daysClimbed) of 1 day")
        #expect(copy.accessibilityLabel.hasPrefix("Weekly target: \(daysClimbed) of 1 day climbed this week. "))
    }

    // MARK: - Home

    @Test
    func homeDrawsTheRingOnlyForAClimberWhoSetATarget() throws {
        let container = try ModelContainer(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self, ClimbAttempt.self,
            LeaderboardStats.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let reference = Date()
        let workout = Workout(
            name: "Climb", date: reference, duration: 1_800, steps: 1_000,
            floors: Workout.stepsToFloors(1_000, stepsPerFloor: 16), stepsPerFloor: 16, source: .manual
        )
        context.insert(workout)

        let viewModel = HomeDashboardViewModel()
        viewModel.refreshLocalData(modelContext: context, workouts: [workout], referenceDate: reference)
        #expect(viewModel.weeklyTargetProgress == nil, "skipping the target means no ring")

        viewModel.refreshLocalData(modelContext: context, workouts: [workout], weeklyTarget: WeeklyTarget(days: 3), referenceDate: reference)
        #expect(viewModel.weeklyTargetProgress?.daysClimbed == 1)
        #expect(viewModel.weeklyTargetProgress?.target.days == 3)

        viewModel.refreshLocalData(modelContext: context, workouts: [workout], weeklyTarget: nil, referenceDate: reference)
        #expect(viewModel.weeklyTargetProgress == nil, "clearing the target in Settings removes the ring")
        #expect(viewModel.weeklyStreak.weeks == 1, "the streak never depended on a target")
    }

    // MARK: - The store

    private func store() -> WeeklyTargetStore {
        let suite = "weekly-target-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return WeeklyTargetStore(userDefaults: defaults)
    }

    @Test
    func aTargetBelongsToTheAccountThatSetIt() {
        let store = store()
        store.save(WeeklyTarget(days: 4), for: "alice")

        #expect(store.target(for: "alice")?.days == 4)
        #expect(store.target(for: "bob") == nil, "a second account on a shared phone starts with no ring")
    }

    @Test
    func clearingTheTargetRemovesItAndMarksTheChangeUnsynced() {
        let store = store()
        store.save(WeeklyTarget(days: 4), for: "alice")
        store.markSynced(for: "alice")
        #expect(!store.hasUnsyncedChange(for: "alice"))

        store.save(nil, for: "alice")
        #expect(store.target(for: "alice") == nil)
        #expect(store.hasUnsyncedChange(for: "alice"))
    }

    @Test
    func theAccountsAnswerNeverOverwritesAChangeTheCloudHasNotSeen() {
        let store = store()
        store.save(WeeklyTarget(days: 5), for: "alice")
        store.adopt(WeeklyTarget(days: 2), for: "alice")
        #expect(store.target(for: "alice")?.days == 5)

        store.markSynced(for: "alice")
        store.adopt(WeeklyTarget(days: 2), for: "alice")
        #expect(store.target(for: "alice")?.days == 2)
    }

    @Test
    func anAcknowledgementOfAnOlderChangeNeverClearsANewerOne() {
        let store = store()
        store.save(WeeklyTarget(days: 3), for: "alice")
        let sentRevision = store.revision(for: "alice")
        store.save(WeeklyTarget(days: 5), for: "alice")

        store.markSynced(for: "alice", ifRevision: sentRevision)

        #expect(store.hasUnsyncedChange(for: "alice"), "the 5 has not reached the account")
        #expect(store.target(for: "alice")?.days == 5)

        store.markSynced(for: "alice", ifRevision: store.revision(for: "alice"))
        #expect(!store.hasUnsyncedChange(for: "alice"))
    }

    // MARK: - The service

    private final class Remote: @unchecked Sendable {
        var stored: WeeklyTarget?
        var writes: [WeeklyTarget?] = []
        var failsWrites = false
        var failsReads = false
    }

    private func service(store: WeeklyTargetStore, remote: Remote, writesEnabled: Bool) -> WeeklyTargetService {
        WeeklyTargetService(
            store: store,
            isWriteEnabled: { writesEnabled },
            readRemote: { _ in
                if remote.failsReads { throw URLError(.notConnectedToInternet) }
                return remote.stored
            },
            writeRemote: { _, target in
                if remote.failsWrites { throw URLError(.notConnectedToInternet) }
                remote.writes.append(target)
                remote.stored = target
            }
        )
    }

    @Test
    func aSavedTargetReachesTheAccountWhenTheSwitchIsOn() async {
        let store = store(), remote = Remote()
        let service = service(store: store, remote: remote, writesEnabled: true)

        let landed = await service.save(WeeklyTarget(days: 3), for: "alice")

        #expect(landed)
        #expect(remote.writes == [WeeklyTarget(days: 3)])
        #expect(!store.hasUnsyncedChange(for: "alice"))
    }

    @Test
    func withTheSwitchOffTheTargetStaysOnTheDeviceAndWaits() async {
        let store = store(), remote = Remote()
        let off = service(store: store, remote: remote, writesEnabled: false)

        let landed = await off.save(WeeklyTarget(days: 3), for: "alice")

        #expect(!landed)
        #expect(remote.writes.isEmpty, "nothing is written while the kill switch is off")
        #expect(off.localTarget(for: "alice")?.days == 3, "the ring still works")
        #expect(store.hasUnsyncedChange(for: "alice"))

        let on = service(store: store, remote: remote, writesEnabled: true)
        await on.reconcile(for: "alice")
        #expect(remote.writes == [WeeklyTarget(days: 3)], "it goes up when the switch returns")
        #expect(!store.hasUnsyncedChange(for: "alice"))
    }

    @Test
    func aFailedWriteLeavesTheChangeToTryAgain() async {
        let store = store(), remote = Remote()
        remote.failsWrites = true
        let service = service(store: store, remote: remote, writesEnabled: true)

        #expect(await service.save(WeeklyTarget(days: 6), for: "alice") == false)
        #expect(store.hasUnsyncedChange(for: "alice"))
        #expect(service.localTarget(for: "alice")?.days == 6)
    }

    @Test
    func aNewPhoneAdoptsTheTargetTheAccountHolds() async {
        let store = store(), remote = Remote()
        remote.stored = WeeklyTarget(days: 4)
        let service = service(store: store, remote: remote, writesEnabled: true)

        let shown = await service.reconcile(for: "alice")

        #expect(shown?.days == 4)
        #expect(service.localTarget(for: "alice")?.days == 4)
    }

    @Test
    func aFailedReadIsNotAnAccountWithNoTarget() async {
        let store = store(), remote = Remote()
        store.save(WeeklyTarget(days: 4), for: "alice")
        store.markSynced(for: "alice")
        remote.failsReads = true
        let service = service(store: store, remote: remote, writesEnabled: true)

        let shown = await service.reconcile(for: "alice")

        #expect(shown?.days == 4, "the device's copy stands when the account cannot be read")
    }

    @Test
    func anAccountWithNoTargetClearsAStaleSyncedOne() async {
        let store = store(), remote = Remote()
        store.save(WeeklyTarget(days: 4), for: "alice")
        store.markSynced(for: "alice")
        remote.stored = nil
        let service = service(store: store, remote: remote, writesEnabled: true)

        #expect(await service.reconcile(for: "alice") == nil)
    }

    // MARK: - One at a time

    /// A remote whose writes stay in flight until the test releases them.
    @MainActor
    private final class HeldWrites {
        var started: [WeeklyTarget?] = []
        var landed: [WeeklyTarget?] = []
        var reads = 0
        private var held: [CheckedContinuation<Void, Never>] = []

        func write(_ target: WeeklyTarget?) async {
            started.append(target)
            await withCheckedContinuation { held.append($0) }
            landed.append(target)
        }

        func releaseOldest() {
            held.removeFirst().resume()
        }

        func letEverythingRun(until condition: () -> Bool = { false }) async {
            for _ in 0..<200 where !condition() {
                await Task.yield()
            }
        }
    }

    private func heldService(store: WeeklyTargetStore, remote: HeldWrites) -> WeeklyTargetService {
        WeeklyTargetService(
            store: store,
            isWriteEnabled: { true },
            readRemote: { _ in
                remote.reads += 1
                return WeeklyTarget(days: 2)
            },
            writeRemote: { _, target in await remote.write(target) },
            queue: WeeklyTargetSyncQueue()
        )
    }

    @Test
    func aNewerChangeWaitsForTheOlderWriteSoTheAccountEndsOnTheNewest() async {
        let store = store(), remote = HeldWrites()
        let service = heldService(store: store, remote: remote)

        let first = Task { await service.save(WeeklyTarget(days: 3), for: "alice") }
        await remote.letEverythingRun { remote.started.count == 1 }
        let second = Task { await service.save(WeeklyTarget(days: 5), for: "alice") }
        await remote.letEverythingRun()
        #expect(remote.started == [WeeklyTarget(days: 3)], "the 5 waits for the 3 to finish")

        remote.releaseOldest()
        await remote.letEverythingRun { remote.started.count == 2 }
        #expect(remote.started == [WeeklyTarget(days: 3), WeeklyTarget(days: 5)])
        #expect(store.hasUnsyncedChange(for: "alice"), "the 3's acknowledgement does not clear the 5")

        remote.releaseOldest()
        #expect(await first.value)
        #expect(await second.value)
        #expect(remote.landed == [WeeklyTarget(days: 3), WeeklyTarget(days: 5)])
        #expect(!store.hasUnsyncedChange(for: "alice"))
        #expect(store.target(for: "alice")?.days == 5)
    }

    @Test
    func aReconcileWaitsForAWriteSoItCannotAdoptAnAnswerFromBeforeIt() async {
        let store = store(), remote = HeldWrites()
        let service = heldService(store: store, remote: remote)

        let save = Task { await service.save(WeeklyTarget(days: 5), for: "alice") }
        await remote.letEverythingRun { remote.started.count == 1 }
        let reconcile = Task { await service.reconcile(for: "alice") }
        await remote.letEverythingRun()
        #expect(remote.reads == 0)

        remote.releaseOldest()
        #expect(await save.value)
        #expect(await reconcile.value?.days == 2, "the account's answer is read after the write landed")
        #expect(remote.reads == 1)
    }
}
