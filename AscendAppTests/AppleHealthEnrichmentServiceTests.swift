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

        // Three callers asking at once is the real shape of this: a Home entry, the workout
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
        #expect(service.hasScheduledWakeUp == false)

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
        // And nothing is left waking the app up to rediscover that the climb aged out.
        #expect(service.hasScheduledWakeUp == false)
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
            authorizationController: EnrichmentStubAuthorization(connectionState: .neverConnected),
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
            authorizationController: EnrichmentStubAuthorization(connectionState: .connected),
            metricsReader: metricsReader,
            attemptStore: attemptStore,
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            featureFlags: flags,
            recordLifecycleState: { _ in },
            now: { clock.now }
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.isEmpty)
        #expect(workout.avgHeartRate == nil)
        #expect(service.hasScheduledWakeUp == false)
        // The ledger is untouched, so the series has lost nothing.
        #expect(attemptStore.attempt(for: workout.id) == nil)

        // A hand-requested check refuses in its own words rather than reporting a switched-off
        // read as "your wearable published nothing".
        await service.refreshPendingEnrichment(modelContext: modelContext, isUserInitiated: true)
        let refusal = try #require(service.lastErrorMessage)
        #expect(refusal.localizedStandardContains("checks resume"))
        #expect(metricsReader.requestedWindows.isEmpty)
        #expect(attemptStore.attempt(for: workout.id) == nil)

        _ = flags.apply(.shippedDefaults)
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(workout.avgHeartRate == 150)
    }

    /// The update lockout suppresses enrichment by never starting it, so this pins that not
    /// starting it is genuinely enough.
    ///
    /// `RootView.scheduleAuthenticatedSessionWork()` carries `guard
    /// !appVersionGateState.isUpdateRequired`, and the enrichment re-arm now lives inside that
    /// guarded chain rather than beside it in the foreground handler. Re-arming outside it let a
    /// binary the operator had retired keep writing: a pass goes through
    /// `WorkoutMutationHandler`, which marks pending remote upserts, rebuilds the leaderboard,
    /// and kicks the sync coordinator and profile publication.
    ///
    /// What a unit test cannot reach is the guard's placement inside a SwiftUI view function.
    /// What it can reach - and what the guard depends on completely - is that this service is
    /// inert until something explicitly starts it. If it ever self-armed (on init, on a
    /// notification, on an observer), the guard would protect nothing and this test would fail.
    @Test("Enrichment stays inert until something explicitly starts it")
    func performsNoWorkUntilStarted() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        // A climb that is due in every respect: recent, in-app, no heart rate, empty ledger.
        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(
            responses: [WorkoutMetrics(avgHeartRate: 150, maxHeartRate: 172, caloriesBurned: 200)]
        )
        let attemptStore = makeAttemptStore()
        let service = AppleHealthEnrichmentService(
            authorizationController: EnrichmentStubAuthorization(connectionState: .connected),
            metricsReader: metricsReader,
            attemptStore: attemptStore,
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            now: { clock.now }
        )

        // Nothing calls resumeTracking or trackNewlyRecordedWorkout - the lockout's position.
        // Time passing must not start it either, since the timer is the other way in.
        clock.advance(by: 6 * 60 * 60)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.isEmpty, "an unstarted service must read nothing")
        #expect(service.hasScheduledWakeUp == false, "an unstarted service must schedule no wake-up")
        #expect(attemptStore.attempt(for: workout.id) == nil, "no attempt may be spent")
        #expect(workout.avgHeartRate == nil, "no workout may be written")

        // And once the lockout lifts and the guarded chain does start it, the same climb is
        // picked up - so the suppression is a delay, not a permanent loss.
        service.resumeTracking(modelContext: modelContext)
        await service.drainInFlightWork()

        #expect(metricsReader.requestedWindows.count == 1)
        #expect(workout.avgHeartRate == 150)
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

    // MARK: - What a check reports, and to whom

    /// A message on the Integrations card belongs to the tap that produced it.
    ///
    /// Home refreshes enrichment from its `.task`, its tab handler and every foreground, so a
    /// refusal written by one of those would be waiting on a screen the climber opens later with
    /// nothing to attach it to.
    @Test("An automatic pass stays silent; a hand-requested check reports itself")
    func onlyAHandRequestedCheckWritesTheMessage() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let authorization = EnrichmentStubAuthorization(connectionState: .revoked)
        let service = AppleHealthEnrichmentService(
            authorizationController: authorization,
            metricsReader: ScriptedMetricsReader(responses: []),
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            recordLifecycleState: { _ in },
            now: { clock.now }
        )

        await service.refreshPendingEnrichment(modelContext: modelContext)
        #expect(service.lastErrorMessage == nil)

        await service.refreshPendingEnrichment(modelContext: modelContext, isUserInitiated: true)
        let reported = try #require(service.lastErrorMessage)
        #expect(reported.isEmpty == false)

        // Connecting clears it, and the next hand-requested check on a working connection leaves
        // nothing behind - so no refusal outlives the state that caused it.
        authorization.connectionState = .connected
        await service.refreshPendingEnrichment(modelContext: modelContext, isUserInitiated: true)
        #expect(service.lastErrorMessage == nil)
    }

    /// A failed check must not read as an empty one: telling the climber Health had nothing
    /// sends them to their own equipment for a failure that was ours.
    @Test("A failed Health query is reported as a failure, not as an empty answer")
    func reportsAFailedQueryDistinctlyFromAnEmptyOne() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let attemptStore = makeAttemptStore()
        let service = AppleHealthEnrichmentService(
            authorizationController: EnrichmentStubAuthorization(connectionState: .connected),
            metricsReader: FailingMetricsReader(),
            attemptStore: attemptStore,
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            recordLifecycleState: { _ in },
            now: { clock.now }
        )

        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()
        #expect(workout.avgHeartRate == nil)

        // The climb keeps its place in the series rather than being retired on a failure.
        #expect(attemptStore.nextEligibleDate(for: workout, at: clock.now) != nil)

        // The message says the check broke and blames nothing the climber owns.
        let message = AppleHealthEnrichmentService.checkFailedMessage
        #expect(message.isEmpty == false)
        for wearable in ["Watch", "Garmin", "Whoop", "Polar", "wearable"] {
            #expect(message.localizedStandardContains(wearable) == false)
        }

        // An automatic pass that fails stays silent; the hand-requested one says so.
        await service.refreshPendingEnrichment(modelContext: modelContext)
        #expect(service.lastErrorMessage == nil)

        clock.advance(by: 6 * 60 * 60)
        await service.refreshPendingEnrichment(modelContext: modelContext, isUserInitiated: true)
        #expect(service.lastErrorMessage == message)
    }

    /// The throttle in front of the lifecycle event is account-scoped, not a process-wide cache.
    ///
    /// Health authorization is device-wide, so the next climber to sign in on this device resolves
    /// the same state - and a throttle that survived the switch would decide their state was old
    /// news and never report it.
    @Test("Ending a session lets the next climber's connection state be reported")
    func reportsLifecycleStateAgainAfterASessionEnds() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let lifecycle = LifecycleStateSpy()
        let service = AppleHealthEnrichmentService(
            authorizationController: EnrichmentStubAuthorization(connectionState: .connected),
            metricsReader: ScriptedMetricsReader(responses: []),
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            recordLifecycleState: { lifecycle.record($0) },
            now: { clock.now }
        )

        await service.refreshPendingEnrichment(modelContext: modelContext)
        #expect(lifecycle.states == [.connected])

        service.cancelInFlightWork()

        await service.refreshPendingEnrichment(modelContext: modelContext)
        #expect(lifecycle.states == [.connected, .connected])
    }

    /// The lifecycle event is named for a change and costs a callable plus a Firestore
    /// transaction, so a climber bouncing between tabs must not bill one per Home entry.
    @Test("The backend hears a connection state when it changes, not on every entry")
    func reportsLifecycleStateOnlyWhenItChanges() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let authorization = EnrichmentStubAuthorization(connectionState: .connected)
        let lifecycle = LifecycleStateSpy()
        let service = AppleHealthEnrichmentService(
            authorizationController: authorization,
            metricsReader: ScriptedMetricsReader(responses: []),
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            recordLifecycleState: { lifecycle.record($0) },
            now: { clock.now }
        )

        // Home -> Leaderboard -> Home -> Profile -> Home, with nothing about Health changing.
        for _ in 0..<3 {
            await service.refreshPendingEnrichment(modelContext: modelContext)
        }
        #expect(lifecycle.states == [.connected])

        // A climber turning Ascend off in the Health app is news, and lands.
        authorization.connectionState = .revoked
        await service.refreshPendingEnrichment(modelContext: modelContext)
        #expect(lifecycle.states == [.connected, .revoked])

        await service.refreshPendingEnrichment(modelContext: modelContext)
        #expect(lifecycle.states == [.connected, .revoked])

        // A tap on Connect is itself the event, so it reports whatever it resolved to.
        _ = await service.requestAppleHealthAuthorizationIfNeeded()
        #expect(lifecycle.states == [.connected, .revoked, .revoked])
    }

    // MARK: - The Integrations connection path

    /// Settings -> Integrations is the only place Ascend offers the Apple Health connection, so
    /// the whole path is walked here: nothing is read while disconnected, and the card's own
    /// connect-then-refresh sequence is what puts heart rate on a climb already waiting for it.
    @Test("Connecting from Integrations reads the climbs that were waiting")
    func connectingFromIntegrationsEnrichesTheWaitingClimb() async throws {
        let clock = TestClock(start: Date(timeIntervalSince1970: 1_800_000_000))
        let modelContext = try makeModelContext()

        let workout = makeLiveClimb(start: clock.now.addingTimeInterval(-1_200), duration: 1_200)
        modelContext.insert(workout)
        try modelContext.save()

        let metricsReader = ScriptedMetricsReader(
            responses: [
                WorkoutMetrics(avgHeartRate: 151, maxHeartRate: 179, caloriesBurned: 220)
            ]
        )
        let service = AppleHealthEnrichmentService(
            authorizationController: EnrichmentStubAuthorization(connectionState: .neverConnected),
            metricsReader: metricsReader,
            attemptStore: makeAttemptStore(),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            recordLifecycleState: { _ in },
            now: { clock.now }
        )

        // No read happens while disconnected - there is nothing to read from.
        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()
        #expect(metricsReader.requestedWindows.isEmpty)

        // What the Integrations card does on a Connect tap, in that order.
        #expect(await service.requestAppleHealthAuthorizationIfNeeded())
        await service.refreshPendingEnrichment(modelContext: modelContext, isUserInitiated: true)

        #expect(service.lastErrorMessage == nil)
        #expect(metricsReader.requestedWindows.count == 1)
        #expect(workout.avgHeartRate == 151)
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
        service.trackNewlyRecordedWorkout(workout, modelContext: modelContext)
        await service.drainInFlightWork()

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
            authorizationController: EnrichmentStubAuthorization(connectionState: .connected),
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

/// A HealthKit read that errors rather than one that comes back empty.
@MainActor
private final class FailingMetricsReader: HealthKitMetricsReading {
    private(set) var attemptCount = 0

    func fetchMetrics(during dateRange: ClosedRange<Date>) async throws -> WorkoutMetrics {
        attemptCount += 1
        throw HealthKitMetricsReadError.queryFailed(
            NSError(domain: "com.apple.healthkit", code: 6)
        )
    }
}

@MainActor
private final class LifecycleStateSpy {
    private(set) var states: [AppleHealthConnectionState] = []

    func record(_ state: AppleHealthConnectionState) {
        states.append(state)
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
private final class EnrichmentStubAuthorization: HealthKitAuthorizationControlling {
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
