import Foundation
import Testing
@testable import AscendApp

/// The join-date rule, held to the same answers as the server by one shared vector
/// (`SharedTestVectors/pre-join-unmeasured-climb-vector.json`; the TypeScript side is
/// `functions/test/leaderboardStats.test.ts`).
struct PreJoinUnmeasuredClimbVectorTests {
    private struct Vector: Decodable {
        let accountCreatedAt: String
        let cases: [Case]

        struct Case: Decodable {
            let name: String
            let source: String
            let startedAt: String
            let steps: Int
            let durationSeconds: Double
            let deviceLeaderboardStatus: String
        }
    }

    private static func vector() throws -> Vector {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appending(path: "SharedTestVectors/pre-join-unmeasured-climb-vector.json")
        return try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
    }

    private static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string), "\(string)")
    }

    @Test
    func everySharedCaseGetsTheSameAnswerOnTheDevice() throws {
        let vector = try Self.vector()
        let created = try Self.date(vector.accountCreatedAt)
        #expect(vector.cases.count >= 7)

        for testCase in vector.cases {
            let source = try #require(WorkoutSource(rawValue: testCase.source), "\(testCase.name)")
            let status = ClimbPacePolicy.leaderboardStatus(
                origin: source.climbOrigin,
                steps: testCase.steps,
                duration: testCase.durationSeconds,
                startedAt: try Self.date(testCase.startedAt),
                accountCreatedAt: created
            )

            #expect(status.rawValue == testCase.deviceLeaderboardStatus, "\(testCase.name)")
        }
    }

    @Test
    func aDeviceThatDoesNotKnowTheDateLeavesTheVerdictToThePaceAndTheServer() {
        let status = ClimbPacePolicy.leaderboardStatus(
            origin: .healthImport,
            steps: 3_000,
            duration: 1_800,
            startedAt: Date(timeIntervalSince1970: 0),
            accountCreatedAt: nil
        )

        #expect(status == .eligible)
    }

    @Test
    func aClimbFromBeforeTheAccountStaysExcludedWhateverItsPace() throws {
        let created = try Self.date("2026-09-10T12:00:00Z")
        let before = try Self.date("2026-08-01T07:00:00Z")

        #expect(ClimbPacePolicy.leaderboardStatus(origin: .manual, steps: 3_000, duration: 1_800, startedAt: before, accountCreatedAt: created) == .excluded)
        #expect(ClimbPacePolicy.leaderboardStatus(origin: .manual, steps: 6_001, duration: 1_800, startedAt: before, accountCreatedAt: created) == .excluded)
    }

    @Test
    func theRefreshAnEditRunsAppliesTheRuleToTheClimbsOwnStart() throws {
        let created = try Self.date("2026-09-10T12:00:00Z")
        let history = Workout(
            name: "Stair Stepper",
            date: try Self.date("2026-08-01T07:00:00Z"),
            duration: 1_800,
            steps: 3_000,
            floors: Workout.stepsToFloors(3_000),
            source: .appleHealth
        )
        let current = Workout(
            name: "Stair Stepper",
            date: try Self.date("2026-10-01T07:00:00Z"),
            duration: 1_800,
            steps: 3_000,
            floors: Workout.stepsToFloors(3_000),
            source: .appleHealth
        )
        history.leaderboardStatus = .eligible
        current.leaderboardStatus = .excluded

        history.refreshLeaderboardStatus(accountCreatedAt: created)
        current.refreshLeaderboardStatus(accountCreatedAt: created)

        #expect(history.leaderboardStatus == .excluded)
        #expect(current.leaderboardStatus == .eligible)
    }
}
