import HealthKit
import SwiftData
import Testing

@testable import AscendApp

@MainActor
@Suite(.serialized)
struct WorkoutImportCoordinatorLiveClimbAppleHealthEnrichmentTests {
  @Test
  func refreshEnrichesSingleLiveClimbWithSingleAppleHealthWorkout() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date(timeIntervalSince1970: 1_777_000_000)
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 480, steps: 800)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "single-climb"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart.addingTimeInterval(-60),
        end: liveStart.addingTimeInterval(900)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let metricsReader = LiveClimbHealthKitMetricsReader(
        metrics: WorkoutMetrics(
          avgHeartRate: 142,
          maxHeartRate: 176,
          caloriesBurned: 92,
          heartRateTimeSeries: [
            HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(60), heartRate: 140)
          ],
          averageMETs: 8.5
        )
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [appleWorkout], addedSamples: [appleSample]),
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(liveWorkout.source == .headphoneMotion)
      #expect(liveWorkout.steps == 800)
      #expect(liveWorkout.duration == 480)
      #expect(liveWorkout.healthKitUUID == appleSample.externalRecordID)
      #expect(
        liveWorkout.sourceLink(for: .appleHealth)?.externalRecordID == appleSample.externalRecordID)
      #expect(liveWorkout.avgHeartRate == 142)
      #expect(liveWorkout.maxHeartRate == 176)
      #expect(liveWorkout.caloriesBurned == 92)
      #expect(liveWorkout.averageMETs == 8.5)
      #expect(liveWorkout.heartRateTimeSeries.count == 1)
      #expect(coordinator.pendingCandidates.isEmpty)
      #expect(metricsReader.requestedRanges[appleSample.externalRecordID]?.lowerBound == liveStart)
      #expect(
        metricsReader.requestedRanges[appleSample.externalRecordID]?.upperBound
          == liveStart.addingTimeInterval(480))
    }
  }

  @Test
  func refreshRevisitsLinkedWorkoutWhenHeartRateSamplesArriveLater() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-60 * 60)
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 1_200, steps: 1_600)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "delayed-heart-rate"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart,
        end: liveStart.addingTimeInterval(1_200)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let metricsReader = LiveClimbHealthKitMetricsReader(
        metricResponses: [
          WorkoutMetrics(),
          WorkoutMetrics(
            avgHeartRate: 148,
            maxHeartRate: 174,
            caloriesBurned: 210,
            heartRateTimeSeries: [
              HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(300), heartRate: 146),
              HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(900), heartRate: 158)
            ],
            averageMETs: 7.4
          )
        ]
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [appleWorkout],
          addedSamples: [appleSample]
        ),
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(liveWorkout.healthKitUUID == appleSample.externalRecordID)
      #expect(
        liveWorkout.sourceLink(for: .appleHealth)?.externalRecordID == appleSample.externalRecordID)
      #expect(liveWorkout.avgHeartRate == nil)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(metricsReader.requestedWorkoutIDs == [
        appleSample.externalRecordID,
        appleSample.externalRecordID
      ])
      #expect(liveWorkout.avgHeartRate == 148)
      #expect(liveWorkout.maxHeartRate == 174)
      #expect(liveWorkout.caloriesBurned == 210)
      #expect(liveWorkout.averageMETs == 7.4)
      #expect(liveWorkout.heartRateTimeSeries.count == 2)
    }
  }

  @Test
  func detailFetchRefreshesLinkedWorkoutByStableAppleHealthID() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-60 * 60)
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 1_200, steps: 1_600)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "detail-fetch"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart,
        end: liveStart.addingTimeInterval(1_200)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let metricsReader = LiveClimbHealthKitMetricsReader(
        metricResponses: [
          WorkoutMetrics(),
          WorkoutMetrics(
            avgHeartRate: 152,
            maxHeartRate: 179,
            caloriesBurned: 225,
            heartRateTimeSeries: [
              HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(600), heartRate: 154)
            ],
            averageMETs: 7.8
          )
        ]
      )
      let workoutReader = LiveClimbHealthKitWorkoutReader(
        workouts: [appleWorkout],
        addedSamples: [appleSample]
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: workoutReader,
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)
      let discoveryCountBeforeFetch = workoutReader.requestedDateRanges.count
      let didFetch = await coordinator.enrichInAppWorkoutWithAppleHealthIfPossible(
        liveWorkout,
        modelContext: modelContext,
        forceRangeDiscovery: true
      )

      #expect(didFetch)
      #expect(metricsReader.requestedWorkoutIDs == [
        appleSample.externalRecordID,
        appleSample.externalRecordID
      ])
      #expect(workoutReader.requestedDateRanges.count == discoveryCountBeforeFetch)
      #expect(liveWorkout.avgHeartRate == 152)
      #expect(liveWorkout.maxHeartRate == 179)
      #expect(liveWorkout.heartRateTimeSeries.count == 1)
    }
  }

  @Test
  func fullyEnrichedLinkedWorkoutIsNotProcessedAgain() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-60 * 60)
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 1_200, steps: 1_600)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "complete-enrichment"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart,
        end: liveStart.addingTimeInterval(1_200)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let metricsReader = LiveClimbHealthKitMetricsReader(
        metrics: WorkoutMetrics(
          avgHeartRate: 150,
          maxHeartRate: 175,
          caloriesBurned: 220,
          heartRateTimeSeries: [
            HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(600), heartRate: 150)
          ],
          averageMETs: 7.5
        )
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [appleWorkout],
          addedSamples: [appleSample]
        ),
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)
      await coordinator.refreshPendingImports(trigger: .backgroundObserver)
      let didFetch = await coordinator.enrichInAppWorkoutWithAppleHealthIfPossible(
        liveWorkout,
        modelContext: modelContext,
        forceRangeDiscovery: true
      )

      #expect(coordinator.appleHealthEnrichmentStatus(for: liveWorkout) == .complete)
      #expect(coordinator.appleHealthHeartRateEnrichmentStatus(for: liveWorkout) == .complete)
      #expect(didFetch == false)
      #expect(metricsReader.requestedWorkoutIDs == [appleSample.externalRecordID])
    }
  }

  @Test
  func heartRateRecoveryIsOnlyPendingForReachableEnrichmentStates() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      defer { stateSnapshot.restore() }
      resetHealthKitSyncStateForTest()

      let oldStart = Date().addingTimeInterval(-(80 * 60 * 60))
      let recentStart = Date().addingTimeInterval(-(2 * 60 * 60))
      let unlinkedWorkout = makeLiveClimbWorkout(start: oldStart, duration: 1_200, steps: 1_600)
      let staleLinkedWorkout = makeLiveClimbWorkout(start: oldStart, duration: 1_200, steps: 1_600)
      staleLinkedWorkout.healthKitUUID = UUID().uuidString
      let recentLinkedWorkout = makeLiveClimbWorkout(start: recentStart, duration: 1_200, steps: 1_600)
      recentLinkedWorkout.healthKitUUID = UUID().uuidString
      modelContext.insert(unlinkedWorkout)
      modelContext.insert(staleLinkedWorkout)
      modelContext.insert(recentLinkedWorkout)
      try modelContext.save()

      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(workouts: [], addedSamples: []),
        metricsReader: LiveClimbHealthKitMetricsReader()
      )

      #expect(coordinator.appleHealthEnrichmentStatus(for: unlinkedWorkout) == .notPending)
      #expect(coordinator.appleHealthHeartRateEnrichmentStatus(for: unlinkedWorkout) == .notPending)
      #expect(coordinator.appleHealthEnrichmentStatus(for: recentLinkedWorkout) == .metricsPending)
      #expect(
        coordinator.appleHealthHeartRateEnrichmentStatus(for: recentLinkedWorkout) == .metricsPending)
      #expect(coordinator.appleHealthEnrichmentStatus(for: staleLinkedWorkout) == .metricsStalled)
      #expect(
        coordinator.appleHealthHeartRateEnrichmentStatus(for: staleLinkedWorkout) == .metricsStalled)
    }
  }

  @Test
  func workoutWithHeartRateButMissingEnergyMetricsStaysEnrichmentEligible() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      defer { stateSnapshot.restore() }
      resetHealthKitSyncStateForTest()

      let liveStart = Date().addingTimeInterval(-(2 * 60 * 60))
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 1_200, steps: 1_600)
      liveWorkout.healthKitUUID = UUID().uuidString
      liveWorkout.avgHeartRate = 141
      liveWorkout.maxHeartRate = 168
      liveWorkout.heartRateData = [
        HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(600), heartRate: 142)
      ].encoded
      modelContext.insert(liveWorkout)
      try modelContext.save()

      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(workouts: [], addedSamples: []),
        metricsReader: LiveClimbHealthKitMetricsReader()
      )

      #expect(coordinator.appleHealthEnrichmentStatus(for: liveWorkout) == .metricsPending)
      #expect(coordinator.appleHealthHeartRateEnrichmentStatus(for: liveWorkout) == .complete)
    }
  }

  @Test
  func manualFetchStillResolvesLinkedWorkoutAfterAutomaticWindowExpires() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-(80 * 60 * 60))
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 1_200, steps: 1_600)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "stalled-fetch"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart,
        end: liveStart.addingTimeInterval(1_200)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      liveWorkout.healthKitUUID = appleSample.externalRecordID
      try modelContext.save()

      let metricsReader = LiveClimbHealthKitMetricsReader(
        metrics: WorkoutMetrics(
          avgHeartRate: 148,
          maxHeartRate: 172,
          caloriesBurned: 210,
          heartRateTimeSeries: [
            HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(600), heartRate: 149)
          ],
          averageMETs: 7.2
        )
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [appleWorkout],
          addedSamples: [appleSample]
        ),
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      #expect(coordinator.appleHealthEnrichmentStatus(for: liveWorkout) == .metricsStalled)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)
      #expect(metricsReader.requestedWorkoutIDs.isEmpty)
      #expect(liveWorkout.avgHeartRate == nil)

      let didFetch = await coordinator.enrichInAppWorkoutWithAppleHealthIfPossible(
        liveWorkout,
        modelContext: modelContext,
        forceRangeDiscovery: true
      )

      #expect(didFetch)
      #expect(metricsReader.requestedWorkoutIDs == [appleSample.externalRecordID])
      #expect(liveWorkout.avgHeartRate == 148)
      #expect(liveWorkout.maxHeartRate == 172)
      #expect(coordinator.appleHealthEnrichmentStatus(for: liveWorkout) == .complete)
    }
  }

  @Test
  func linkedMetricRefreshFailureDoesNotAbortRemainingEnrichment() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-60 * 60)
      let failingWorkout = makeLiveClimbWorkout(start: liveStart, duration: 1_200, steps: 1_600)
      failingWorkout.healthKitUUID = "failing-external-record"
      modelContext.insert(failingWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: failingWorkout, climbId: "failing-link"))

      let recoverableStart = liveStart.addingTimeInterval(-(4 * 60 * 60))
      let recoverableWorkout = makeLiveClimbWorkout(
        start: recoverableStart, duration: 1_200, steps: 1_600)
      modelContext.insert(recoverableWorkout)
      modelContext.insert(
        makeLiveClimbParticipation(for: recoverableWorkout, climbId: "recoverable-link"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: recoverableStart,
        end: recoverableStart.addingTimeInterval(1_200)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let metricsReader = LiveClimbHealthKitMetricsReader(
        metrics: WorkoutMetrics(
          avgHeartRate: 144,
          maxHeartRate: 168,
          caloriesBurned: 205,
          heartRateTimeSeries: [
            HeartRateDataPoint(timestamp: recoverableStart.addingTimeInterval(600), heartRate: 145)
          ],
          averageMETs: 7.1
        )
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [appleWorkout],
          addedSamples: [appleSample],
          failingExternalRecordIDs: ["failing-external-record"]
        ),
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(recoverableWorkout.avgHeartRate == 144)
      #expect(recoverableWorkout.healthKitUUID == appleSample.externalRecordID)
      #expect(failingWorkout.avgHeartRate == nil)
    }
  }

  @Test
  func refreshEnrichesJustClimbWithoutParticipationWithSingleAppleHealthWorkout() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let sessionStart = Date(timeIntervalSince1970: 1_777_005_000)
      let workout = makeHeadphoneMotionWorkout(
        name: "Just Climb",
        start: sessionStart,
        duration: 1_800,
        steps: 1_686
      )
      modelContext.insert(workout)
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: sessionStart,
        end: sessionStart.addingTimeInterval(1_801)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let metricsReader = LiveClimbHealthKitMetricsReader(
        metrics: WorkoutMetrics(
          avgHeartRate: 151,
          maxHeartRate: 178,
          caloriesBurned: 220,
          heartRateTimeSeries: [
            HeartRateDataPoint(timestamp: sessionStart.addingTimeInterval(120), heartRate: 145),
            HeartRateDataPoint(timestamp: sessionStart.addingTimeInterval(1_200), heartRate: 164)
          ],
          averageMETs: 7.8
        )
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [appleWorkout],
          addedSamples: [appleSample]
        ),
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(workout.source == .headphoneMotion)
      #expect(workout.participations.isEmpty)
      #expect(workout.steps == 1_686)
      #expect(workout.healthKitUUID == appleSample.externalRecordID)
      #expect(workout.avgHeartRate == 151)
      #expect(workout.maxHeartRate == 178)
      #expect(workout.caloriesBurned == 220)
      #expect(workout.averageMETs == 7.8)
      #expect(workout.heartRateTimeSeries.count == 2)
      #expect(coordinator.pendingCandidates.isEmpty)
      #expect(
        metricsReader.requestedRanges[appleSample.externalRecordID]?.lowerBound
          == sessionStart)
      #expect(
        metricsReader.requestedRanges[appleSample.externalRecordID]?.upperBound
          == sessionStart.addingTimeInterval(1_800))
    }
  }

  @Test
  func refreshEnrichesFutureParticipationContextWithoutPolicyChange() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let challengeStart = Date(timeIntervalSince1970: 1_777_006_000)
      let workout = makeHeadphoneMotionWorkout(
        name: "Weighted Class",
        start: challengeStart,
        duration: 900,
        steps: 1_100
      )
      modelContext.insert(workout)
      modelContext.insert(
        WorkoutParticipation(
          workout: workout,
          userId: nil,
          contextType: .challenge,
          contextId: "weighted-class",
          leaderboardEligible: true,
          verificationTier: .sensorVerified
        )
      )
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: challengeStart.addingTimeInterval(-30),
        end: challengeStart.addingTimeInterval(930)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [appleWorkout],
          addedSamples: [appleSample]
        ),
        metricsReader: LiveClimbHealthKitMetricsReader()
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(workout.source == .headphoneMotion)
      #expect(workout.participations.map(\.contextType) == [.challenge])
      #expect(workout.healthKitUUID == appleSample.externalRecordID)
      #expect(
        workout.sourceLink(for: .appleHealth)?.externalRecordID == appleSample.externalRecordID)
      #expect(coordinator.pendingCandidates.isEmpty)
    }
  }

  @Test
  func refreshDiscoversFinishedAppleHealthWorkoutNearLiveClimbWhenAnchorMissesIt()
    async throws
  {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-2 * 60 * 60)
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 2_347, steps: 3_042)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "cn-tower"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart,
        end: liveStart.addingTimeInterval(2_522)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let metricsReader = LiveClimbHealthKitMetricsReader(
        metrics: WorkoutMetrics(
          avgHeartRate: 153,
          maxHeartRate: 170,
          caloriesBurned: 651,
          restingCaloriesBurned: 83,
          heartRateTimeSeries: [
            HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(60), heartRate: 148),
            HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(1_800), heartRate: 160)
          ],
          averageMETs: 6
        )
      )
      let workoutReader = LiveClimbHealthKitWorkoutReader(
        workouts: [appleWorkout],
        addedSamples: [],
        dateRangeSamples: [appleSample]
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: workoutReader,
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(liveWorkout.source == .headphoneMotion)
      #expect(liveWorkout.duration == 2_347)
      #expect(liveWorkout.steps == 3_042)
      #expect(liveWorkout.healthKitUUID == appleSample.externalRecordID)
      #expect(liveWorkout.avgHeartRate == 153)
      #expect(liveWorkout.maxHeartRate == 170)
      #expect(liveWorkout.caloriesBurned == 651)
      #expect(liveWorkout.heartRateTimeSeries.count == 2)
      #expect(coordinator.pendingCandidates.isEmpty)
      #expect(metricsReader.requestedRanges[appleSample.externalRecordID]?.lowerBound == liveStart)
      #expect(
        metricsReader.requestedRanges[appleSample.externalRecordID]?.upperBound
          == liveStart.addingTimeInterval(2_347))
      #expect(workoutReader.requestedDateRanges.count == 1)
    }
  }

  @Test
  func refreshEnrichesWhenAppleHealthWorkoutStartsLateButOverlapsSession() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-3 * 60 * 60)
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 2_400, steps: 3_800)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "late-watch-climb"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart.addingTimeInterval(20 * 60),
        end: liveStart.addingTimeInterval(2_430)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let metricsReader = LiveClimbHealthKitMetricsReader(
        metrics: WorkoutMetrics(
          avgHeartRate: 149,
          maxHeartRate: 171,
          caloriesBurned: 410,
          heartRateTimeSeries: [
            HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(1_300), heartRate: 150)
          ],
          averageMETs: 7.1
        )
      )
      let workoutReader = LiveClimbHealthKitWorkoutReader(
        workouts: [appleWorkout],
        addedSamples: [],
        dateRangeSamples: [appleSample]
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: workoutReader,
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(liveWorkout.healthKitUUID == appleSample.externalRecordID)
      #expect(liveWorkout.avgHeartRate == 149)
      #expect(liveWorkout.maxHeartRate == 171)
      #expect(liveWorkout.heartRateTimeSeries.count == 1)
      #expect(metricsReader.requestedRanges[appleSample.externalRecordID]?.lowerBound == appleSample.startDate)
      #expect(
        metricsReader.requestedRanges[appleSample.externalRecordID]?.upperBound
          == liveStart.addingTimeInterval(2_400))
      #expect(workoutReader.requestedDateRanges.count == 1)
    }
  }

  @Test
  func refreshFallsBackToHeartRateSamplesWhenWorkoutMatchIsUnavailable() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-45 * 60)
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 2_603, steps: 4_134)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "window-fallback"))
      try modelContext.save()

      let metricsReader = LiveClimbHealthKitMetricsReader(
        timeWindowMetrics: WorkoutMetrics(
          avgHeartRate: 154,
          maxHeartRate: 181,
          heartRateTimeSeries: [
            HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(300), heartRate: 146),
            HeartRateDataPoint(timestamp: liveStart.addingTimeInterval(2_100), heartRate: 174)
          ]
        )
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [],
          addedSamples: [],
          dateRangeSamples: []
        ),
        metricsReader: metricsReader
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(liveWorkout.source == .headphoneMotion)
      #expect(liveWorkout.duration == 2_603)
      #expect(liveWorkout.steps == 4_134)
      #expect(liveWorkout.healthKitUUID == nil)
      #expect(liveWorkout.sourceLink(for: .appleHealth) == nil)
      #expect(liveWorkout.avgHeartRate == 154)
      #expect(liveWorkout.maxHeartRate == 181)
      #expect(liveWorkout.heartRateTimeSeries.count == 2)
      #expect(metricsReader.requestedTimeWindows.count == 1)
      #expect(metricsReader.requestedTimeWindows.first?.lowerBound == liveStart)
      #expect(
        metricsReader.requestedTimeWindows.first?.upperBound
          == liveStart.addingTimeInterval(2_603))
    }
  }

  @Test
  func detailRetryDoesNotRepeatHealthKitLookupInsideThrottleWindow() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-60 * 60)
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 1_200, steps: 1_500)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "retry-climb"))
      try modelContext.save()

      let workoutReader = LiveClimbHealthKitWorkoutReader(
        workouts: [],
        addedSamples: [],
        dateRangeSamples: []
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: workoutReader,
        metricsReader: LiveClimbHealthKitMetricsReader()
      )

      await coordinator.enrichInAppWorkoutWithAppleHealthIfPossible(
        liveWorkout,
        modelContext: modelContext
      )
      await coordinator.enrichInAppWorkoutWithAppleHealthIfPossible(
        liveWorkout,
        modelContext: modelContext
      )

      #expect(workoutReader.requestedDateRanges.count == 1)
      #expect(liveWorkout.healthKitUUID == nil)
      #expect(liveWorkout.sourceLink(for: .appleHealth) == nil)
    }
  }

  @Test
  func detailRetryStopsQueryingHealthKitAfterRetryWindowExpires() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-(80 * 60 * 60))
      let liveWorkout = makeLiveClimbWorkout(start: liveStart, duration: 1_200, steps: 1_500)
      modelContext.insert(liveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: liveWorkout, climbId: "expired-climb"))
      try modelContext.save()

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart,
        end: liveStart.addingTimeInterval(1_200)
      )
      let appleSample = makeAppleHealthSample(from: appleWorkout)
      let workoutReader = LiveClimbHealthKitWorkoutReader(
        workouts: [appleWorkout],
        addedSamples: [],
        dateRangeSamples: [appleSample]
      )
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: workoutReader,
        metricsReader: LiveClimbHealthKitMetricsReader()
      )

      await coordinator.enrichInAppWorkoutWithAppleHealthIfPossible(
        liveWorkout,
        modelContext: modelContext
      )

      #expect(workoutReader.requestedDateRanges.isEmpty)
      #expect(liveWorkout.healthKitUUID == nil)
      #expect(liveWorkout.sourceLink(for: .appleHealth) == nil)
    }
  }

  @Test
  func refreshEnrichesTwoLiveClimbsWithTwoDistinctAppleHealthWorkouts() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let firstStart = Date(timeIntervalSince1970: 1_777_010_000)
      let secondStart = firstStart.addingTimeInterval(1_500)
      let firstLiveWorkout = makeLiveClimbWorkout(start: firstStart, duration: 480, steps: 800)
      let secondLiveWorkout = makeLiveClimbWorkout(start: secondStart, duration: 600, steps: 1_000)
      modelContext.insert(firstLiveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: firstLiveWorkout, climbId: "first-climb"))
      modelContext.insert(secondLiveWorkout)
      modelContext.insert(
        makeLiveClimbParticipation(for: secondLiveWorkout, climbId: "second-climb"))
      try modelContext.save()

      let firstAppleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: firstStart.addingTimeInterval(-45),
        end: firstStart.addingTimeInterval(540)
      )
      let secondAppleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: secondStart.addingTimeInterval(-30),
        end: secondStart.addingTimeInterval(720)
      )
      let firstSample = makeAppleHealthSample(from: firstAppleWorkout)
      let secondSample = makeAppleHealthSample(from: secondAppleWorkout)
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [firstAppleWorkout, secondAppleWorkout],
          addedSamples: [firstSample, secondSample]
        ),
        metricsReader: LiveClimbHealthKitMetricsReader()
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(firstLiveWorkout.healthKitUUID == firstSample.externalRecordID)
      #expect(secondLiveWorkout.healthKitUUID == secondSample.externalRecordID)
      #expect(firstLiveWorkout.source == .headphoneMotion)
      #expect(secondLiveWorkout.source == .headphoneMotion)
      #expect(coordinator.pendingCandidates.isEmpty)
    }
  }

  @Test
  func refreshDoesNotLinkOneAppleHealthWorkoutToMultipleLiveClimbs() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
      let modelContext = try makeModelContext()
      let stateSnapshot = LiveClimbHealthKitSyncStateSnapshot.capture()
      let settingsSnapshot = LiveClimbSettingsSnapshot.capture()
      defer {
        stateSnapshot.restore()
        settingsSnapshot.restore()
      }
      resetHealthKitSyncStateForTest()
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let firstStart = Date(timeIntervalSince1970: 1_777_020_000)
      let secondStart = firstStart.addingTimeInterval(600)
      let firstLiveWorkout = makeLiveClimbWorkout(start: firstStart, duration: 300, steps: 500)
      let secondLiveWorkout = makeLiveClimbWorkout(start: secondStart, duration: 300, steps: 500)
      modelContext.insert(firstLiveWorkout)
      modelContext.insert(makeLiveClimbParticipation(for: firstLiveWorkout, climbId: "first-climb"))
      modelContext.insert(secondLiveWorkout)
      modelContext.insert(
        makeLiveClimbParticipation(for: secondLiveWorkout, climbId: "second-climb"))
      try modelContext.save()

      let longAppleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: firstStart.addingTimeInterval(-60),
        end: secondStart.addingTimeInterval(420)
      )
      let sample = makeAppleHealthSample(from: longAppleWorkout)
      let coordinator = WorkoutImportCoordinator(
        authorizationController: LiveClimbHealthKitAuthorizationController(),
        workoutReader: LiveClimbHealthKitWorkoutReader(
          workouts: [longAppleWorkout], addedSamples: [sample]),
        metricsReader: LiveClimbHealthKitMetricsReader()
      )
      coordinator.configure(modelContext: modelContext)

      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(firstLiveWorkout.healthKitUUID == nil)
      #expect(secondLiveWorkout.healthKitUUID == nil)
      #expect(firstLiveWorkout.sourceLink(for: .appleHealth) == nil)
      #expect(secondLiveWorkout.sourceLink(for: .appleHealth) == nil)
      #expect(coordinator.pendingCandidates.count == 1)
      #expect(
        coordinator.pendingCandidates.first?.appleHealthSample?.externalRecordID
          == sample.externalRecordID)
    }
  }

  private func makeModelContext() throws -> ModelContext {
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

  private func makeLiveClimbWorkout(start: Date, duration: TimeInterval, steps: Int) -> Workout {
    makeHeadphoneMotionWorkout(
      name: "Live Climb",
      start: start,
      duration: duration,
      steps: steps
    )
  }

  private func makeHeadphoneMotionWorkout(
    name: String,
    start: Date,
    duration: TimeInterval,
    steps: Int
  ) -> Workout {
    Workout(
      name: name,
      date: start,
      duration: duration,
      steps: steps,
      floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
      stepsPerFloor: 16,
      source: .headphoneMotion
    )
  }

  private func makeLiveClimbParticipation(for workout: Workout, climbId: String)
    -> WorkoutParticipation
  {
    WorkoutParticipation(
      workout: workout,
      userId: nil,
      contextType: .climbAttempt,
      contextId: climbId,
      leaderboardEligible: true,
      verificationTier: .sensorVerified
    )
  }

  private func makeAppleHealthSample(from workout: HKWorkout) -> HealthKitWorkoutSample {
    HealthKitWorkoutSample(
      externalRecordID: workout.uuid.uuidString,
      startDate: workout.startDate,
      endDate: workout.endDate,
      duration: workout.duration,
      sourceName: "Apple Watch",
      sourceBundleIdentifier: "com.apple.health",
      deviceModel: "Apple Watch"
    )
  }

  private func resetHealthKitSyncStateForTest() {
    HealthKitSyncState.hasRequestedAuthorization = true
    HealthKitSyncState.hasCompletedInitialBackfill = true
    HealthKitSyncState.lastSuccessfulCheckAt = nil
    HealthKitSyncState.workoutAnchorData = nil
    HealthKitSyncState.cachedWorkoutSamples = []
  }
}

private enum LiveClimbHealthKitReaderError: Error {
  case lookupFailed
}

@MainActor
private final class LiveClimbHealthKitWorkoutReader: HealthKitWorkoutReading {
  let isHealthDataAvailable = true
  private let workoutsByID: [String: HKWorkout]
  private let addedSamples: [HealthKitWorkoutSample]
  private let dateRangeSamples: [HealthKitWorkoutSample]
  private let failingExternalRecordIDs: Set<String>
  private(set) var requestedDateRanges: [ClosedRange<Date>] = []

  init(
    workouts: [HKWorkout],
    addedSamples: [HealthKitWorkoutSample],
    dateRangeSamples: [HealthKitWorkoutSample]? = nil,
    failingExternalRecordIDs: Set<String> = []
  ) {
    self.workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.uuid.uuidString, $0) })
    self.addedSamples = addedSamples
    self.dateRangeSamples = dateRangeSamples ?? addedSamples
    self.failingExternalRecordIDs = failingExternalRecordIDs
  }

  func fetchAnchoredStairStepperWorkouts(anchorData: Data?) async throws
    -> HealthKitWorkoutDiscoveryResult
  {
    HealthKitWorkoutDiscoveryResult(
      addedSamples: addedSamples,
      deletedExternalRecordIDs: [],
      anchorData: anchorData
    )
  }

  func fetchWorkout(withExternalRecordID externalRecordID: String) async throws -> HKWorkout? {
    if failingExternalRecordIDs.contains(externalRecordID) {
      throw LiveClimbHealthKitReaderError.lookupFailed
    }

    return workoutsByID[externalRecordID]
  }

  func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws
    -> [HealthKitWorkoutSample]
  {
    requestedDateRanges.append(dateRange)

    return dateRangeSamples.filter { sample in
      sample.startDate >= dateRange.lowerBound && sample.startDate <= dateRange.upperBound
    }
  }
}

@MainActor
private final class LiveClimbHealthKitMetricsReader: HealthKitMetricsReading {
  private let metrics: WorkoutMetrics
  private let timeWindowMetrics: WorkoutMetrics?
  private var metricResponses: [WorkoutMetrics]
  private(set) var requestedRanges: [String: ClosedRange<Date>] = [:]
  private(set) var requestedTimeWindows: [ClosedRange<Date>] = []
  private(set) var requestedWorkoutIDs: [String] = []

  init(
    metrics: WorkoutMetrics = WorkoutMetrics(
      avgHeartRate: 135, maxHeartRate: 165, caloriesBurned: 75),
    timeWindowMetrics: WorkoutMetrics? = nil,
    metricResponses: [WorkoutMetrics] = []
  ) {
    self.metrics = metrics
    self.timeWindowMetrics = timeWindowMetrics
    self.metricResponses = metricResponses
  }

  func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
    metrics
  }

  func fetchMetrics(for workout: HKWorkout, during dateRange: ClosedRange<Date>) async
    -> WorkoutMetrics
  {
    requestedRanges[workout.uuid.uuidString] = dateRange
    requestedWorkoutIDs.append(workout.uuid.uuidString)
    return nextMetricsResponse()
  }

  func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
    requestedTimeWindows.append(dateRange)
    return timeWindowMetrics ?? WorkoutMetrics()
  }

  private func nextMetricsResponse() -> WorkoutMetrics {
    guard metricResponses.isEmpty == false else { return metrics }
    return metricResponses.removeFirst()
  }
}

@MainActor
private final class LiveClimbHealthKitAuthorizationController: HealthKitAuthorizationControlling {
  let isHealthDataAvailable = true
  let hasRequestedAuthorization = true
  let hasCompletedInitialBackfill = true
  var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
  var lastPermissionErrorMessage: String?
  let connectionState: AppleHealthConnectionState = .connected

  func refreshAuthorizationRequestStatus() async {}

  func requestAuthorization() async -> Bool {
    true
  }
}

private struct LiveClimbHealthKitSyncStateSnapshot {
  let hasRequestedAuthorization: Bool
  let hasCompletedInitialBackfill: Bool
  let lastSuccessfulCheckAt: Date?
  let workoutAnchorData: Data?
  let cachedWorkoutSamples: [HealthKitWorkoutSample]

  static func capture() -> Self {
    LiveClimbHealthKitSyncStateSnapshot(
      hasRequestedAuthorization: HealthKitSyncState.hasRequestedAuthorization,
      hasCompletedInitialBackfill: HealthKitSyncState.hasCompletedInitialBackfill,
      lastSuccessfulCheckAt: HealthKitSyncState.lastSuccessfulCheckAt,
      workoutAnchorData: HealthKitSyncState.workoutAnchorData,
      cachedWorkoutSamples: HealthKitSyncState.cachedWorkoutSamples
    )
  }

  func restore() {
    HealthKitSyncState.hasRequestedAuthorization = hasRequestedAuthorization
    HealthKitSyncState.hasCompletedInitialBackfill = hasCompletedInitialBackfill
    HealthKitSyncState.lastSuccessfulCheckAt = lastSuccessfulCheckAt
    HealthKitSyncState.workoutAnchorData = workoutAnchorData
    HealthKitSyncState.cachedWorkoutSamples = cachedWorkoutSamples
  }
}

@MainActor
private struct LiveClimbSettingsSnapshot {
  let appleHealthAutoImportEnabled: Bool
  let appleHealthAutoImportActivatedAt: Date?

  static func capture() -> Self {
    LiveClimbSettingsSnapshot(
      appleHealthAutoImportEnabled: SettingsManager.shared.appleHealthAutoImportEnabled,
      appleHealthAutoImportActivatedAt: SettingsManager.shared.appleHealthAutoImportActivatedAt
    )
  }

  func restore() {
    SettingsManager.shared.appleHealthAutoImportEnabled = appleHealthAutoImportEnabled
    SettingsManager.shared.appleHealthAutoImportActivatedAt = appleHealthAutoImportActivatedAt
  }
}
