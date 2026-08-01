import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// The behaviour contracts behind the ASCEND-IOS-1K fix.
///
/// `HomeEntryImportCostEvidenceTests` proves the bounded query is cheap; these prove it answers
/// the same questions the store-wide scan it replaced did. A faster query that quietly
/// re-imports a workout, or quietly drops review state, would be a worse bug than the hang.
@MainActor
@Suite(.serialized)
struct HomeEntryImportBoundedQueryTests {
    private static let sessionStart = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - Existence

    @Test
    func existingIDsReportsOnlyTheWorkoutsStillInTheStore() throws {
        let context = try Self.makeContext()
        let surviving = Self.makeWorkout(offsetDays: 0)
        let deleted = Self.makeWorkout(offsetDays: 1)
        context.insert(surviving)
        context.insert(deleted)
        try context.save()

        context.delete(deleted)
        try context.save()

        let existing = try WorkoutExistenceQuery.existingIDs(
            among: [surviving.id, deleted.id, UUID()],
            in: context
        )

        #expect(existing == [surviving.id])
    }

    @Test
    func existingIDsHandlesAnEmptyRequest() throws {
        let context = try Self.makeContext()
        #expect(try WorkoutExistenceQuery.existingIDs(among: [], in: context).isEmpty)
    }

    // MARK: - Apple Health links

    @Test
    func importedRecordIDsResolvesBothTheSourceLinkAndTheLegacyHealthKitUUID() throws {
        let context = try Self.makeContext()

        let linkedWorkout = Self.makeWorkout(offsetDays: 0)
        context.insert(linkedWorkout)
        context.insert(
            WorkoutSourceLink(
                provider: .appleHealth,
                externalRecordID: "linked",
                providerWindowStart: Self.sessionStart,
                providerWindowEnd: Self.sessionStart.addingTimeInterval(600),
                timingPrecision: .exact,
                workout: linkedWorkout
            )
        )

        let legacyWorkout = Self.makeWorkout(offsetDays: 1, healthKitUUID: "legacy")
        context.insert(legacyWorkout)
        try context.save()

        let imported = try AppleHealthLinkQuery.importedRecordIDs(
            among: ["linked", "legacy", "never-seen"],
            in: context
        )

        #expect(imported == ["linked", "legacy"])
    }

    /// A link belonging to another provider must not make an Apple Health record look imported.
    /// The scan this replaced switched on `sourceLink.provider`; the bounded query has to filter
    /// the same way, because the predicate cannot see the private raw value.
    @Test
    func importedRecordIDsIgnoresLinksFromOtherProviders() throws {
        let context = try Self.makeContext()
        let workout = Self.makeWorkout(offsetDays: 0)
        context.insert(workout)
        context.insert(
            WorkoutSourceLink(
                provider: .hevy,
                externalRecordID: "shared-id",
                providerWindowStart: Self.sessionStart,
                providerWindowEnd: Self.sessionStart.addingTimeInterval(600),
                timingPrecision: .exact,
                workout: workout
            )
        )
        try context.save()

        let imported = try AppleHealthLinkQuery.importedRecordIDs(
            among: ["shared-id"],
            in: context
        )

        #expect(imported.isEmpty)
    }

    @Test
    func workoutLookupFindsTheLinkedWorkoutAndNothingElse() throws {
        let context = try Self.makeContext()
        let workout = Self.makeWorkout(offsetDays: 0, healthKitUUID: "legacy")
        context.insert(workout)
        try context.save()

        let found = try AppleHealthLinkQuery.workout(forExternalRecordID: "legacy", in: context)
        let missing = try AppleHealthLinkQuery.workout(forExternalRecordID: "other", in: context)

        #expect(found?.id == workout.id)
        #expect(missing == nil)
    }

    // MARK: - Enrichment scope

    /// The enrichment scan used to filter every workout in the store by source. The predicate has
    /// to select exactly the same set - in-app sensor sessions - and nothing else.
    @Test
    func inAppSensorQuerySelectsOnlyHeadphoneMotionWorkouts() throws {
        let context = try Self.makeContext()
        let inApp = Self.makeWorkout(offsetDays: 0, source: .headphoneMotion)
        let imported = Self.makeWorkout(offsetDays: 1, source: .appleHealth)
        let manual = Self.makeWorkout(offsetDays: 2, source: .manual)
        for workout in [inApp, imported, manual] {
            context.insert(workout)
        }
        try context.save()

        let selected = try InAppSensorWorkoutQuery.allInAppSensorWorkouts(in: context)

        #expect(selected.map(\.id) == [inApp.id])
    }

    /// `source` moved to a stored raw value so it could appear in a predicate; the accessor has
    /// to keep round-tripping, including for a workout written before the accessor existed.
    @Test
    func sourceRoundTripsThroughItsStoredRawValue() throws {
        let context = try Self.makeContext()
        let workout = Self.makeWorkout(offsetDays: 0, source: .appleHealth)
        context.insert(workout)
        try context.save()

        #expect(workout.sourceRawValue == WorkoutSource.appleHealth.rawValue)

        workout.source = .headphoneMotion
        try context.save()

        #expect(workout.sourceRawValue == WorkoutSource.headphoneMotion.rawValue)
        #expect(workout.source == .headphoneMotion)
        #expect(try InAppSensorWorkoutQuery.allInAppSensorWorkouts(in: context).count == 1)
    }

    // MARK: - Percentiles

    /// The linear pass replaced a quadratic one during import. It is a cost change only: every
    /// score has to match what the per-workout call produced, ties included.
    @Test
    func theLinearPercentilePassMatchesThePerWorkoutCalculation() throws {
        let context = try Self.makeContext()
        var workouts: [Workout] = []

        for index in 0..<40 {
            // Two workouts share a timestamp, so the strictly-earlier tie rule is exercised.
            let day = index == 12 ? 11 : index
            let workout = Workout(
                name: "Session \(index)",
                date: Self.sessionStart.addingTimeInterval(TimeInterval(day) * 86_400),
                duration: TimeInterval(1_200 + index * 30),
                steps: 2_000 + index * 40,
                floors: 120 + index,
                avgHeartRate: 130 + (index % 17),
                maxHeartRate: 150 + (index % 11),
                caloriesBurned: 300 + index * 3,
                averageMETs: 8 + Double(index % 5) * 0.4,
                source: .appleHealth
            )
            context.insert(workout)
            workouts.append(workout)
        }
        try context.save()

        let ordered = try context.fetch(
            FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )
        let linear = PercentileScoreService.allPercentiles(forDateAscendingWorkouts: ordered)

        for (index, workout) in ordered.enumerated() {
            let reference = PercentileScoreService.calculateAllPercentiles(
                for: workout,
                existingWorkouts: ordered
            )
            #expect(
                linear[index] == reference,
                "percentiles diverged for workout at index \(index)"
            )
        }
    }

    // MARK: - Fixture

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            PendingMediaUpload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func makeWorkout(
        offsetDays: Int,
        source: WorkoutSource = .appleHealth,
        healthKitUUID: String? = nil
    ) -> Workout {
        Workout(
            name: "Session",
            date: sessionStart.addingTimeInterval(TimeInterval(offsetDays) * 86_400),
            duration: 1_800,
            steps: 2_400,
            floors: 150,
            source: source,
            healthKitUUID: healthKitUUID
        )
    }
}
