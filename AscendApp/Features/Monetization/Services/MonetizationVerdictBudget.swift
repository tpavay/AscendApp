import Foundation

/// One total budget for producing a post-purchase entitlement verdict.
///
/// Every segment shares this single deadline - serialized identity work, the RevenueCat
/// customer-info fetch, and server reconciliation - and it is never reset between them. Decomposing
/// the refresh differently therefore cannot lengthen the spinner a climber sits behind after a
/// charge, which a per-segment timeout would have allowed.
@MainActor
struct MonetizationVerdictBudget {
    /// Generous for one RevenueCat `logIn`/`logOut` serialization plus the rest of the refresh
    /// chain on an ordinary connection, short enough that the post-purchase spinner is not read as
    /// hung.
    static let defaultTotal = Duration.seconds(10)

    private let total: Duration
    private let sleeper: @Sendable (Duration) async throws -> Void

    init(
        total: Duration = MonetizationVerdictBudget.defaultTotal,
        sleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.total = total
        self.sleeper = sleeper
    }

    /// Runs `work` under the one shared deadline, collapsing the whole attempt to an explicit
    /// unresolved answer if any part of it outlasts the budget.
    ///
    /// Work that outlasts the budget is abandoned rather than cancelled: a RevenueCat identity
    /// mutation stopped midway would leave the identity ambiguous. Its task is therefore never
    /// retained for cancellation - it finishes on its own and the latch discards the late answer -
    /// so no cancellation can ever propagate into it, however cancellation-aware the layers below
    /// become. Only the deadline timer, which owns nothing but a sleep, is cancelled.
    func resolve(
        _ work: @escaping @MainActor () async -> MonetizationEntitlementRefresh
    ) async -> MonetizationEntitlementRefresh {
        let latch = VerdictLatch()

        Task { @MainActor in
            latch.finish(await work())
        }
        let expiry = Task { @MainActor [total, sleeper] in
            try? await sleeper(total)
            latch.finish(.unavailable(.refreshTimedOut))
        }

        let outcome = await latch.outcome
        expiry.cancel()
        return outcome
    }
}

/// Resolves once, for whichever of the attempt and the budget gets there first.
@MainActor
private final class VerdictLatch {
    private var continuation: CheckedContinuation<MonetizationEntitlementRefresh, Never>?
    private var settled: MonetizationEntitlementRefresh?

    var outcome: MonetizationEntitlementRefresh {
        get async {
            if let settled { return settled }

            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    func finish(_ outcome: MonetizationEntitlementRefresh) {
        guard settled == nil else { return }

        settled = outcome
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
