//
//  WorkoutImportAnalyticsEventTests.swift
//  AscendAppTests
//
//  Created by Codex on 4/6/26.
//

import Foundation
import Testing
@testable import AscendApp

struct WorkoutImportAnalyticsEventTests {
    @Test
    func startedUsesLinkedOnlySourceMixForLinkedCandidate() {
        let candidate = ImportedWorkoutCandidate.hevy(
            workoutID: "hevy_123",
            workoutTitle: "Morning Session",
            startDate: Date(timeIntervalSince1970: 1_775_390_400),
            endDate: Date(timeIntervalSince1970: 1_775_392_200),
            duration: 1_800,
            metricValue: 1_200,
            metricType: .steps,
            matchingAppleHealthSample: makeAppleHealthSample(id: "ah_123")
        )

        let record = WorkoutImportAnalyticsEvent
            .started(mode: .single, candidates: [candidate])
            .record

        #expect(record.name == "workout_import_started")
        #expect(record.parameters["import_mode"] == .string("single"))
        #expect(record.parameters["candidate_count_bucket"] == .string("one"))
        #expect(record.parameters["source_mix"] == .string("linked_only"))
    }

    @Test
    func finishedUsesPartialSuccessForMixedBatch() {
        let candidates = [
            ImportedWorkoutCandidate.appleHealth(sample: makeAppleHealthSample(id: "ah_1")),
            ImportedWorkoutCandidate.hevy(
                workoutID: "hevy_1",
                workoutTitle: "Evening Session",
                startDate: Date(timeIntervalSince1970: 1_775_390_400),
                endDate: Date(timeIntervalSince1970: 1_775_392_200),
                duration: 1_800,
                metricValue: 80,
                metricType: .floors,
                matchingAppleHealthSample: nil
            )
        ]

        let result = ImportBatchResult(
            importedWorkouts: [makeWorkout()],
            updatedWorkouts: [],
            failedCandidateIDs: ["hevy_1"]
        )

        let record = WorkoutImportAnalyticsEvent
            .finished(mode: .all, candidates: candidates, result: result)
            .record

        #expect(record.name == "workout_import_finished")
        #expect(record.parameters["import_mode"] == .string("all"))
        #expect(record.parameters["candidate_count_bucket"] == .string("2_5"))
        #expect(record.parameters["imported_count_bucket"] == .string("one"))
        #expect(record.parameters["failed_count_bucket"] == .string("one"))
        #expect(record.parameters["outcome"] == .string("partial_success"))
        #expect(record.parameters["source_mix"] == .string("mixed"))
    }

    private func makeAppleHealthSample(id: String) -> HealthKitWorkoutSample {
        let startDate = Date(timeIntervalSince1970: 1_775_390_400)
        return HealthKitWorkoutSample(
            externalRecordID: id,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1_800),
            duration: 1_800,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            deviceModel: "Apple Watch"
        )
    }

    private func makeWorkout() -> Workout {
        Workout(
            name: "Imported Workout",
            date: Date(timeIntervalSince1970: 1_775_390_400),
            duration: 1_800,
            steps: 1_200,
            floors: 75,
            stepsPerFloor: 16,
            source: .appleHealth
        )
    }
}
