import Foundation
import SwiftData
@testable import AscendApp

/// One stored row for every model in the live schema.
///
/// It exists so a test can assert that a sweep emptied *the store* rather than that it emptied the
/// types whoever wrote the test happened to remember. Account deletion missed four models for
/// exactly that reason, and no test noticed, because every test container and every assertion was
/// another copy of the same hand-written list (#348).
///
/// Coverage is checked against `AscendLocalStore.models`, so adding a model to the schema without
/// adding it here fails `AccountDeletionServiceTests.hasAFixtureForEveryModelInTheLiveSchema`
/// before it can quietly become the next thing deletion leaves behind.
@MainActor
enum AscendLocalStoreFixture {

    /// Keyed by model type name so coverage can be compared against the schema directly.
    private static var inserters: [String: (ModelContext) -> Void] {
        Dictionary(uniqueKeysWithValues: [
            inserter(Workout.self) {
                Workout(name: "Fixture Workout", duration: 1_200, steps: 1_000, floors: 63)
            },
            inserter(WorkoutSourceLink.self) {
                WorkoutSourceLink(
                    provider: .appleHealth,
                    externalRecordID: "fixture-external-record",
                    providerWindowStart: fixtureDate,
                    providerWindowEnd: fixtureDate.addingTimeInterval(1_200),
                    timingPrecision: .exact
                )
            },
            inserter(WorkoutParticipation.self) {
                WorkoutParticipation(
                    workout: Workout(duration: 1_200, steps: 1_000, floors: 63),
                    userId: "fixture-user",
                    contextType: .climbAttempt,
                    contextId: "fixture-climb",
                    leaderboardEligible: false,
                    verificationTier: .unverified
                )
            },
            inserter(ActiveHeadphoneWorkoutDraft.self) {
                ActiveHeadphoneWorkoutDraft(
                    sessionID: "fixture-session",
                    kind: .justClimb,
                    title: "Fixture Session",
                    subtitle: "In progress",
                    workoutName: "Fixture Workout",
                    targetStepCount: nil,
                    targetDurationSeconds: nil
                )
            },
            inserter(LeaderboardStats.self) {
                LeaderboardStats(
                    userId: "fixture-user",
                    timeFrame: .weekly,
                    period: LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: fixtureDate)
                )
            },
            inserter(Routine.self) {
                Routine(name: "Fixture Routine")
            },
            inserter(RoutineFolder.self) {
                RoutineFolder(name: "Fixture Folder")
            },
            inserter(ClimbAttempt.self) {
                ClimbAttempt(climbId: "fixture-climb", status: .completed)
            },
            inserter(PendingMediaUpload.self) {
                PendingMediaUpload(
                    workoutId: UUID(),
                    localFileName: "fixture.jpg",
                    mediaType: "photo",
                    orderIndex: 0
                )
            },
            inserter(PendingWorkoutDeletion.self) {
                PendingWorkoutDeletion(workoutId: UUID(), ownerUserId: "fixture-user")
            },
            inserter(PendingRoutineDeletion.self) {
                PendingRoutineDeletion(
                    recordId: UUID(),
                    kind: .routine,
                    ownerUserId: "fixture-user"
                )
            },
            inserter(BestEffortCacheEntry.self) {
                BestEffortCacheEntry(
                    kind: .ranked,
                    effort: fixtureRankedBestEffort,
                    generatedAt: fixtureDate,
                    cacheVersion: 1
                )
            },
            inserter(BestEffortCacheMetadata.self) {
                BestEffortCacheMetadata(
                    id: "fixture-metadata",
                    cacheVersion: 1,
                    workoutSignature: "fixture-signature",
                    referenceYear: 2_026,
                    generatedAt: fixtureDate,
                    entryCount: 1
                )
            }
        ])
    }

    /// The model names this fixture can populate.
    static var coveredModelNames: Set<String> {
        Set(inserters.keys)
    }

    /// The model names the app actually persists.
    static var liveModelNames: Set<String> {
        Set(AscendLocalStore.models.map { String(describing: $0) })
    }

    /// A `ModelContainer` over the live schema, so a test cannot exercise a narrower store than
    /// the app ships.
    static func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Inserts and saves one row per model, then returns the row counts it produced.
    @discardableResult
    static func insertOneOfEach(into context: ModelContext) throws -> [String: Int] {
        for insert in inserters.values {
            insert(context)
        }
        try context.save()

        return try storedCountsByModelName(in: context)
    }

    static func storedCountsByModelName(in context: ModelContext) throws -> [String: Int] {
        var counts: [String: Int] = [:]

        for model in AscendLocalStore.models {
            counts[String(describing: model)] = try model.storedCount(in: context)
        }

        return counts
    }

    private static func inserter<Model: PersistentModel>(
        _ model: Model.Type,
        _ make: @escaping () -> Model
    ) -> (String, (ModelContext) -> Void) {
        (String(describing: model), { context in context.insert(make()) })
    }

    private static var fixtureDate: Date {
        Date(timeIntervalSince1970: 1_775_000_000)
    }

    private static var fixtureRankedBestEffort: RankedBestEffort {
        let workout = Workout(duration: 1_200, steps: 1_000, floors: 63)
        return RankedBestEffort(
            metric: .mostSteps,
            rank: 1,
            scope: .allTime,
            context: .all,
            performance: BestEffortPerformance(
                metric: .mostSteps,
                workout: workout,
                value: 1_000,
                steps: 1_000,
                duration: 1_200,
                segmentStartElapsedSeconds: nil,
                segmentEndElapsedSeconds: nil
            )
        )
    }
}
