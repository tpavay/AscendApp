import Foundation
import Testing
@testable import AscendApp

/// Pins the iOS split-curve normalizer against the Cloud Functions twin
/// (`functions/src/liveReplaySplitNormalization.ts`). Both sides read the same vector, so
/// re-anchoring buckets on one side alone fails here instead of silently publishing a
/// replay curve that disagrees with the client's own chart and Best Efforts math.
struct LiveReplaySplitNormalizationParityTests {
    struct ParityVector: Decodable {
        let cases: [ParityCase]
    }

    struct ParityCase: Decodable {
        let name: String
        let splitIntervalSeconds: Int
        let splitSteps: [Int]
        let finalDurationSeconds: Int
        let finalSteps: Int
        let expected: [Int]
    }

    @Test
    func swiftNormalizationMatchesTheSharedParityVector() throws {
        let vector = try Self.sharedParityVector()
        #expect(vector.cases.count >= 7)

        for parityCase in vector.cases {
            let actual = LiveClimbWorkoutSummaryData.normalizedSplitSteps(
                parityCase.splitSteps,
                intervalSeconds: parityCase.splitIntervalSeconds,
                finalDurationSeconds: parityCase.finalDurationSeconds,
                finalSteps: parityCase.finalSteps
            )
            #expect(
                actual == parityCase.expected,
                "case \(parityCase.name) diverged from the shared vector"
            )
        }
    }

    private static func sharedParityVector() throws -> ParityVector {
        // Navigate from this test file to the repo-root shared vector so Swift and the
        // TypeScript functions test assert against the exact same cases.
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent() // AscendAppTests/
            .deletingLastPathComponent() // repo root
        let vectorURL = repoRoot.appending(
            path: "SharedTestVectors/live-replay-split-normalization-vector.json"
        )
        let data = try Data(contentsOf: vectorURL)
        return try JSONDecoder().decode(ParityVector.self, from: data)
    }
}
