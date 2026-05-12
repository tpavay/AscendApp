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

@MainActor
private final class LiveClimbHealthKitWorkoutReader: HealthKitWorkoutReading {
  let isHealthDataAvailable = true
  private let workoutsByID: [String: HKWorkout]
  private let addedSamples: [HealthKitWorkoutSample]

  init(workouts: [HKWorkout], addedSamples: [HealthKitWorkoutSample]) {
    self.workoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.uuid.uuidString, $0) })
    self.addedSamples = addedSamples
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
    workoutsByID[externalRecordID]
  }

  func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws
    -> [HealthKitWorkoutSample]
  {
    addedSamples.filter { sample in
      sample.startDate >= dateRange.lowerBound && sample.startDate <= dateRange.upperBound
    }
  }
}

@MainActor
private final class LiveClimbHealthKitMetricsReader: HealthKitMetricsReading {
  private let metrics: WorkoutMetrics
  private(set) var requestedRanges: [String: ClosedRange<Date>] = [:]

  init(
    metrics: WorkoutMetrics = WorkoutMetrics(
      avgHeartRate: 135, maxHeartRate: 165, caloriesBurned: 75)
  ) {
    self.metrics = metrics
  }

  func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
    metrics
  }

  func fetchMetrics(for workout: HKWorkout, during dateRange: ClosedRange<Date>) async
    -> WorkoutMetrics
  {
    requestedRanges[workout.uuid.uuidString] = dateRange
    return metrics
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
