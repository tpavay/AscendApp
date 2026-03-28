//
//  WorkoutShareCardComposerTests.swift
//  AscendAppTests
//
//  Created by Codex on 3/28/26.
//

import XCTest
@testable import AscendApp

final class WorkoutShareCardComposerTests: XCTestCase {
    private let composer = WorkoutShareCardComposer()

    func testUsesVerticalClimbAsHeroWhenAvailable() {
        let workout = makeWorkout(
            duration: 2_027,
            steps: 2_502,
            floors: 156,
            caloriesBurned: 511
        )

        let composition = composer.compose(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: 8,
            preferredMetric: .steps
        )

        XCTAssertEqual(composition.heroStat.kind, .verticalClimb)
        XCTAssertEqual(composition.heroStat.label, "FEET CLIMBED")
        XCTAssertEqual(composition.heroStat.value, "1,668")
        XCTAssertEqual(composition.supportingStats.map(\.kind), [.preferredMetric, .duration, .calories])
        XCTAssertEqual(composition.supportingStats.map(\.value), ["2,502", "33:47", "511"])
    }

    func testUsesPreferredFloorsMetricWhenNoVerticalClimbIsAvailable() {
        let workout = makeWorkout(
            duration: 1_800,
            steps: 0,
            floors: 42,
            caloriesBurned: 300
        )

        let composition = composer.compose(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: 8,
            preferredMetric: .floors
        )

        XCTAssertEqual(composition.heroStat.kind, .preferredMetric)
        XCTAssertEqual(composition.heroStat.label, "FLOORS")
        XCTAssertEqual(composition.heroStat.value, "42")
        XCTAssertEqual(composition.supportingStats.map(\.kind), [.duration, .calories, .pace])
        XCTAssertEqual(composition.supportingStats.map(\.value), ["30:00", "300", "1"])
    }

    func testDurationOnlyWorkoutOmitsSupportingRailContent() {
        let workout = makeWorkout(duration: 1_245, steps: 0, floors: 0)

        let composition = composer.compose(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: 8,
            preferredMetric: .steps
        )

        XCTAssertEqual(composition.heroStat.kind, .duration)
        XCTAssertEqual(composition.heroStat.value, "20:45")
        XCTAssertTrue(composition.supportingStats.isEmpty)
    }

    func testIncludesCaloriesAndHeartRateWhenQualified() {
        let workout = makeWorkout(
            duration: 1_500,
            steps: 0,
            floors: 0,
            avgHeartRate: 151,
            caloriesBurned: 412
        )

        let composition = composer.compose(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: 8,
            preferredMetric: .steps
        )

        XCTAssertEqual(composition.heroStat.kind, .duration)
        XCTAssertEqual(composition.supportingStats.map(\.kind), [.calories, .avgHeartRate])
        XCTAssertEqual(composition.supportingStats.map(\.value), ["412", "151"])
    }

    func testIncludesAddedWeightInSupportingStats() {
        let workout = makeWorkout(
            duration: 1_500,
            steps: 0,
            floors: 0,
            weightConfiguration: WeightConfiguration(
                entries: [
                    WeightEntry(equipmentType: .weightedVest, weightValue: 20, isEnabled: true),
                ]
            )
        )

        let composition = composer.compose(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: 8,
            preferredMetric: .steps
        )

        XCTAssertEqual(composition.heroStat.kind, .duration)
        XCTAssertEqual(composition.supportingStats.map(\.kind), [.addedWeight])
        XCTAssertEqual(composition.supportingStats.first?.value, "20 LB")
    }

    func testLimitsSupportingStatsToQualifiedStatsOnly() {
        let workout = makeWorkout(
            duration: 1_260,
            steps: 640,
            floors: 0
        )

        let composition = composer.compose(
            workout: workout,
            measurementSystem: .imperial,
            stepHeight: 0,
            preferredMetric: .steps
        )

        XCTAssertEqual(composition.heroStat.kind, .preferredMetric)
        XCTAssertEqual(composition.supportingStats.map(\.kind), [.duration, .pace])
        XCTAssertEqual(composition.supportingStats.map(\.value), ["21:00", "30"])
    }

    private func makeWorkout(
        duration: TimeInterval,
        steps: Int,
        floors: Int,
        avgHeartRate: Int? = nil,
        caloriesBurned: Int? = nil,
        weightConfiguration: WeightConfiguration? = nil
    ) -> Workout {
        Workout(
            name: "Workout",
            date: Date(timeIntervalSince1970: 1_711_581_200),
            duration: duration,
            steps: steps,
            floors: floors,
            stepsPerFloor: 16,
            avgHeartRate: avgHeartRate,
            caloriesBurned: caloriesBurned,
            weightConfiguration: weightConfiguration
        )
    }
}
