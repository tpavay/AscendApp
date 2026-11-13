import Foundation
import os.lock
@testable import AscendApp

/// A clock a test moves by hand.
final class FreeWeekTestClock: Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        state = OSAllocatedUnfairLock(initialState: date)
    }

    var now: Date {
        state.withLock { $0 }
    }

    func advance(days: Double) {
        state.withLock { $0 = $0.addingTimeInterval(days * 86_400) }
    }
}

struct FreeWeekTestError: Error {}

@MainActor
final class FreeWeekTestReader: FreeWeekRecordReading {
    var result: Result<FreeWeekGrant?, any Error>
    /// When set, a read waits here instead of answering, so a test can outrun it.
    var suspendsReads = false
    private(set) var readCount = 0

    init(result: Result<FreeWeekGrant?, any Error> = .success(nil)) {
        self.result = result
    }

    func readRecord(userID: String) async throws -> FreeWeekGrant? {
        readCount += 1
        if suspendsReads {
            try await Task.sleep(for: .seconds(3_600))
        }
        return try result.get()
    }
}

@MainActor
final class FreeWeekTestGranter: FreeWeekGranting {
    /// One entry per call, in order. The last entry answers every call after it.
    var responses: [Result<FreeWeekGrantResponse, any Error>]
    private(set) var callCount = 0

    init(responses: [Result<FreeWeekGrantResponse, any Error>]) {
        self.responses = responses
    }

    func startFreeWeek() async throws -> FreeWeekGrantResponse {
        let index = min(callCount, responses.count - 1)
        callCount += 1
        return try responses[index].get()
    }
}

@MainActor
struct FreeWeekTestHarness {
    let store: FreeWeekAccessStore
    let reader: FreeWeekTestReader
    let granter: FreeWeekTestGranter
    let cache: FreeWeekRecordCache
    let clock: FreeWeekTestClock

    /// - Parameter sleep: Stands in for both the read deadline and the timer that ends a week on
    ///   screen. The default never fires inside a test.
    init(
        isEnabled: Bool = true,
        record: Result<FreeWeekGrant?, any Error> = .success(nil),
        responses: [Result<FreeWeekGrantResponse, any Error>] = [.failure(FreeWeekTestError())],
        clock: FreeWeekTestClock = FreeWeekTestClock(),
        sleep: @escaping FreeWeekAccessStore.Sleep = { _ in try await Task.sleep(for: .seconds(3_600)) }
    ) {
        let reader = FreeWeekTestReader(result: record)
        let granter = FreeWeekTestGranter(responses: responses)
        let cache = FreeWeekRecordCache(
            userDefaults: UserDefaults(suiteName: "FreeWeekTests-\(UUID().uuidString)")!
        )
        self.reader = reader
        self.granter = granter
        self.cache = cache
        self.clock = clock
        store = FreeWeekAccessStore(
            reader: { reader },
            granter: { granter },
            cache: cache,
            featureFlags: Self.featureFlags(isEnabled: isEnabled),
            now: { clock.now },
            sleep: sleep
        )
    }

    static func featureFlags(isEnabled: Bool) -> RemoteFeatureFlagStore {
        RemoteFeatureFlagStore(
            snapshot: .resolving(remoteValues: [RemoteFeatureFlag.freeWeekAfterDecline.key: isEnabled])
        )
    }

    func week(startingDaysAgo days: Double = 0) -> FreeWeekGrant {
        let grantedAt = clock.now.addingTimeInterval(-days * 86_400)
        return FreeWeekGrant(grantedAt: grantedAt, expiresAt: grantedAt.addingTimeInterval(7 * 86_400))
    }
}

/// Waits for work the code under test started on its own unstructured tasks.
///
/// Bounded by a wall clock rather than a number of yields: the full suite runs thousands of tests
/// in one process, and under that load a fixed count of scheduler hops is not a promise that
/// another task has had its turn. The bound is generous for the same reason - a hosted suite running
/// alongside can hold the main actor for tens of seconds - and it is only ever spent on a failure.
@MainActor
func freeWeekWaitUntil(
    timeout: Duration = .seconds(60),
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}
