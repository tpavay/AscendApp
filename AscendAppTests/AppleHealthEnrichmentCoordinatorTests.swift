import Foundation
import HealthKit
import SwiftData
import Testing

@testable import AscendApp

/// Enrichment is the only thing Apple Health does for a climber now that Ascend does not import
/// workouts, so these cover the whole contract: read over the climb's own window, never anyone
/// else's workout record, and never overwrite a chest strap's series.
@MainActor
@Suite(.serialized)
struct AppleHealthEnrichmentCoordinatorTests {
    @Test
    func enrichesAClimbAscendRecordedFromItsOwnTimeWindow() async throws {
        try await HealthKitCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let snapshot = HealthKitSyncStateSnapshot.capture()
            defer { snapshot.restore() }
            HealthKitSyncState.hasRequestedAuthorization = true

            let start = Date().addingTimeInterval(-30 * 60)
            let climb = Self.makeClimb(start: start, duration: 1_200, steps: 1_600)
            modelContext.insert(climb)
            try modelContext.save()

            let metricsReader = StubMetricsReader(responses: [
                WorkoutMetrics(
                    avgHeartRate: 148,
                    maxHeartRate: 174,
                    caloriesBurned: 210,
                    heartRateTimeSeries: [
                        HeartRateDataPoint(timestamp: start.addingTimeInterval(300), heartRate: 146)
                    ]
                )
            ])
            let coordinator = Self.makeCoordinator(metricsReader: metricsReader)
            coordinator.configure(modelContext: modelContext)

            await coordinator.refreshPendingEnrichment()

            #expect(climb.avgHeartRate == 148)
            #expect(climb.maxHeartRate == 174)
            #expect(climb.caloriesBurned == 210)
            #expect(climb.heartRateTimeSeries.count == 1)
            #expect(metricsReader.requestedRanges.count == 1)
            #expect(metricsReader.requestedRanges.first?.lowerBound == start)
            #expect(metricsReader.requestedRanges.first?.upperBound == start.addingTimeInterval(1_200))
        }
    }

    @Test("A climb stays eligible until Health has actually written its samples")
    func retriesWhenTheFirstReadFindsNothing() async throws {
        try await HealthKitCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let snapshot = HealthKitSyncStateSnapshot.capture()
            defer { snapshot.restore() }
            HealthKitSyncState.hasRequestedAuthorization = true

            let start = Date().addingTimeInterval(-60 * 60)
            let climb = Self.makeClimb(start: start, duration: 900, steps: 1_100)
            modelContext.insert(climb)
            try modelContext.save()

            let metricsReader = StubMetricsReader(responses: [
                WorkoutMetrics(),
                WorkoutMetrics(
                    avgHeartRate: 151,
                    maxHeartRate: 168,
                    caloriesBurned: 180,
                    heartRateTimeSeries: [
                        HeartRateDataPoint(timestamp: start.addingTimeInterval(120), heartRate: 149)
                    ]
                )
            ])
            let coordinator = Self.makeCoordinator(metricsReader: metricsReader)
            coordinator.configure(modelContext: modelContext)

            await coordinator.refreshPendingEnrichment()

            #expect(climb.avgHeartRate == nil)
            #expect(coordinator.appleHealthEnrichmentStatus(for: climb) == .metricsPending)

            // The pass throttles a second attempt within the minute, so this is the forced route
            // the detail screen's retry button takes.
            _ = await coordinator.enrichInAppWorkoutWithAppleHealthIfPossible(
                climb,
                modelContext: modelContext,
                force: true
            )

            #expect(climb.avgHeartRate == 151)
            #expect(climb.caloriesBurned == 180)
            #expect(coordinator.appleHealthEnrichmentStatus(for: climb) == .complete)
            #expect(metricsReader.requestedRanges.count == 2)
        }
    }

    @Test("A live-captured chest-strap series outranks Apple Health's wrist data")
    func keepsALiveCapturedHeartRateSeries() async throws {
        try await HealthKitCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let snapshot = HealthKitSyncStateSnapshot.capture()
            defer { snapshot.restore() }
            HealthKitSyncState.hasRequestedAuthorization = true

            let start = Date().addingTimeInterval(-20 * 60)
            let climb = Self.makeClimb(start: start, duration: 600, steps: 900)
            climb.avgHeartRate = 160
            climb.maxHeartRate = 181
            climb.heartRateData = [
                HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 158)
            ].encoded
            modelContext.insert(climb)
            try modelContext.save()

            let metricsReader = StubMetricsReader(responses: [
                WorkoutMetrics(
                    avgHeartRate: 120,
                    maxHeartRate: 130,
                    caloriesBurned: 140,
                    heartRateTimeSeries: [
                        HeartRateDataPoint(timestamp: start.addingTimeInterval(30), heartRate: 118)
                    ]
                )
            ])
            let coordinator = Self.makeCoordinator(metricsReader: metricsReader)
            coordinator.configure(modelContext: modelContext)

            await coordinator.refreshPendingEnrichment()

            #expect(climb.avgHeartRate == 160)
            #expect(climb.maxHeartRate == 181)
            #expect(climb.heartRateTimeSeries.map(\.heartRate) == [158])
            #expect(climb.caloriesBurned == 140)
        }
    }

    @Test("A workout Ascend did not record is never enriched")
    func leavesNonSensorWorkoutsAlone() async throws {
        try await HealthKitCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let snapshot = HealthKitSyncStateSnapshot.capture()
            defer { snapshot.restore() }
            HealthKitSyncState.hasRequestedAuthorization = true

            let start = Date().addingTimeInterval(-15 * 60)
            let legacy = Workout(
                name: "Legacy",
                date: start,
                duration: 600,
                steps: 700,
                floors: Workout.stepsToFloors(700, stepsPerFloor: 16),
                stepsPerFloor: 16,
                source: .appleHealth
            )
            modelContext.insert(legacy)
            try modelContext.save()

            let metricsReader = StubMetricsReader(responses: [
                WorkoutMetrics(avgHeartRate: 140, maxHeartRate: 160, caloriesBurned: 100)
            ])
            let coordinator = Self.makeCoordinator(metricsReader: metricsReader)
            coordinator.configure(modelContext: modelContext)

            await coordinator.refreshPendingEnrichment()

            #expect(legacy.avgHeartRate == nil)
            #expect(metricsReader.requestedRanges.isEmpty)
            #expect(coordinator.appleHealthEnrichmentStatus(for: legacy) == .notPending)
        }
    }

    @Test("Past the retry window the surface says so instead of pretending to still be checking")
    func reportsStalledOnceTheRetryWindowHasPassed() async throws {
        try await HealthKitCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let snapshot = HealthKitSyncStateSnapshot.capture()
            defer { snapshot.restore() }
            HealthKitSyncState.hasRequestedAuthorization = true

            let start = Date().addingTimeInterval(-96 * 60 * 60)
            let climb = Self.makeClimb(start: start, duration: 900, steps: 1_000)
            modelContext.insert(climb)
            try modelContext.save()

            let metricsReader = StubMetricsReader(responses: [])
            let coordinator = Self.makeCoordinator(metricsReader: metricsReader)
            coordinator.configure(modelContext: modelContext)

            await coordinator.refreshPendingEnrichment()

            #expect(metricsReader.requestedRanges.isEmpty)
            #expect(coordinator.appleHealthEnrichmentStatus(for: climb) == .metricsStalled)
            #expect(coordinator.appleHealthHeartRateEnrichmentStatus(for: climb) == .metricsStalled)
        }
    }

    @Test("A climber who never connected Apple Health is not swept")
    func doesNothingWithoutAnAppleHealthConnection() async throws {
        try await HealthKitCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let snapshot = HealthKitSyncStateSnapshot.capture()
            defer { snapshot.restore() }
            HealthKitSyncState.hasRequestedAuthorization = false

            let start = Date().addingTimeInterval(-25 * 60)
            let climb = Self.makeClimb(start: start, duration: 900, steps: 1_200)
            modelContext.insert(climb)
            try modelContext.save()

            let metricsReader = StubMetricsReader(responses: [
                WorkoutMetrics(avgHeartRate: 140, maxHeartRate: 160, caloriesBurned: 100)
            ])
            let coordinator = Self.makeCoordinator(metricsReader: metricsReader)
            coordinator.configure(modelContext: modelContext)

            await coordinator.refreshPendingEnrichment()

            #expect(metricsReader.requestedRanges.isEmpty)
            #expect(climb.avgHeartRate == nil)
            #expect(coordinator.lastErrorMessage == nil)
        }
    }

    @Test("An automatic sweep re-entering seconds later is refused, an explicit one is not")
    func throttlesAutomaticSweepsButNotUserInitiatedOnes() async throws {
        try await HealthKitCoordinatorTestIsolation.shared.run {
            let modelContext = try Self.makeModelContext()
            let snapshot = HealthKitSyncStateSnapshot.capture()
            defer { snapshot.restore() }
            HealthKitSyncState.hasRequestedAuthorization = true

            let firstStart = Date().addingTimeInterval(-40 * 60)
            let firstClimb = Self.makeClimb(start: firstStart, duration: 900, steps: 1_100)
            modelContext.insert(firstClimb)
            try modelContext.save()

            let metricsReader = StubMetricsReader(responses: [])
            let coordinator = Self.makeCoordinator(metricsReader: metricsReader)
            coordinator.configure(modelContext: modelContext)

            await coordinator.refreshPendingEnrichment(trigger: .automatic)
            #expect(metricsReader.requestedRanges.count == 1)

            // A brand-new climb proves the second pass was refused before the fetch, rather than
            // the per-climb retry store refusing a repeat read of the first one.
            let secondStart = Date().addingTimeInterval(-20 * 60)
            let secondClimb = Self.makeClimb(start: secondStart, duration: 600, steps: 800)
            modelContext.insert(secondClimb)
            try modelContext.save()

            await coordinator.refreshPendingEnrichment(trigger: .automatic)
            #expect(metricsReader.requestedRanges.count == 1)

            await coordinator.refreshPendingEnrichment()
            #expect(metricsReader.requestedRanges.count == 2)
            #expect(metricsReader.requestedRanges.last?.lowerBound == secondStart)
        }
    }

    // MARK: - Helpers

    private static func makeCoordinator(
        metricsReader: StubMetricsReader
    ) -> AppleHealthEnrichmentCoordinator {
        AppleHealthEnrichmentCoordinator(
            authorizationController: StubAuthorizationController(),
            metricsReader: metricsReader,
            enrichmentRetryStore: AppleHealthEnrichmentRetryStore(
                defaults: UserDefaults(suiteName: "AppleHealthEnrichmentCoordinatorTests")!,
                key: "test.enrichmentRetry.\(UUID().uuidString)"
            )
        )
    }

    private static func makeModelContext() throws -> ModelContext {
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

    private static func makeClimb(start: Date, duration: TimeInterval, steps: Int) -> Workout {
        Workout(
            name: "Live Climb",
            date: start,
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
    }
}

@MainActor
final class StubMetricsReader: HealthKitMetricsReading {
    private var responses: [WorkoutMetrics]
    private(set) var requestedRanges: [ClosedRange<Date>] = []

    init(responses: [WorkoutMetrics]) {
        self.responses = responses
    }

    func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        requestedRanges.append(dateRange)
        guard !responses.isEmpty else { return WorkoutMetrics() }
        return responses.removeFirst()
    }
}

@MainActor
final class StubAuthorizationController: HealthKitAuthorizationControlling {
    var isHealthDataAvailable = true
    var lastPermissionErrorMessage: String?
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary

    var hasRequestedAuthorization: Bool {
        HealthKitSyncState.hasRequestedAuthorization
    }

    var connectionState: AppleHealthConnectionState {
        guard isHealthDataAvailable else { return .unavailable }
        guard hasRequestedAuthorization else { return .neverConnected }
        return .connected
    }

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool {
        HealthKitSyncState.hasRequestedAuthorization = true
        return true
    }
}

struct HealthKitSyncStateSnapshot {
    private let hasRequestedAuthorization: Bool

    static func capture() -> HealthKitSyncStateSnapshot {
        HealthKitSyncStateSnapshot(
            hasRequestedAuthorization: HealthKitSyncState.hasRequestedAuthorization
        )
    }

    func restore() {
        HealthKitSyncState.hasRequestedAuthorization = hasRequestedAuthorization
    }
}
