import Foundation
import Testing
@testable import AscendApp

struct ShareStatResolverTests {
    @Test
    func splitsAreHiddenForManualWorkouts() {
        let workout = Workout(
            name: "Manual",
            duration: 600,
            steps: 800,
            floors: Workout.stepsToFloors(800, stepsPerFloor: 16),
            source: .manual
        )
        let resolver = makeResolver(workout: workout)

        #expect(resolver.resolve(.splits) == nil)
        #expect(!resolver.availableKinds().contains(.splits))
    }

    @Test
    func splitsAreHiddenForHeadphoneWorkoutsWithoutRecordedTimeline() {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 500,
            trackingMode: .justClimb,
            climbId: nil,
            targetStepCount: 900,
            stopReason: .userStopped
        )
        let workout = Workout(
            name: "Just Climb",
            duration: 600,
            steps: 900,
            floors: Workout.stepsToFloors(900, stepsPerFloor: 16),
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
        let resolver = makeResolver(workout: workout)

        #expect(resolver.resolve(.splits) == nil)
        #expect(!resolver.availableKinds().contains(.splits))
    }

    @Test
    func splitsResolveRowsFromRecordedTimeline() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800)
        let splitCurve = LiveReplaySplitCurve(
            intervalSeconds: 30,
            steps: [0, 40, 80, 130, 180]
        )
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 900,
            climbId: "test-climb",
            targetStepCount: 180,
            stopReason: .targetReached,
            splitCurve: splitCurve
        )
        let workout = Workout(
            name: "Live Climb",
            date: startedAt,
            duration: 120,
            steps: 180,
            floors: Workout.stepsToFloors(180, stepsPerFloor: 16),
            heartRateTimeSeries: [
                HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(10), heartRate: 150),
                HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(50), heartRate: 160),
                HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(70), heartRate: 170),
                HeartRateDataPoint(timestamp: startedAt.addingTimeInterval(110), heartRate: 180)
            ],
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
        let resolver = makeResolver(workout: workout, splitTargetSteps: 180)

        let tile = try #require(resolver.resolve(.splits))
        #expect(tile.label == "SPLITS")
        #expect(tile.value == "2 SEGMENTS")
        #expect(resolver.availableKinds().contains(.splits))

        let splits = try #require(resolver.resolveSplits())
        #expect(splits.rows.count == 2)
        #expect(splits.rows[0].rangeText == "0:00-1:00")
        #expect(splits.rows[0].stepsText == "80")
        #expect(splits.rows[0].spmText == "80")
        #expect(splits.rows[0].heartRateText == "155")
        #expect(splits.rows[1].rangeText == "1:00-2:00")
        #expect(splits.rows[1].stepsText == "100")
        #expect(splits.rows[1].spmText == "100")
        #expect(splits.rows[1].heartRateText == "175")
        #expect(splits.hasHeartRate)
    }

    @Test
    func climbRankAndRankWithTotalResolveAsSeparateShareStats() throws {
        let workout = Workout(
            name: "Live Climb",
            duration: 600,
            steps: 800,
            floors: Workout.stepsToFloors(800, stepsPerFloor: 16),
            source: .headphoneMotion
        )
        let resolver = makeResolver(
            workout: workout,
            climbName: "Empire State Building",
            climbRank: 1,
            climbRankTotal: 2_460
        )

        let rank = try #require(resolver.resolve(.climbRank))
        #expect(rank.label == "RANK")
        #expect(rank.value == "#1")

        let rankWithTotal = try #require(resolver.resolve(.climbRankWithTotal))
        #expect(rankWithTotal.label == "RANK / TOTAL")
        #expect(rankWithTotal.value == "#1 / 2,460")

        #expect(resolver.availableKinds().contains(.climbRank))
        #expect(resolver.availableKinds().contains(.climbRankWithTotal))
    }

    @Test
    func climbRankWithTotalIsHiddenWithoutTotal() {
        let workout = Workout(
            name: "Live Climb",
            duration: 600,
            steps: 800,
            floors: Workout.stepsToFloors(800, stepsPerFloor: 16),
            source: .headphoneMotion
        )
        let resolver = makeResolver(
            workout: workout,
            climbName: "Empire State Building",
            climbRank: 1,
            climbRankTotal: nil
        )

        #expect(resolver.resolve(.climbRank) != nil)
        #expect(resolver.resolve(.climbRankWithTotal) == nil)
        #expect(!resolver.availableKinds().contains(.climbRankWithTotal))
    }

    private func makeResolver(
        workout: Workout,
        climbName: String? = nil,
        climbRank: Int? = nil,
        climbRankTotal: Int? = nil,
        splitTargetSteps: Int? = nil
    ) -> ShareStatResolver {
        ShareStatResolver(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climbName: climbName,
            climbRank: climbRank,
            climbRankTotal: climbRankTotal,
            splitTargetSteps: splitTargetSteps
        )
    }
}
