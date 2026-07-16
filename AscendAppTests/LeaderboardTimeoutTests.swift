import Testing
@testable import AscendApp

struct LeaderboardTimeoutTests {
    @Test
    func timeoutCompletesWhenOperationDoesNotCooperateWithCancellation() async {
        await #expect(throws: LeaderboardTimeoutError.operationTimedOut) {
            let _: Int = try await withLeaderboardTimeout(seconds: 0.1) {
                try await withCheckedThrowingContinuation { (_: CheckedContinuation<Int, Error>) in
                    // Intentionally never resumes to simulate a non-cooperative async dependency.
                }
            }
        }
    }
}
