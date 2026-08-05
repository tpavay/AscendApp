import Foundation
import Testing
@testable import AscendApp

/// The post-purchase verdict spends one total budget, not one per segment. These drive an injected
/// clock rather than waiting, so the timeout behaviour is deterministic and instant.
@MainActor
struct MonetizationVerdictBudgetTests {
    @Test
    func aVerdictThatArrivesInsideTheBudgetIsReportedUnchanged() async {
        let sleeper = ControlledBudgetSleeper()
        let budget = MonetizationVerdictBudget(total: .seconds(10), sleeper: sleeper.sleep)

        let outcome = await budget.resolve { .refreshed(.active(["app_access"])) }

        #expect(outcome == .refreshed(.active(["app_access"])))
    }

    @Test
    func anExpiredBudgetCollapsesTheAttemptToAnUnresolvedTimeout() async {
        let sleeper = ControlledBudgetSleeper()
        let budget = MonetizationVerdictBudget(total: .seconds(10), sleeper: sleeper.sleep)
        let work = ControlledRefreshWork()

        let resolution = Task { await budget.resolve(work.run) }
        await sleeper.waitUntilSleeping()
        sleeper.expireBudget()

        #expect(await resolution.value == .unavailable(.refreshTimedOut))
        #expect(sleeper.requestedTotals == [.seconds(10)])

        // Abandoning the wait must not abandon the work, which owns identity state.
        work.finish(with: .refreshed(.active(["app_access"])))
    }

    /// The budget is started once for the whole attempt, so a slow first segment leaves less for
    /// the rest rather than handing each segment a fresh ten seconds.
    @Test
    func theBudgetIsSpentOnceAcrossEverySegmentOfOneAttempt() async {
        let sleeper = ControlledBudgetSleeper()
        let budget = MonetizationVerdictBudget(total: .seconds(10), sleeper: sleeper.sleep)
        let firstSegment = ControlledRefreshWork()
        let secondSegment = ControlledRefreshWork()

        let resolution = Task {
            await budget.resolve {
                _ = await firstSegment.run()
                return await secondSegment.run()
            }
        }
        await sleeper.waitUntilSleeping()

        firstSegment.finish(with: .refreshed(.inactive))
        await secondSegment.waitUntilRunning()
        sleeper.expireBudget()

        #expect(await resolution.value == .unavailable(.refreshTimedOut))
        #expect(sleeper.requestedTotals == [.seconds(10)])

        secondSegment.finish(with: .refreshed(.active(["app_access"])))
    }

    @Test
    func theShippedBudgetIsTenSeconds() {
        #expect(MonetizationVerdictBudget.defaultTotal == .seconds(10))
    }
}

@MainActor
final class ControlledBudgetSleeper {
    private(set) var requestedTotals: [Duration] = []

    private var budgetContinuation: CheckedContinuation<Void, any Error>?
    private var startObserver: CheckedContinuation<Void, Never>?

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] total in
            try await beginSleeping(for: total)
        }
    }

    func waitUntilSleeping() async {
        guard requestedTotals.isEmpty else { return }

        await withCheckedContinuation { continuation in
            startObserver = continuation
        }
    }

    func expireBudget() {
        budgetContinuation?.resume()
        budgetContinuation = nil
    }

    private func beginSleeping(for total: Duration) async throws {
        requestedTotals.append(total)
        startObserver?.resume()
        startObserver = nil

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                budgetContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor in self.cancelSleeping() }
        }
    }

    private func cancelSleeping() {
        budgetContinuation?.resume(throwing: CancellationError())
        budgetContinuation = nil
    }
}

/// One segment of a refresh, held open until the test decides it lands.
@MainActor
private final class ControlledRefreshWork {
    private var continuation: CheckedContinuation<MonetizationEntitlementRefresh, Never>?
    private var startObserver: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private var settled: MonetizationEntitlementRefresh?

    var run: @MainActor () async -> MonetizationEntitlementRefresh {
        { [self] in await begin() }
    }

    func waitUntilRunning() async {
        guard !hasStarted else { return }

        await withCheckedContinuation { continuation in
            startObserver = continuation
        }
    }

    func finish(with outcome: MonetizationEntitlementRefresh) {
        guard settled == nil else { return }

        settled = outcome
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    private func begin() async -> MonetizationEntitlementRefresh {
        hasStarted = true
        startObserver?.resume()
        startObserver = nil

        if let settled { return settled }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
