import Foundation
import Testing

/// Serializes the suites that read or write process-global `SentrySDK` state.
///
/// There is one Sentry client per process. `SentryCrashContextEnvelopeEvidenceTests` starts a real
/// one and holds it for several seconds - a 5s flush plus up to a hundred envelope polls, twice -
/// while `SentryDiagnosticsConfigurationTests` asserts `!SentrySDK.isEnabled` to prove a dev build
/// initialises nothing. Both claims are load-bearing and neither may be relaxed, so the two suites
/// have to take turns instead.
///
/// Suite-level `.serialized` does not cover this: it orders a suite's own cases, not two suites
/// against each other, and Swift Testing runs distinct suites in parallel. Without this gate the
/// config suite can land inside the evidence suite's start/close window and fail with "another
/// suite left an SDK client running" - a flake with no defect behind it.
///
/// Apply to any suite that starts, closes, or interrogates the shared SDK client.
struct SentrySDKOwnershipTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: () async throws -> Void
    ) async throws {
        await SentrySDKGate.shared.acquire()
        do {
            try await function()
        } catch {
            await SentrySDKGate.shared.release()
            throw error
        }
        await SentrySDKGate.shared.release()
    }
}

extension Trait where Self == SentrySDKOwnershipTrait {
    /// This suite owns the one process-wide Sentry client while it runs, so no other may.
    static var ownsTheSentrySDK: Self { Self() }
}

/// A FIFO mutex whose critical section spans `await`s, so a waiter suspends rather than blocking a
/// thread the suite it is waiting on still needs.
private actor SentrySDKGate {
    static let shared = SentrySDKGate()

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
