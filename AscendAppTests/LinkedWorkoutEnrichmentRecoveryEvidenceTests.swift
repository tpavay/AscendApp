import Foundation
import HealthKit
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence for issue #251: an in-app sensor workout that acquires
/// an Apple Health link before Health has written its heart-rate and energy
/// samples must stay recoverable instead of going permanently ineligible.
///
/// The test drives the real `WorkoutImportCoordinator` through two background
/// refreshes - the first links the workout and finds no metrics, the second sees
/// the delayed samples land - and renders the exact Workout Detail surfaces the
/// climber sees in each state (`WorkoutHeartRateRecoveryCard` while pending,
/// `HeartRateChartView` plus the enriched secondary stats once complete).
@MainActor
@Suite(.serialized)
struct LinkedWorkoutEnrichmentRecoveryEvidenceTests {
  @Test("Linked workout recovers delayed Apple Health metrics", .bug(id: 251))
  func rendersPendingThenCompleteEnrichment() async throws {
    try await HealthKitImportCoordinatorTestIsolation.shared.run {
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

      let syncSnapshot = EnrichmentEvidenceSyncStateSnapshot.capture()
      let autoImportEnabled = SettingsManager.shared.appleHealthAutoImportEnabled
      defer {
        syncSnapshot.restore()
        SettingsManager.shared.appleHealthAutoImportEnabled = autoImportEnabled
      }
      HealthKitSyncState.hasRequestedAuthorization = true
      HealthKitSyncState.hasCompletedInitialBackfill = true
      HealthKitSyncState.lastSuccessfulCheckAt = nil
      HealthKitSyncState.workoutAnchorData = nil
      HealthKitSyncState.cachedWorkoutSamples = []
      SettingsManager.shared.appleHealthAutoImportEnabled = false

      let liveStart = Date().addingTimeInterval(-60 * 60)
      let workout = Workout(
        name: "Live Climb",
        date: liveStart,
        duration: 1_200,
        steps: 1_600,
        floors: Workout.stepsToFloors(1_600, stepsPerFloor: 16),
        stepsPerFloor: 16,
        source: .headphoneMotion
      )
      modelContext.insert(workout)
      let participation = WorkoutParticipation(
        workout: workout,
        userId: nil,
        contextType: .climbAttempt,
        contextId: "delayed-heart-rate",
        leaderboardEligible: true,
        verificationTier: .sensorVerified
      )
      modelContext.insert(participation)
      try modelContext.save()

      let workoutID = workout.id
      let originalSteps = workout.steps
      let originalDuration = workout.duration

      let appleWorkout = HKWorkout(
        activityType: .stairClimbing,
        start: liveStart,
        end: liveStart.addingTimeInterval(1_200)
      )
      let appleSample = HealthKitWorkoutSample(
        externalRecordID: appleWorkout.uuid.uuidString,
        startDate: appleWorkout.startDate,
        endDate: appleWorkout.endDate,
        duration: appleWorkout.duration,
        sourceName: "Apple Watch",
        sourceBundleIdentifier: "com.apple.health",
        deviceModel: "Apple Watch"
      )

      let beats = [138, 146, 151, 149, 156, 158, 161, 157, 152, 147]
      let delayedSeries = beats.enumerated().map { index, beat in
        HeartRateDataPoint(
          timestamp: liveStart.addingTimeInterval(Double(index + 1) * 110),
          heartRate: beat
        )
      }
      let coordinator = WorkoutImportCoordinator(
        authorizationController: EnrichmentEvidenceAuthorizationController(),
        workoutReader: EnrichmentEvidenceWorkoutReader(
          workout: appleWorkout,
          sample: appleSample
        ),
        metricsReader: EnrichmentEvidenceMetricsReader(
          responses: [
            // Health has written the workout but not yet its samples.
            WorkoutMetrics(),
            WorkoutMetrics(
              avgHeartRate: 148,
              maxHeartRate: 174,
              caloriesBurned: 210,
              heartRateTimeSeries: delayedSeries,
              averageMETs: 7.4
            )
          ]
        )
      )
      coordinator.configure(modelContext: modelContext)

      // Refresh 1 - the link lands, the metrics have not.
      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      let linkedID = try #require(workout.healthKitUUID)
      #expect(linkedID == appleSample.externalRecordID)
      #expect(workout.avgHeartRate == nil)
      #expect(workout.heartRateTimeSeries.isEmpty)
      let pendingStatus = coordinator.appleHealthEnrichmentStatus(for: workout)
      let pendingHeartRateStatus = coordinator.appleHealthHeartRateEnrichmentStatus(for: workout)
      #expect(pendingStatus == .metricsPending)
      #expect(pendingHeartRateStatus == .metricsPending)

      // Refresh 2 - Health finishes writing, the linked workout is revisited.
      await coordinator.refreshPendingImports(trigger: .backgroundObserver)

      #expect(workout.healthKitUUID == linkedID)
      #expect(workout.avgHeartRate == 148)
      #expect(workout.maxHeartRate == 174)
      #expect(workout.caloriesBurned == 210)
      #expect(workout.averageMETs == 7.4)
      #expect(workout.heartRateTimeSeries.count == beats.count)
      let completeStatus = coordinator.appleHealthEnrichmentStatus(for: workout)
      let completeHeartRateStatus = coordinator.appleHealthHeartRateEnrichmentStatus(for: workout)
      #expect(completeStatus == .complete)
      #expect(completeHeartRateStatus == .complete)

      // Identity, measurement, and leaderboard participation are untouched by enrichment.
      #expect(workout.id == workoutID)
      #expect(workout.steps == originalSteps)
      #expect(workout.duration == originalDuration)
      #expect(workout.source == .headphoneMotion)
      let persistedParticipation = try #require(
        try modelContext.fetch(FetchDescriptor<WorkoutParticipation>()).first
      )
      #expect(persistedParticipation.leaderboardEligible)
      #expect(persistedParticipation.verificationTier == .sensorVerified)

      let renderer = ImageRenderer(
        content: EnrichmentRecoveryProof(
          pendingStatus: pendingHeartRateStatus,
          completeStatus: completeHeartRateStatus,
          heartRateSamples: workout.heartRateTimeSeries,
          workoutStartTime: workout.date,
          workoutDuration: workout.duration,
          averageHeartRateBpm: workout.avgHeartRate,
          maxHeartRateBpm: workout.maxHeartRate,
          caloriesBurned: workout.caloriesBurned,
          averageMETs: workout.averageMETs,
          linkedHealthID: linkedID
        )
      )
      renderer.scale = 3

      let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
      let png = try #require(image.pngData(), "UIImage produced no PNG data")

      let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
        ?? NSTemporaryDirectory()
      let url = URL(filePath: directory)
        .appending(path: "linked-workout-delayed-enrichment.png")
      try png.write(to: url)

      #expect(png.count > 5_000)
    }
  }
}

/// Mirrors `WorkoutDetailView.heartRateSection` for both enrichment states, plus
/// the secondary stat row that carries the delayed calorie and MET values.
private struct EnrichmentRecoveryProof: View {
  let pendingStatus: WorkoutImportCoordinator.AppleHealthEnrichmentStatus
  let completeStatus: WorkoutImportCoordinator.AppleHealthEnrichmentStatus
  let heartRateSamples: [HeartRateDataPoint]
  let workoutStartTime: Date
  let workoutDuration: TimeInterval
  let averageHeartRateBpm: Int?
  let maxHeartRateBpm: Int?
  let caloriesBurned: Int?
  let averageMETs: Double?
  let linkedHealthID: String

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        Text("WORKOUT DETAIL · LINKED WORKOUT RECOVERS DELAYED HEALTH METRICS")
          .font(.montserratBold(size: 15))
          .foregroundStyle(.white)
        Text("Same Live Climb, same stable Health UUID \(linkedHealthID.prefix(8))…, two background refreshes of the real WorkoutImportCoordinator.")
          .font(.montserratRegular(size: 11))
          .foregroundStyle(.white.opacity(0.7))
          .fixedSize(horizontal: false, vertical: true)
      }

      panel(
        title: "Refresh 1 · linked, metrics have not landed",
        detail: "enrichment status \(describe(pendingStatus)) · avg HR nil · calories nil · METs nil"
      ) {
        WorkoutHeartRateRecoveryCard(
          connectionState: .connected,
          isFetching: false,
          hasStoppedAutomaticChecks: pendingStatus == .metricsStalled,
          message: nil,
          effectiveColorScheme: .dark,
          onFetch: {}
        )
      }

      panel(
        title: "Refresh 2 · delayed Health samples arrive",
        detail: "enrichment status \(describe(completeStatus)) · \(heartRateSamples.count) heart-rate samples · card gone"
      ) {
        VStack(alignment: .leading, spacing: 12) {
          HeartRateChartView(
            heartRateData: heartRateSamples,
            workoutStartTime: workoutStartTime,
            workoutDuration: workoutDuration,
            averageHeartRateBpm: averageHeartRateBpm,
            maxHeartRateBpm: maxHeartRateBpm
          )
          HStack(spacing: 28) {
            stat(label: "Calories", value: caloriesBurned.map(String.init) ?? "-")
            stat(
              label: "METs",
              value: averageMETs?.formatted(.number.precision(.fractionLength(1))) ?? "-"
            )
          }
        }
      }
    }
    .padding(24)
    .frame(width: 440)
    .background(Color.jet)
    .environment(\.colorScheme, .dark)
  }

  private func describe(
    _ status: WorkoutImportCoordinator.AppleHealthEnrichmentStatus
  ) -> String {
    switch status {
    case .notPending: return "notPending"
    case .linkPending: return "linkPending"
    case .metricsPending: return "metricsPending"
    case .metricsStalled: return "metricsStalled"
    case .complete: return "complete"
    }
  }

  @ViewBuilder
  private func stat(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.montserratBold(size: 18))
        .foregroundStyle(.white)
      Text(label.uppercased())
        .font(.montserratMedium(size: 10))
        .foregroundStyle(.white.opacity(0.6))
    }
  }

  @ViewBuilder
  private func panel(
    title: String,
    detail: String,
    @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.montserratSemiBold(size: 13))
        .foregroundStyle(Color.ascendAccent)
      Text(detail)
        .font(.montserratRegular(size: 11))
        .foregroundStyle(.white.opacity(0.75))
        .fixedSize(horizontal: false, vertical: true)
      content()
    }
  }
}

@MainActor
private final class EnrichmentEvidenceAuthorizationController: HealthKitAuthorizationControlling {
  let isHealthDataAvailable = true
  let hasRequestedAuthorization = true
  let hasCompletedInitialBackfill = true
  var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
  var lastPermissionErrorMessage: String?
  let connectionState: AppleHealthConnectionState = .connected

  func refreshAuthorizationRequestStatus() async {}

  func requestAuthorization() async -> Bool { true }
}

@MainActor
private final class EnrichmentEvidenceWorkoutReader: HealthKitWorkoutReading {
  let isHealthDataAvailable = true
  private let workout: HKWorkout
  private let sample: HealthKitWorkoutSample

  init(workout: HKWorkout, sample: HealthKitWorkoutSample) {
    self.workout = workout
    self.sample = sample
  }

  func fetchAnchoredStairStepperWorkouts(anchorData: Data?) async throws
    -> HealthKitWorkoutDiscoveryResult
  {
    HealthKitWorkoutDiscoveryResult(
      addedSamples: [sample],
      deletedExternalRecordIDs: [],
      anchorData: anchorData
    )
  }

  func fetchWorkout(withExternalRecordID externalRecordID: String) async throws -> HKWorkout? {
    externalRecordID == sample.externalRecordID ? workout : nil
  }

  func fetchStairStepperWorkouts(in dateRange: ClosedRange<Date>) async throws
    -> [HealthKitWorkoutSample]
  {
    (dateRange.contains(sample.startDate)) ? [sample] : []
  }
}

/// Hands back one scripted metrics response per lookup so the second refresh sees
/// the samples Health wrote after the first one.
@MainActor
private final class EnrichmentEvidenceMetricsReader: HealthKitMetricsReading {
  private var responses: [WorkoutMetrics]

  init(responses: [WorkoutMetrics]) {
    self.responses = responses
  }

  func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics {
    nextResponse()
  }

  func fetchMetrics(for workout: HKWorkout, during dateRange: ClosedRange<Date>) async
    -> WorkoutMetrics
  {
    nextResponse()
  }

  func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
    WorkoutMetrics()
  }

  private func nextResponse() -> WorkoutMetrics {
    responses.isEmpty ? WorkoutMetrics() : responses.removeFirst()
  }
}

private struct EnrichmentEvidenceSyncStateSnapshot {
  let hasRequestedAuthorization: Bool
  let hasCompletedInitialBackfill: Bool
  let lastSuccessfulCheckAt: Date?
  let workoutAnchorData: Data?
  let cachedWorkoutSamples: [HealthKitWorkoutSample]

  static func capture() -> Self {
    EnrichmentEvidenceSyncStateSnapshot(
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
