import HealthKit
import SwiftData
import Testing

@testable import AscendApp

/// A HealthKit observer imports on its own schedule, so account deletion cannot stop it by draining
/// the bootstrap chain alone.
///
/// An import pass that starts after the drain and lands inside deletion's staged window does two
/// things at once: it saves the context, committing a sweep that was deliberately left unsaved so
/// it could roll back, and it inserts a workout owned by the account being deleted. That leftover
/// row is exactly what the ownership guard blocks the replacement account on (#389).
@MainActor
@Suite(.serialized)
struct AccountDeletionSessionWorkGateTests {
    @Test("Suspended session work blocks a background-observer import pass", .bug(id: 389))
    func suspendedSessionWorkBlocksObserverImport() async throws {
        try await HealthKitImportCoordinatorTestIsolation.shared.run {
            let fixture = try Self.makeFixture()
            defer { fixture.teardown() }

            await fixture.gate.suspendAndDrain(autonomousWorkers: [fixture.coordinator])

            await fixture.coordinator.refreshPendingImports(trigger: .backgroundObserver)

            #expect(fixture.authorization.refreshCount == 0)
            #expect(try fixture.modelContext.fetch(FetchDescriptor<Workout>()).isEmpty)
        }
    }

    @Test("The gate reopens once deletion resolves", .bug(id: 389))
    func importResumesAfterDeletionResolves() async throws {
        try await HealthKitImportCoordinatorTestIsolation.shared.run {
            let fixture = try Self.makeFixture()
            defer { fixture.teardown() }

            await fixture.gate.suspendAndDrain(autonomousWorkers: [fixture.coordinator])
            fixture.gate.discard()

            await fixture.coordinator.refreshPendingImports(trigger: .backgroundObserver)

            #expect(fixture.authorization.refreshCount == 1)
        }
    }

    // MARK: - Fixture

    private static func makeFixture() throws -> Fixture {
        let suiteName = "AccountDeletionSessionWorkGateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

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
        let modelContext = ModelContext(container)

        let gate = AuthenticatedBootstrapCoordinator()
        let authorization = RecordingAuthorizationController()
        let coordinator = WorkoutImportCoordinator(
            authorizationController: authorization,
            workoutReader: EmptyStubWorkoutReader(),
            metricsReader: EmptyStubMetricsReader(),
            reviewStateStore: WorkoutAutoImportReviewStateStore(
                defaults: defaults,
                key: "auto-review"
            ),
            ignoredAppleHealthWorkoutStore: IgnoredAppleHealthWorkoutStore(
                defaults: defaults,
                key: "ignored-apple-health"
            ),
            sessionWorkGate: gate
        )
        coordinator.configure(modelContext: modelContext)

        return Fixture(
            container: container,
            modelContext: modelContext,
            gate: gate,
            authorization: authorization,
            coordinator: coordinator,
            teardown: {
                coordinator.cancelInFlightWork()
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let modelContext: ModelContext
        let gate: AuthenticatedBootstrapCoordinator
        let authorization: RecordingAuthorizationController
        let coordinator: WorkoutImportCoordinator
        let teardown: @MainActor () -> Void
    }
}

/// Records whether the import pass got past its gate: refreshing authorization status is the first
/// thing a real pass does once it has a store to write to.
@MainActor
private final class RecordingAuthorizationController: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = true
    let hasCompletedInitialBackfill = true
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState = .connected

    private(set) var refreshCount = 0

    func refreshAuthorizationRequestStatus() async {
        refreshCount += 1
    }

    func requestAuthorization() async -> Bool { true }
}

@MainActor
private final class EmptyStubWorkoutReader: HealthKitWorkoutReading {
    let isHealthDataAvailable = true

    func fetchAnchoredStairStepperWorkouts(anchorData: Data?) async throws
        -> HealthKitWorkoutDiscoveryResult
    {
        HealthKitWorkoutDiscoveryResult(
            addedSamples: [],
            deletedExternalRecordIDs: [],
            anchorData: anchorData
        )
    }

    func fetchWorkout(withExternalRecordID externalRecordID: String) async throws -> HKWorkout? {
        nil
    }

    func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws
        -> [HealthKitWorkoutSample]
    {
        []
    }
}

@MainActor
private final class EmptyStubMetricsReader: HealthKitMetricsReading {
    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
        WorkoutMetrics(steps: 0)
    }
}
