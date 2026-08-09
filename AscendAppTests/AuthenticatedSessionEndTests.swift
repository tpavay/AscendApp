import Foundation
import HealthKit
import SwiftData
import Testing

@testable import AscendApp

/// Signing out has to stop the workers that schedule themselves, not only the bootstrap chain.
///
/// Enrichment is the motivating case: its timer sleeps for hours between passes while holding the
/// store and the climbs it was watching, so one armed under the previous climber wakes up after the
/// account has changed and writes a row that `WorkoutMutationHandler` attributes to whoever is
/// signed in when it lands.
///
/// What no unit test can reach is the call site - `AuthenticationViewModel`'s Firebase auth-state
/// handler, the one place that sees every way a session ends. What it depends on completely is
/// asserted here: that ending a session stops every worker handed to it, and that stopping
/// enrichment leaves no wake-up and performs no further read.
@MainActor
struct AuthenticatedSessionEndTests {
    @Test("Ending a session leaves enrichment with no wake-up and no further read")
    func endingASessionStopsEnrichment() async throws {
        let clock = SessionEndClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try AscendLocalStoreFixture.makeModelContext()

        let workout = Workout(
            name: "Live Climb",
            date: clock.now.addingTimeInterval(-1_200),
            duration: 1_200,
            steps: 1_600,
            floors: Workout.stepsToFloors(1_600, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = SessionEndMetricsReader()
        let coordinator = AuthenticatedBootstrapCoordinator()
        let service = AppleHealthEnrichmentService(
            authorizationController: SessionEndAuthorization(),
            metricsReader: metricsReader,
            attemptStore: AppleHealthEnrichmentAttemptStore(
                defaults: UserDefaults(suiteName: "session-end-\(UUID().uuidString)")!
            ),
            sessionWorkGate: coordinator,
            now: { clock.now }
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        // The series is genuinely running: one read spent, and the next attempt armed.
        #expect(metricsReader.requestedWindows.count == 1)
        #expect(service.hasScheduledWakeUp)

        coordinator.endAuthenticatedSession(autonomousWorkers: [service])
        await service.drainInFlightWork()

        #expect(service.hasScheduledWakeUp == false)

        // Well past the next backoff step, and nothing wakes up to read the previous account's
        // climb.
        clock.advance(by: 6 * 60 * 60)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.count == 1)
        #expect(workout.avgHeartRate == nil)
    }

    @Test("Every autonomous worker is stopped, not one named case")
    func stopsEveryAutonomousWorker() {
        let enrichment = SpySessionWorker()
        let uploads = SpySessionWorker()
        let coordinator = AuthenticatedBootstrapCoordinator()

        coordinator.endAuthenticatedSession(autonomousWorkers: [enrichment, uploads])

        #expect(enrichment.cancelCount == 1)
        #expect(uploads.cancelCount == 1)
    }

    /// The previous account's bootstrap is dropped rather than parked: resuming it once someone
    /// else has signed in would run it against the wrong session.
    @Test("The signed-out account's bootstrap is not resumable")
    func dropsTheSignedOutAccountsBootstrap() async {
        let coordinator = AuthenticatedBootstrapCoordinator()
        let runs = AsyncStream<Void>.makeStream()
        var runCount = 0

        coordinator.schedule {
            runCount += 1
            runs.continuation.yield()
        }

        var runIterator = runs.stream.makeAsyncIterator()
        _ = await runIterator.next()

        coordinator.endAuthenticatedSession(autonomousWorkers: [])

        await coordinator.suspendAndDrain(timeout: unraceableDrainBound)
        coordinator.resumeLatest()
        await coordinator.suspendAndDrain(timeout: unraceableDrainBound)

        #expect(runCount == 1)
    }
}

/// Far past any scheduling delay, so a starved main-actor hop in a parallel run cannot turn this
/// into an assertion about who won a race.
private let unraceableDrainBound: Duration = .seconds(3_600)

private final class SessionEndClock: @unchecked Sendable {
    private(set) var now: Date

    init(start: Date) {
        now = start
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
private final class SpySessionWorker: AuthenticatedSessionWorker {
    private(set) var cancelCount = 0

    func cancelInFlightWork() {
        cancelCount += 1
    }

    func drainInFlightWork() async {}
}

@MainActor
private final class SessionEndMetricsReader: HealthKitMetricsReading {
    private(set) var requestedWindows: [ClosedRange<Date>] = []

    func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        requestedWindows.append(dateRange)
        return WorkoutMetrics()
    }
}

@MainActor
private final class SessionEndAuthorization: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = true
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState = .connected

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool { true }
}
