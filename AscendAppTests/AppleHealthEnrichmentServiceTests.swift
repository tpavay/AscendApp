import Foundation
import HealthKit
import SwiftData
import Testing

@testable import AscendApp

/// Behavioural coverage for #438: a climb Ascend recorded gets its heart rate attached even
/// when Apple Health publishes it after Ascend first looked.
///
/// The timing case is the one that made enrichment silently inert in the field, so it is
/// asserted as a sequence rather than as a single call: Ascend looks, finds nothing, looks
/// again when the schedule says to, and finds it.
@MainActor
struct AppleHealthEnrichmentServiceTests {
    // MARK: - The timing defect

    @Test("Heart rate lands on a later look when Health publishes after the first one")
    func enrichesOnASecondLookWhenHealthPublishesLate() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()
        let store = makeAttemptStore()

        let climbStart = clock.now.addingTimeInterval(-1_200)
        let workout = makeLiveClimb(start: climbStart, duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        // Health has nothing when the climb is saved - the wearable has not synced yet.
        let metricsReader = ScriptedMetricsReader(responses: [WorkoutMetrics()])
        let service = makeService(metricsReader: metricsReader, attemptStore: store, clock: clock)

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.count == 1)
        #expect(workout.avgHeartRate == nil)
        #expect(workout.heartRateTimeSeries.isEmpty)
        #expect(service.phase(for: workout) == .waiting(nextCheckAt: clock.now.addingTimeInterval(15)))

        // The wearable syncs. Nothing about the climb changed - only what Health now holds.
        metricsReader.enqueue(
            WorkoutMetrics(
                avgHeartRate: 149,
                maxHeartRate: 178,
                caloriesBurned: 214,
                heartRateTimeSeries: [
                    HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(300), heartRate: 145),
                    HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(900), heartRate: 168)
                ]
            )
        )

        // The first backoff step elapses and the schedule comes due.
        clock.advance(by: 20)
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.count == 2)
        #expect(workout.avgHeartRate == 149)
        #expect(workout.maxHeartRate == 178)
        #expect(workout.caloriesBurned == 214)
        #expect(workout.heartRateTimeSeries.count == 2)
        #expect(service.phase(for: workout) == .notApplicable)
        #expect(service.lastEnrichedWorkoutID == workout.id)
    }

    @Test("A look before its backoff step has elapsed does not spend an attempt")
    func doesNotLookAgainBeforeTheScheduleIsDue() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(responses: [WorkoutMetrics()])
        let service = makeService(
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            clock: clock
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()
        #expect(metricsReader.requestedWindows.count == 1)

        // Three surfaces asking at once is the real shape of this: the summary, the workout
        // detail and a foreground can all land in the same instant.
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.count == 1)
    }

    // MARK: - The window it reads

    @Test("The read covers the climb's own window, not an Apple Health workout's")
    func readsTheClimbsOwnTimeWindow() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let climbStart = clock.now.addingTimeInterval(-900)
        let workout = makeLiveClimb(start: climbStart, duration: 900)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(responses: [WorkoutMetrics()])
        let service = makeService(
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            clock: clock
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        let window = try #require(metricsReader.requestedWindows.first)
        #expect(window.lowerBound == climbStart)
        #expect(window.upperBound == climbStart.addingTimeInterval(900))
    }

    /// A Garmin writing four samples across a climb has answered. Ascend takes the four.
    @Test("A sparse series is a real answer and ends the series")
    func acceptsASparseHeartRateSeries() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let climbStart = clock.now.addingTimeInterval(-1_200)
        let workout = makeLiveClimb(start: climbStart, duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(
            responses: [
                WorkoutMetrics(
                    avgHeartRate: 138,
                    maxHeartRate: 151,
                    caloriesBurned: 180,
                    heartRateTimeSeries: [
                        HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(120), heartRate: 131),
                        HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(1_020), heartRate: 151)
                    ]
                )
            ]
        )
        let service = makeService(
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            clock: clock
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(workout.heartRateTimeSeries.count == 2)
        #expect(service.phase(for: workout) == .notApplicable)

        // Nothing keeps looking for a climb that has been answered.
        clock.advance(by: 3_600)
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()
        #expect(metricsReader.requestedWindows.count == 1)
    }

    /// A wearable that published only a summary has answered too - re-reading it forever
    /// would be Ascend refusing an answer it already has.
    @Test("A summary with no samples still ends the series")
    func acceptsASummaryWithNoSamples() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(
            responses: [
                WorkoutMetrics(avgHeartRate: 142, maxHeartRate: 166, caloriesBurned: 190)
            ]
        )
        let service = makeService(
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            clock: clock
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(workout.avgHeartRate == 142)
        #expect(workout.heartRateTimeSeries.isEmpty)
        #expect(service.phase(for: workout) == .notApplicable)
    }

    // MARK: - Bounds

    @Test("The retry series stops instead of polling forever")
    func stopsAfterTheAttemptBudget() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()
        // A curve of its own, so this asserts the injected schedule bounds the series rather
        // than a constant the ledger happens to share with it.
        let schedule = AppleHealthEnrichmentSchedule(backoff: [10, 30, 90])

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(responses: [])
        let service = makeService(
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(schedule: schedule),
            clock: clock
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        for delay in schedule.backoff {
            clock.advance(by: delay + 1)
            service.resumeTracking(modelContext: modelContext)
            await service.drainInFlightWork()
        }

        #expect(metricsReader.requestedWindows.count == schedule.attemptBudget)
        #expect(service.phase(for: workout) == .stoppedLooking)

        // Well past the last backoff step, and it stays stopped.
        clock.advance(by: 12 * 60 * 60)
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()
        #expect(metricsReader.requestedWindows.count == schedule.attemptBudget)
    }

    @Test("A climb outside the retry window is never picked up automatically")
    func doesNotTrackClimbsOutsideTheWindow() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let stale = makeLiveClimb(
            start: clock.now.addingTimeInterval(-(80 * 60 * 60)),
            duration: 1_200
        )
        modelContext.insert(stale)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(responses: [])
        let service = makeService(
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            clock: clock
        )

        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.isEmpty)
        // Still honest about it, and still fetchable by hand - and a hand fetch that reads and
        // comes back empty says so, distinctly from one that never got to read.
        #expect(service.phase(for: stale) == .stoppedLooking)
        #expect(await service.fetchNow(stale, modelContext: modelContext) == .foundNothing)
        #expect(metricsReader.requestedWindows.count == 1)
    }

    /// A pass that cannot read leaves every tracked climb still due, so re-arming off the back
    /// of one would schedule the next wake-up a second out and keep doing it.
    @Test("A climb that cannot be read leaves no wake-up scheduled")
    func schedulesNoWakeUpWhenAPassCouldNotRun() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(responses: [])
        let service = AppleHealthEnrichmentService(
            authorizationController: StubAuthorizationController(connectionState: .neverConnected),
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            now: { clock.now }
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.isEmpty)
        #expect(service.hasScheduledWakeUp == false)

        // Same for a connected climber whose only climb has aged out of the window. Its own
        // store, so the assertion is about that climb and nothing else.
        let staleContext = try makeModelContext()
        let stale = makeLiveClimb(
            start: clock.now.addingTimeInterval(-(80 * 60 * 60)),
            duration: 1_200
        )
        staleContext.insert(stale)
        try staleContext.save()

        let connected = makeService(
            metricsReader: ScriptedMetricsReader(responses: []),
            attemptStore: makeAttemptStore(),
            clock: clock
        )
        connected.resumeTracking(modelContext: staleContext)
        await connected.drainInFlightWork()
        #expect(connected.hasScheduledWakeUp == false)
    }

    /// The third door into the same spin: account deletion suspends the session gate, and its
    /// re-authentication step sends the climber out to a sign-in flow whose return fires a
    /// foreground `resumeTracking`. A suspended pass reads nothing, so every tracked climb is
    /// still due, and a wake-up armed off that pass would fire one second later - forever.
    @Test("A suspended account session leaves no wake-up scheduled")
    func schedulesNoWakeUpWhileTheSessionGateIsSuspended() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let sessionWorkGate = AuthenticatedBootstrapCoordinator()
        await sessionWorkGate.suspendAndDrain()

        let metricsReader = ScriptedMetricsReader(
            responses: [WorkoutMetrics(avgHeartRate: 150, maxHeartRate: 172, caloriesBurned: 200)]
        )
        let service = makeService(
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            clock: clock,
            sessionWorkGate: sessionWorkGate
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.isEmpty)
        #expect(service.hasScheduledWakeUp == false)

        // A foreground while still suspended arms nothing either - that is the reachable path.
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.isEmpty)
        #expect(service.hasScheduledWakeUp == false)

        // Deletion stopped short of the auth account, so the series picks up where it was.
        sessionWorkGate.resumeLatest()
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(workout.avgHeartRate == 150)
    }

    /// The kill switch has to defer, not drop: a climb it blocks resumes its own series from
    /// where it left off once the flag comes back.
    @Test("The kill switch stops the pass without spending an attempt")
    func killSwitchDefersWithoutSpendingAnAttempt() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()
        let attemptStore = makeAttemptStore()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let flags = RemoteFeatureFlagStore(
            snapshot: .resolving(
                remoteValues: [RemoteFeatureFlag.appleHealthEnrichment.key: false]
            )
        )

        let metricsReader = ScriptedMetricsReader(
            responses: [WorkoutMetrics(avgHeartRate: 150, maxHeartRate: 172, caloriesBurned: 200)]
        )
        let service = AppleHealthEnrichmentService(
            authorizationController: StubAuthorizationController(connectionState: .connected),
            metricsReader: metricsReader,
            attemptStore: attemptStore,
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            featureFlags: flags,
            now: { clock.now }
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.isEmpty)
        #expect(workout.avgHeartRate == nil)
        #expect(service.hasScheduledWakeUp == false)
        // The ledger is untouched, so the series has lost nothing.
        #expect(attemptStore.attempt(for: workout.id) == nil)

        // A hand-requested fetch says it never looked, so no surface can report a switched-off
        // read as "your wearable published nothing".
        #expect(await service.fetchNow(workout, modelContext: modelContext) == .couldNotLook)

        // And it says so rather than claiming a check is coming that was never scheduled.
        #expect(service.phase(for: workout) == .checksPaused)

        _ = flags.apply(.shippedDefaults)
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(workout.avgHeartRate == 150)
    }

    /// A switched-off incident is exactly when a wrong status costs trust: `.waiting` would
    /// promise a check that `armTimer` deliberately never scheduled, and the connect offer would
    /// spend a permission prompt on a benefit the app has been told not to deliver.
    @Test("A switched-off kill switch is stated, not dressed up as waiting")
    func reportsPausedChecksRatherThanWaiting() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)

        let flags = RemoteFeatureFlagStore(
            snapshot: .resolving(
                remoteValues: [RemoteFeatureFlag.appleHealthEnrichment.key: false]
            )
        )

        let connected = AppleHealthEnrichmentService(
            authorizationController: StubAuthorizationController(connectionState: .connected),
            metricsReader: ScriptedMetricsReader(responses: []),
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            featureFlags: flags,
            now: { clock.now }
        )

        #expect(connected.phase(for: workout) == .checksPaused)

        let neverConnected = AppleHealthEnrichmentService(
            authorizationController: StubAuthorizationController(connectionState: .neverConnected),
            metricsReader: ScriptedMetricsReader(responses: []),
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            featureFlags: flags,
            now: { clock.now }
        )

        #expect(neverConnected.offersConnectionPrompt(for: workout) == false)
        #expect(neverConnected.phase(for: workout) == .checksPaused)

        // A device that cannot reach Health at all is still told the truer thing.
        let unavailable = AppleHealthEnrichmentService(
            authorizationController: StubAuthorizationController(connectionState: .unavailable),
            metricsReader: ScriptedMetricsReader(responses: []),
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            featureFlags: flags,
            now: { clock.now }
        )

        #expect(unavailable.phase(for: workout) == .unavailable)

        // The offer returns with the flag, so nothing is permanently withheld.
        _ = flags.apply(.shippedDefaults)
        #expect(neverConnected.offersConnectionPrompt(for: workout))
        #expect(neverConnected.phase(for: workout) == .connectionOffered)
    }

    @Test("Cancelling stops the series and forgets what it was watching")
    func cancellationStopsTheSeries() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(responses: [])
        let service = makeService(
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            clock: clock
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()
        #expect(metricsReader.requestedWindows.count == 1)

        service.cancelInFlightWork()
        await service.drainInFlightWork()

        clock.advance(by: 3_600)
        await service.drainInFlightWork()
        #expect(metricsReader.requestedWindows.count == 1)
    }

    // MARK: - The connection offer

    @Test("A climber who never connected is offered the connection, not skipped")
    func offersConnectionAfterAClimbWithNoHeartRate() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let authorization = StubAuthorizationController(connectionState: .neverConnected)
        let metricsReader = ScriptedMetricsReader(
            responses: [
                WorkoutMetrics(avgHeartRate: 151, maxHeartRate: 179, caloriesBurned: 220)
            ]
        )
        let service = AppleHealthEnrichmentService(
            authorizationController: authorization,
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            now: { clock.now }
        )

        #expect(service.offersConnectionPrompt(for: workout))
        #expect(service.phase(for: workout) == .connectionOffered)

        // No read happens while disconnected - there is nothing to read from.
        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()
        #expect(metricsReader.requestedWindows.isEmpty)

        // The climber taps Connect. Granting reads immediately rather than waiting for a timer.
        authorization.connectionState = .connected
        let result = await service.connectAndFetch(workout, modelContext: modelContext)

        #expect(result == .added)
        #expect(workout.avgHeartRate == 151)
        #expect(service.offersConnectionPrompt(for: workout) == false)
    }

    @Test("A climb that already has heart rate is never offered the connection")
    func doesNotOfferConnectionForAClimbThatHasHeartRate() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        workout.avgHeartRate = 144
        workout.maxHeartRate = 170

        let service = AppleHealthEnrichmentService(
            authorizationController: StubAuthorizationController(connectionState: .neverConnected),
            metricsReader: ScriptedMetricsReader(responses: []),
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            now: { clock.now }
        )

        #expect(service.offersConnectionPrompt(for: workout) == false)
        #expect(service.phase(for: workout) == .notApplicable)
    }

    /// A chest strap paired to Ascend during the session is first-party and denser than
    /// anything a wrist writes afterwards, so Health never overwrites it.
    @Test("A live-captured series is never overwritten by Apple Health")
    func preservesLiveCapturedHeartRate() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let climbStart = clock.now.addingTimeInterval(-1_200)
        let workout = makeLiveClimb(start: climbStart, duration: 1_200)
        workout.avgHeartRate = 155
        workout.maxHeartRate = 181
        workout.heartRateData = [
            HeartRateDataPoint(timestamp: climbStart.addingTimeInterval(60), heartRate: 150)
        ].encoded
        modelContext.insert(workout)
        try modelContext.save()

        let service = makeService(
            metricsReader: ScriptedMetricsReader(
                responses: [
                    WorkoutMetrics(avgHeartRate: 99, maxHeartRate: 110, caloriesBurned: 175)
                ]
            ),
            attemptStore: makeAttemptStore(),
            clock: clock
        )

        // Calories are still missing, so this climb is genuinely still enrichable.
        _ = await service.fetchNow(workout, modelContext: modelContext)

        #expect(workout.avgHeartRate == 155)
        #expect(workout.maxHeartRate == 181)
        #expect(workout.heartRateTimeSeries.count == 1)
        #expect(workout.caloriesBurned == 175)
    }

    // MARK: - Helpers

    private func makeService(
        metricsReader: ScriptedMetricsReader,
        attemptStore: AppleHealthEnrichmentAttemptStore,
        clock: TestClock,
        sessionWorkGate: AuthenticatedBootstrapCoordinator = AuthenticatedBootstrapCoordinator()
    ) -> AppleHealthEnrichmentService {
        AppleHealthEnrichmentService(
            authorizationController: StubAuthorizationController(connectionState: .connected),
            metricsReader: metricsReader,
            attemptStore: attemptStore,
            sessionWorkGate: sessionWorkGate,
            now: { clock.now }
        )
    }

    private func makeAttemptStore(
        schedule: AppleHealthEnrichmentSchedule = .standard
    ) -> AppleHealthEnrichmentAttemptStore {
        AppleHealthEnrichmentAttemptStore(
            defaults: UserDefaults(suiteName: "enrichment-\(UUID().uuidString)")!,
            schedule: schedule
        )
    }

    private func makeModelContext() throws -> ModelContext {
        try AscendLocalStoreFixture.makeModelContext()
    }

    private func makeLiveClimb(start: Date, duration: TimeInterval) -> Workout {
        Workout(
            name: "Live Climb",
            date: start,
            duration: duration,
            steps: 1_600,
            floors: Workout.stepsToFloors(1_600, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
    }
}

/// A clock the test advances by hand, so the schedule is exercised without sleeping through it.
private final class TestClock: @unchecked Sendable {
    private(set) var now: Date

    init(start: Date) {
        now = start
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
private final class ScriptedMetricsReader: HealthKitMetricsReading {
    private var responses: [WorkoutMetrics]
    private(set) var requestedWindows: [ClosedRange<Date>] = []

    init(responses: [WorkoutMetrics]) {
        self.responses = responses
    }

    func enqueue(_ metrics: WorkoutMetrics) {
        responses.append(metrics)
    }

    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics { WorkoutMetrics() }

    func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        requestedWindows.append(dateRange)
        guard !responses.isEmpty else { return WorkoutMetrics() }
        return responses.removeFirst()
    }
}

@MainActor
private final class StubAuthorizationController: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = true
    let hasCompletedInitialBackfill = true
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    var connectionState: AppleHealthConnectionState

    init(connectionState: AppleHealthConnectionState) {
        self.connectionState = connectionState
    }

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool {
        connectionState = .connected
        return true
    }
}
