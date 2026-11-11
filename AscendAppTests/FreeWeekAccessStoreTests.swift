import Foundation
import Testing
@testable import AscendApp

/// The device's reading of the free week: one account's record, mirrored from the server.
@MainActor
struct FreeWeekAccessStoreTests {
    @Test
    func anAccountWithNoRecordHoldsTheRouteOnlyUntilTheServerAnswers() async {
        let harness = FreeWeekTestHarness(record: .success(nil))

        harness.store.setUser("climber")
        #expect(harness.store.routingAccess == .unresolved)

        #expect(await freeWeekWaitUntil { harness.store.record == .absent })
        #expect(harness.store.routingAccess == .none)
        #expect(harness.store.liveGrant == nil)
        #expect(harness.reader.readCount == 1)
    }

    @Test
    func aRunningWeekReadFromTheServerOpensTheAppAndIsRemembered() async {
        let harness = FreeWeekTestHarness()
        let week = harness.week(startingDaysAgo: 2)
        harness.reader.result = .success(week)

        harness.store.setUser("climber")
        #expect(await freeWeekWaitUntil { harness.store.record == .granted(week) })

        #expect(harness.store.routingAccess == .live)
        #expect(harness.store.liveGrant == week)
        #expect(harness.store.daysLeft == 5)
        #expect(harness.cache.grant(for: "climber") == week)
    }

    @Test
    func aRememberedWeekOpensTheAppWithNoReadAtAll() {
        let harness = FreeWeekTestHarness(record: .failure(FreeWeekTestError()))
        let week = harness.week(startingDaysAgo: 1)
        harness.cache.store(week, for: "climber")

        harness.store.setUser("climber")

        #expect(harness.store.routingAccess == .live)
        #expect(harness.reader.readCount == 0)
    }

    @Test
    func aWeekThatIsOverIsNotAccessAndIsNotAnInvitationToAnotherLetter() {
        let harness = FreeWeekTestHarness()
        let week = harness.week(startingDaysAgo: 8)
        harness.cache.store(week, for: "climber")

        harness.store.setUser("climber")

        #expect(harness.store.routingAccess == .none)
        #expect(harness.store.liveGrant == nil)
        #expect(harness.store.hasSpentWeek)
        #expect(harness.store.daysLeft == nil)
        // The letter is offered only for `.absent`; a spent week is still a record.
        #expect(harness.store.record == .granted(week))
    }

    @Test
    func aWeekEndsOnScreenWhenItsClockRunsOut() async {
        let clock = FreeWeekTestClock()
        let gate = FreeWeekSleepGate()
        let harness = FreeWeekTestHarness(clock: clock, sleep: gate.sleep)
        let week = harness.week()
        harness.cache.store(week, for: "climber")

        harness.store.setUser("climber")
        #expect(harness.store.routingAccess == .live)

        clock.advance(days: 7)
        gate.open()

        #expect(await freeWeekWaitUntil { harness.store.routingAccess == .none })
        #expect(harness.store.hasSpentWeek)
    }

    @Test
    func aForegroundNoticesAWeekThatEndedWhileTheAppWasSuspended() {
        let clock = FreeWeekTestClock()
        let harness = FreeWeekTestHarness(clock: clock)
        harness.cache.store(harness.week(), for: "climber")
        harness.store.setUser("climber")
        #expect(harness.store.routingAccess == .live)

        // A suspended process's timer never fired.
        clock.advance(days: 9)
        harness.store.reevaluate()

        #expect(harness.store.routingAccess == .none)
    }

    @Test
    func aReadThatFailsIsNotAnAnswerThatThereIsNoRecord() async {
        let harness = FreeWeekTestHarness(record: .failure(FreeWeekTestError()))

        harness.store.setUser("climber")
        #expect(await freeWeekWaitUntil { harness.store.record == .unavailable })

        // The route stops holding, so the climber is not left on a spinner...
        #expect(harness.store.routingAccess == .none)
        // ...and a foreground asks again without sending them back to it.
        harness.reader.result = .success(nil)
        harness.store.reevaluate()
        #expect(harness.store.record == .unavailable)
        #expect(await freeWeekWaitUntil { harness.store.record == .absent })
        #expect(harness.reader.readCount == 2)
    }

    @Test
    func aReadThatNeverReturnsIsCutOffAtTheDeadline() async {
        let harness = FreeWeekTestHarness(sleep: { _ in })
        harness.reader.suspendsReads = true

        harness.store.setUser("climber")

        #expect(await freeWeekWaitUntil { harness.store.record == .unavailable })
        #expect(harness.store.routingAccess == .none)
    }

    @Test
    func startingTheWeekAdoptsWhatTheServerGranted() async {
        let harness = FreeWeekTestHarness()
        let week = harness.week()
        harness.granter.responses = [.success(.granted(week))]
        harness.store.setUser("climber")
        #expect(await freeWeekWaitUntil { harness.store.record == .absent })

        let outcome = await harness.store.startFreeWeek()

        #expect(outcome == .started(week))
        #expect(harness.granter.callCount == 1)
        #expect(harness.store.routingAccess == .live)
        #expect(harness.cache.grant(for: "climber") == week)
    }

    @Test
    func aFailedCallIsRetriedExactlyOnce() async {
        let harness = FreeWeekTestHarness()
        let week = harness.week()
        harness.granter.responses = [.failure(FreeWeekTestError()), .success(.granted(week))]
        harness.store.setUser("climber")

        #expect(await harness.store.startFreeWeek() == .started(week))
        #expect(harness.granter.callCount == 2)

        let failing = FreeWeekTestHarness(responses: [.failure(FreeWeekTestError())])
        failing.store.setUser("climber")

        #expect(await failing.store.startFreeWeek() == .failed)
        #expect(failing.granter.callCount == 2)
        #expect(failing.store.liveGrant == nil)
    }

    @Test
    func aRefusalIsAnAnswerAndIsNotRetried() async {
        let spent = FreeWeekTestHarness()
        let oldWeek = spent.week(startingDaysAgo: 30)
        spent.granter.responses = [.success(.alreadyUsed(oldWeek))]
        spent.store.setUser("climber")

        #expect(await spent.store.startFreeWeek() == .alreadyUsed)
        #expect(spent.granter.callCount == 1)
        #expect(spent.store.hasSpentWeek)
        #expect(spent.store.routingAccess == .none)

        let paid = FreeWeekTestHarness(responses: [.success(.paidActive)])
        paid.store.setUser("climber")
        #expect(await paid.store.startFreeWeek() == .paidActive)
        #expect(paid.granter.callCount == 1)

        let off = FreeWeekTestHarness(responses: [.success(.disabled)])
        off.store.setUser("climber")
        #expect(await off.store.startFreeWeek() == .failed)
        #expect(off.granter.callCount == 1)
    }

    @Test
    func aSpentWeekTheServerCouldNotDateIsStillSpent() async {
        let harness = FreeWeekTestHarness(responses: [.success(.alreadyUsed(nil))])
        harness.store.setUser("climber")

        #expect(await harness.store.startFreeWeek() == .alreadyUsed)
        #expect(harness.store.hasSpentWeek)
    }

    @Test
    func withTheSwitchOffNothingIsReadGrantedOrHonoured() async {
        let harness = FreeWeekTestHarness(isEnabled: false)
        let week = harness.week()
        harness.cache.store(week, for: "climber")
        harness.granter.responses = [.success(.granted(week))]

        harness.store.setUser("climber")

        #expect(harness.store.routingAccess == .none)
        #expect(harness.store.liveGrant == nil)
        #expect(harness.store.daysLeft == nil)
        #expect(await harness.store.startFreeWeek() == .failed)
        #expect(harness.granter.callCount == 0)
        await harness.store.refresh()
        #expect(harness.reader.readCount == 0)
    }

    @Test
    func signingOutDropsTheWeekAndTheNextAccountStartsFromNothing() async {
        let harness = FreeWeekTestHarness(record: .success(nil))
        harness.cache.store(harness.week(), for: "first")
        harness.store.setUser("first")
        #expect(harness.store.routingAccess == .live)

        harness.store.setUser(nil)
        #expect(harness.store.routingAccess == .none)
        #expect(harness.store.record == .unknown)

        harness.store.setUser("second")
        #expect(harness.store.liveGrant == nil)
        #expect(await freeWeekWaitUntil { harness.store.record == .absent })
    }

    @Test
    func theWeekEndedReportIsClaimedOncePerAccount() {
        let harness = FreeWeekTestHarness()
        harness.cache.store(harness.week(startingDaysAgo: 8), for: "climber")
        harness.store.setUser("climber")

        #expect(harness.store.claimExpiredGateReport())
        #expect(harness.store.claimExpiredGateReport() == false)

        let running = FreeWeekTestHarness()
        running.cache.store(running.week(), for: "climber")
        running.store.setUser("climber")
        #expect(running.store.claimExpiredGateReport() == false)
    }

    @Test
    func daysLeftRoundsUpAndNeverReadsZeroWhileTheWeekRuns() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let week = FreeWeekGrant(grantedAt: start, expiresAt: start.addingTimeInterval(7 * 86_400))

        #expect(week.daysLeft(at: start) == 7)
        #expect(week.daysLeft(at: start.addingTimeInterval(1)) == 7)
        #expect(week.daysLeft(at: start.addingTimeInterval(86_400 + 1)) == 6)
        #expect(week.daysLeft(at: start.addingTimeInterval(6 * 86_400 + 3_600)) == 1)
        #expect(week.daysLeft(at: start.addingTimeInterval(7 * 86_400 - 1)) == 1)
        #expect(week.daysLeft(at: start.addingTimeInterval(7 * 86_400)) == 0)
        #expect(week.isLive(at: start.addingTimeInterval(7 * 86_400)) == false)
    }

    @Test
    func theCallableAnswerIsReadStrictly() {
        let granted = FreeWeekGrantResponse(payload: [
            "status": "granted",
            "grantedAtMs": NSNumber(value: 1_800_000_000_000.0),
            "expiresAtMs": NSNumber(value: 1_800_604_800_000.0)
        ])
        #expect(granted == .granted(FreeWeekGrant(
            grantedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_604_800)
        )))

        // A grant with no window is not something the app can route on.
        #expect(FreeWeekGrantResponse(payload: ["status": "granted"]) == .unrecognized)
        #expect(FreeWeekGrantResponse(payload: ["status": "already_used"]) == .alreadyUsed(nil))
        #expect(FreeWeekGrantResponse(payload: ["status": "paid_active"]) == .paidActive)
        #expect(FreeWeekGrantResponse(payload: ["status": "disabled"]) == .disabled)
        #expect(FreeWeekGrantResponse(payload: ["status": "something_new"]) == .unrecognized)
        #expect(FreeWeekGrantResponse(payload: nil) == .unrecognized)
    }

    @Test
    func theSettingsRowCountsDaysAndIsSingularAtOne() {
        #expect(FreeWeekSettingsRow.title(daysLeft: 7) == "Free trial, 7 days left")
        #expect(FreeWeekSettingsRow.title(daysLeft: 2) == "Free trial, 2 days left")
        #expect(FreeWeekSettingsRow.title(daysLeft: 1) == "Free trial, 1 day left")
        #expect(FreeWeekSettingsRow.title(daysLeft: 0) == nil)
        #expect(FreeWeekSettingsRow.title(daysLeft: nil) == nil)
    }
}

/// A sleep that waits until a test opens it, for the timer that ends a week on screen.
private final class FreeWeekSleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var sleep: FreeWeekAccessStore.Sleep {
        { [self] _ in
            await withCheckedContinuation { continuation in
                lock.lock()
                if isOpen {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}
