import Testing

/// SCRATCH - never merge. Forces a hung test so one real `iOS Verify (Staging)`
/// job proves that a hang now concludes `failure`, not `cancelled` (#571).
@Suite struct HangProofScratchTests {
    @Test func aTestThatNeverFinishes() async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}
