import Foundation
import Testing
@testable import AscendApp

struct BestEffortRankingBuilderTests {
    @Test
    func benchmarkDefinitionsMatchBestEffortsDesign() {
        #expect(BestEffortMetric.stepTargets == [500, 1_000, 2_000, 3_000, 5_000, 10_000])
        #expect(BestEffortMetric.timeWindowMinutes == [5, 10, 20, 30, 45, 60])
        #expect(BestEffortMetric.workoutRecordDefinitions.allSatisfy { !$0.requiresTimeline })
        #expect(BestEffortMetric.liveSplitDefinitions.allSatisfy { $0.requiresTimeline })
        #expect(BestEffortMetric.allDefinitions == BestEffortMetric.workoutRecordDefinitions + BestEffortMetric.liveSplitDefinitions)
    }

    @Test
    func ranksStepFirstEffortsAcrossAllTimeAndYear() throws {
        #expect(BestEffortScope.allCases == [.allTime, .thisYear])

        let referenceDate = date(year: 2026, month: 5, day: 10)
        let olderBest = makeWorkout(
            name: "Older Big Climb",
            date: date(year: 2025, month: 9, day: 1),
            duration: 2_400,
            steps: 4_500
        )
        let thisYearBest = makeWorkout(
            name: "This Year Climb",
            date: date(year: 2026, month: 4, day: 20),
            duration: 1_800,
            steps: 3_200
        )

        let workouts = [thisYearBest, olderBest]

        let allTime = BestEffortRankingBuilder.board(
            from: workouts,
            scope: .allTime,
            context: .all,
            referenceDate: referenceDate
        )
        let year = BestEffortRankingBuilder.board(
            from: workouts,
            scope: .thisYear,
            context: .all,
            referenceDate: referenceDate
        )

        let allTimeMostSteps = try #require(allTime.category(.mostSteps)?.efforts.first)
        let yearMostSteps = try #require(year.category(.mostSteps)?.efforts.first)

        #expect(allTimeMostSteps.workout.id == olderBest.id)
        #expect(allTimeMostSteps.sentence == "Most steps ever")
        #expect(yearMostSteps.workout.id == thisYearBest.id)
        #expect(yearMostSteps.sentence == "Most steps this year")
        #expect(year.allEfforts.allSatisfy { !$0.metric.id.lowercased().contains("floor") })
    }

    @Test
    func filtersWeightedContextWithoutUsingFloors() throws {
        let referenceDate = date(year: 2026, month: 5, day: 10)
        let weighted = makeWorkout(
            name: "Weighted Climb",
            date: referenceDate,
            duration: 1_800,
            steps: 2_800,
            weightConfiguration: WeightConfiguration(entries: [
                WeightEntry(equipmentType: .weightedVest, weightValue: 20)
            ])
        )
        let bodyweight = makeWorkout(
            name: "Bodyweight Climb",
            date: referenceDate,
            duration: 1_800,
            steps: 4_000
        )

        let board = BestEffortRankingBuilder.board(
            from: [bodyweight, weighted],
            scope: .allTime,
            context: .weighted,
            referenceDate: referenceDate
        )

        let mostSteps = try #require(board.category(.mostSteps)?.efforts.first)
        #expect(mostSteps.workout.id == weighted.id)
        #expect(mostSteps.sentence == "Most weighted steps ever")
        #expect(board.allEfforts.allSatisfy { $0.workout.hasWeights })
    }

    @Test
    func exactWeightLoadoutContextSeparatesFullWeightCombos() throws {
        let referenceDate = date(year: 2026, month: 5, day: 10)
        let vestOnly = makeWorkout(
            name: "20 lb Vest",
            date: referenceDate,
            duration: 1_800,
            steps: 3_000,
            weightConfiguration: WeightConfiguration(entries: [
                WeightEntry(equipmentType: .weightedVest, weightValue: 20)
            ])
        )
        let heavierVest = makeWorkout(
            name: "40 lb Vest",
            date: referenceDate,
            duration: 1_800,
            steps: 4_000,
            weightConfiguration: WeightConfiguration(entries: [
                WeightEntry(equipmentType: .weightedVest, weightValue: 40)
            ])
        )
        let vestAndAnkle = makeWorkout(
            name: "Vest and Ankle",
            date: referenceDate,
            duration: 1_800,
            steps: 5_000,
            weightConfiguration: WeightConfiguration(entries: [
                WeightEntry(equipmentType: .weightedVest, weightValue: 20),
                WeightEntry(equipmentType: .ankleWeights, weightValue: 5)
            ])
        )

        let exactLoadout = try #require(vestOnly.weightLoadoutKey)
        let board = BestEffortRankingBuilder.board(
            from: [vestAndAnkle, heavierVest, vestOnly],
            scope: .allTime,
            context: .exactWeight(exactLoadout),
            referenceDate: referenceDate
        )

        let mostSteps = try #require(board.category(.mostSteps)?.efforts.first)
        #expect(mostSteps.workout.id == vestOnly.id)
        #expect(mostSteps.sentence == "Most steps with 20 lb vest ever")

        let availableContexts = BestEffortRankingBuilder.availableContexts(from: [vestAndAnkle, heavierVest, vestOnly])
        let vestAndAnkleLoadout = try #require(vestAndAnkle.weightLoadoutKey)
        let heavierVestLoadout = try #require(heavierVest.weightLoadoutKey)
        #expect(availableContexts.contains(.exactWeight(exactLoadout)))
        #expect(availableContexts.contains(.exactWeight(vestAndAnkleLoadout)))
        #expect(availableContexts.contains(.exactWeight(heavierVestLoadout)))
    }

    @Test
    func timelineEffortsUseSampledSegmentsOnly() throws {
        let referenceDate = date(year: 2026, month: 5, day: 10)
        let liveWorkout = makeLiveClimbWorkout(
            name: "Sampled Live Climb",
            date: referenceDate,
            duration: 300,
            steps: 3_000,
            splitSteps: [0, 400, 1_000, 2_000, 2_600, 3_000]
        )
        let importWithoutTimeline = makeWorkout(
            name: "Apple Health Import",
            date: referenceDate,
            duration: 300,
            steps: 5_000,
            source: .appleHealth
        )

        let board = BestEffortRankingBuilder.board(
            from: [importWithoutTimeline, liveWorkout],
            scope: .allTime,
            context: .all,
            referenceDate: referenceDate
        )

        let fastestThousand = try #require(board.category(.fastestStepTarget(steps: 1_000))?.efforts.first)
        let mostStepsInFive = try #require(board.category(.mostStepsInTime(minutes: 5))?.efforts.first)

        #expect(fastestThousand.workout.id == liveWorkout.id)
        #expect(fastestThousand.valueText == "1:00")
        #expect(fastestThousand.detailText.contains("2:00-3:00"))
        #expect(mostStepsInFive.workout.id == liveWorkout.id)
        #expect(mostStepsInFive.valueText == "3,000 steps")
    }

    @Test
    func workoutPrimaryEffortPrefersAllTimeRankBeforeYearlyRank() throws {
        let referenceDate = date(year: 2026, month: 5, day: 10)
        let workout = makeWorkout(
            name: "Fast Climb",
            date: referenceDate,
            duration: 600,
            steps: 1_800
        )
        let longerWorkout = makeWorkout(
            name: "Longer Climb",
            date: date(year: 2025, month: 3, day: 1),
            duration: 3_600,
            steps: 3_000
        )

        let primary = try #require(BestEffortRankingBuilder.primaryEffort(
            for: workout,
            from: [workout, longerWorkout],
            referenceDate: referenceDate
        ))

        #expect(primary.sentence == "Highest average SPM ever")
    }

    @Test
    func primaryEffortsLookupMatchesSingleWorkoutPrimaryEffort() throws {
        let referenceDate = date(year: 2026, month: 5, day: 10)
        let fastWorkout = makeWorkout(
            name: "Fast Climb",
            date: referenceDate,
            duration: 600,
            steps: 1_800
        )
        let longWorkout = makeWorkout(
            name: "Long Climb",
            date: date(year: 2025, month: 3, day: 1),
            duration: 3_600,
            steps: 3_000
        )
        let workouts = [fastWorkout, longWorkout]

        let lookup = BestEffortRankingBuilder.primaryEffortsByWorkoutID(
            from: workouts,
            referenceDate: referenceDate
        )
        let fastPrimary = try #require(BestEffortRankingBuilder.primaryEffort(
            for: fastWorkout,
            from: workouts,
            referenceDate: referenceDate
        ))

        #expect(lookup[fastWorkout.id]?.id == fastPrimary.id)
        #expect(lookup[fastWorkout.id]?.sentence == "Highest average SPM ever")
    }

    private func makeWorkout(
        name: String,
        date: Date,
        duration: TimeInterval,
        steps: Int,
        source: WorkoutSource = .manual,
        weightConfiguration: WeightConfiguration? = nil
    ) -> Workout {
        Workout(
            name: name,
            date: date,
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: source,
            weightConfiguration: weightConfiguration
        )
    }

    private func makeLiveClimbWorkout(
        name: String,
        date: Date,
        duration: TimeInterval,
        steps: Int,
        splitSteps: [Int]
    ) -> Workout {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: splitSteps.count,
            climbId: "test-climb",
            targetStepCount: steps,
            stopReason: .targetReached,
            splitCurve: LiveReplaySplitCurve(intervalSeconds: 60, steps: splitSteps)
        )

        return Workout(
            name: name,
            date: date,
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12
        )) ?? Date()
    }
}

private extension BestEffortBoard {
    func category(_ metric: BestEffortMetric) -> BestEffortCategoryRanking? {
        sections
            .flatMap(\.categories)
            .first { $0.metric == metric }
    }
}
