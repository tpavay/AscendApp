import Foundation
import Testing

/// Serializes the tests that screenshot a real `UIWindow`.
///
/// The test host has exactly one window scene, and every hosting suite borrows it. A second suite
/// bringing its window up mid-capture pushes the first host out of the visible hierarchy, so that
/// host's appearance transition never completes and its capture times out. Suite-level
/// `.serialized` does not cover this: it orders a suite's own cases, not two suites against each
/// other.
///
/// Apply to any suite that puts a view in a window and reads the pixels back.
struct HostedWindowTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: () async throws -> Void
    ) async throws {
        await HostedWindowGate.shared.acquire()
        do {
            try await function()
        } catch {
            await HostedWindowGate.shared.release()
            throw error
        }
        await HostedWindowGate.shared.release()
    }
}

extension Trait where Self == HostedWindowTrait {
    /// This test hosts a view in the shared window scene, so it may not overlap another that does.
    static var hostsAWindow: Self { Self() }
}

/// A FIFO mutex whose critical section spans `await`s, so a waiter suspends rather than blocking a
/// thread the test it is waiting on still needs.
private actor HostedWindowGate {
    static let shared = HostedWindowGate()

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
