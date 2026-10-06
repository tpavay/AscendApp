import Foundation
import Testing

/// Serializes the tests that drive an `SKTestSession`.
///
/// A StoreKit test session is process-wide: `resetToDefaultState()` and `clearTransactions()` in
/// one suite erase the purchase another suite is in the middle of asserting on. Suite-level
/// `.serialized` orders a suite's own cases, not two suites against each other, so every suite
/// that opens a session carries this trait.
struct StoreKitTestSessionTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: () async throws -> Void
    ) async throws {
        await StoreKitTestSessionGate.shared.acquire()
        do {
            try await function()
        } catch {
            await StoreKitTestSessionGate.shared.release()
            throw error
        }
        await StoreKitTestSessionGate.shared.release()
    }
}

extension Trait where Self == StoreKitTestSessionTrait {
    /// This test opens a StoreKit test session, so it may not overlap another that does.
    static var usesStoreKitTestSession: Self { Self() }
}

/// A FIFO mutex whose critical section spans `await`s, so a waiter suspends rather than blocking a
/// thread the test it is waiting on still needs.
private actor StoreKitTestSessionGate {
    static let shared = StoreKitTestSessionGate()

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }

        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard waiters.isEmpty else {
            waiters.removeFirst().resume()
            return
        }

        isHeld = false
    }
}
