import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

struct ProfileHeartRateSummaryTests {
    private struct Vector: Decodable {
        struct Case: Decodable {
            struct Climb: Decodable {
                let durationSeconds: Double
                let averageBpm: Int?
                let maxBpm: Int?
            }

            struct Expected: Decodable {
                let averageBpm: Int?
                let maxBpm: Int?
            }

            let name: String
            let climbs: [Climb]
            let expected: Expected
        }

        let cases: [Case]
    }

    @Test
    func derivationMatchesTheSharedVector() throws {
        for vectorCase in try Self.sharedVector().cases {
            let summary = ProfileHeartRateSummary.derive(
                from: vectorCase.climbs.map {
                    ProfileHeartRateSummary.Climb(
                        durationSeconds: $0.durationSeconds,
                        averageBpm: $0.averageBpm,
                        maxBpm: $0.maxBpm
                    )
                }
            )

            #expect(summary?.averageBpm == vectorCase.expected.averageBpm, "\(vectorCase.name)")
            #expect(summary?.maxBpm == vectorCase.expected.maxBpm, "\(vectorCase.name)")
            #expect(
                (summary == nil) ==
                    (vectorCase.expected.averageBpm == nil && vectorCase.expected.maxBpm == nil),
                "\(vectorCase.name)"
            )
        }
    }

    @Test
    func aStoredValueOutsideThePlausibleRangeReadsAsAbsent() {
        #expect(ProfileHeartRateSummary(averageBpm: 400, maxBpm: 0) == nil)
        #expect(ProfileHeartRateSummary(averageBpm: 140, maxBpm: 400)?.maxBpm == nil)
    }

    @Test
    func thePublishedPayloadCarriesTheAggregatesAndNothingFiner() {
        let payload = ProfileRepository.statsPayload(
            stats(heartRate: ProfileHeartRateSummary(averageBpm: 142, maxBpm: 178)),
            isHeartRatePublic: true
        )

        #expect(payload["average_heart_rate_bpm"] as? Int == 142)
        #expect(payload["max_heart_rate_bpm"] as? Int == 178)
        #expect(payload["heart_rate_public"] as? Bool == true)
        #expect(!payload.keys.contains { $0.localizedStandardContains("series") })
    }

    @Test
    func aClimberWithoutHeartRateClearsAnyPublishedAggregate() {
        let payload = ProfileRepository.statsPayload(stats(heartRate: nil), isHeartRatePublic: true)

        #expect(payload["average_heart_rate_bpm"] is FieldValue)
        #expect(payload["max_heart_rate_bpm"] is FieldValue)
    }

    @Test
    func aClimberWhoHidHeartRatePublishesNoneOfIt() {
        let payload = ProfileRepository.statsPayload(
            stats(heartRate: ProfileHeartRateSummary(averageBpm: 142, maxBpm: 178)),
            isHeartRatePublic: false
        )

        #expect(payload["heart_rate_public"] as? Bool == false)
        #expect(payload["average_heart_rate_bpm"] is FieldValue)
        #expect(payload["max_heart_rate_bpm"] is FieldValue)
    }

    @Test
    func heartRateIsShownUntilAClimberSwitchesItOff() {
        #expect(ProfileHeartRateVisibility.isPublic(stored: nil))
        #expect(ProfileHeartRateVisibility.isPublic(stored: true))
        #expect(!ProfileHeartRateVisibility.isPublic(stored: false))
        #expect(ProfileHeartRateVisibility.isPublic(stored: "false"))
    }

    @Test
    func averagesPerClimbDivideTheAllTimeTotalsByEveryRecordedClimb() {
        var snapshot = stats(heartRate: nil)
        snapshot.lifetimeTotalSteps = 10_000
        snapshot.lifetimeDurationSeconds = 5_000
        snapshot.totalClimbs = 4

        #expect(snapshot.averageStepsPerClimb == 2_500)
        #expect(snapshot.averageClimbDurationSeconds == 1_250)

        snapshot.totalClimbs = 0
        #expect(snapshot.averageStepsPerClimb == nil)
        #expect(snapshot.averageClimbDurationSeconds == nil)
    }

    private func stats(heartRate: ProfileHeartRateSummary?) -> ProfileStatsSnapshot {
        ProfileStatsSnapshot(
            totalClimbsCompleted: 0,
            totalFirstAscents: 0,
            achievementCounts: .zero,
            mostCompletedClimbId: nil,
            currentStreakWeeks: 0,
            bestStreakWeeks: 0,
            prMostSteps: 0,
            prLongestClimbSeconds: 0,
            prHighestSPM: 0,
            heartRate: heartRate
        )
    }

    private static func sharedVector() throws -> Vector {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let vectorURL = repoRoot.appending(
            path: "SharedTestVectors/profile-heart-rate-summary-vector.json"
        )
        return try JSONDecoder().decode(Vector.self, from: Data(contentsOf: vectorURL))
    }
}

struct ProfileHeartRateComparisonTests {
    @Test
    func aRowIsDrawnWhenEitherClimberHoldsTheNumber() {
        let comparison = ProfileHeartRateComparison(
            viewer: nil,
            other: ProfileHeartRateSummary(averageBpm: 142, maxBpm: 178),
            isOtherLoading: false
        )

        #expect(comparison.rows.map(\.kind) == [.average, .max])
        #expect(comparison.rows.allSatisfy { $0.viewerBpm == nil })
        #expect(ProfileHeartRateComparison.text(for: comparison.rows.first?.viewerBpm) == "-")
        #expect(ProfileHeartRateComparison.text(for: comparison.rows.first?.otherBpm) == "142 bpm")
    }

    @Test
    func theSectionIsAbsentWhenNeitherClimberHasHeartRate() {
        let comparison = ProfileHeartRateComparison(viewer: nil, other: nil, isOtherLoading: false)

        #expect(comparison.isEmpty)
    }

    @Test
    func aNumberOnlyOneSideHoldsKeepsOnlyItsOwnRow() {
        let comparison = ProfileHeartRateComparison(
            viewer: ProfileHeartRateSummary(averageBpm: nil, maxBpm: 181),
            other: ProfileHeartRateSummary(averageBpm: nil, maxBpm: 170),
            isOtherLoading: false
        )

        #expect(comparison.rows.map(\.kind) == [.max])
    }

    @Test
    func whileTheOtherClimberLoadsOnlyTheViewersNumbersHoldARow() {
        let viewerOnly = ProfileHeartRateComparison(
            viewer: ProfileHeartRateSummary(averageBpm: 140, maxBpm: 175),
            other: nil,
            isOtherLoading: true
        )
        let nobody = ProfileHeartRateComparison(
            viewer: nil,
            other: ProfileHeartRateSummary(averageBpm: 140, maxBpm: 175),
            isOtherLoading: true
        )

        #expect(viewerOnly.rows.map(\.kind) == [.average, .max])
        #expect(viewerOnly.rows.allSatisfy { $0.otherBpm == nil })
        #expect(nobody.isEmpty)
    }
}
