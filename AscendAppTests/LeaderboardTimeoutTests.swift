import Foundation
import Testing
@testable import AscendApp

struct LeaderboardTimeoutTests {
    @Test
    func timeoutFailsSlowOperations() async {
        await #expect(throws: LeaderboardTimeoutError.operationTimedOut) {
            try await withLeaderboardTimeout(seconds: 0.05) {
                try await Task.sleep(for: .milliseconds(200))
                return 1
            }
        }
    }
}
