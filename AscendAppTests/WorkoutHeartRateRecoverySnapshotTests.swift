import Foundation
import HealthKit
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the Apple Health heart-rate recovery card on Workout Detail.
///
/// `WorkoutDetailView` decides whether to show the card - and which copy it shows -
/// purely from `WorkoutImportCoordinator.appleHealthHeartRateEnrichmentStatus(for:)`
/// (see WorkoutDetailView.swift `shouldShowAppleHealthHeartRateRecovery`). This test
/// builds real `Workout` values in each enrichment state, asks a real coordinator for
/// the status, applies the same visibility switch the view uses, and renders the real
/// `WorkoutHeartRateRecoveryCard` to a PNG a reviewer can inspect.
///
/// Rows, top to bottom:
///   linkPending     -> in-app sensor workout inside the retry window, not yet linked
///   metricsPending  -> linked by stable Health UUID, metrics still arriving (card shows)
///   metricsStalled  -> linked but past the automatic retry window ("Stopped checking")
///   complete        -> heart rate present, card hidden, no reprocessing
@MainActor
struct WorkoutHeartRateRecoverySnapshotTests {
    @Test
    func rendersRecoveryCardOnlyForPendingEnrichmentStates() throws {
        let stateSnapshot = HealthKitSyncState.hasRequestedAuthorization
        defer { HealthKitSyncState.hasRequestedAuthorization = stateSnapshot }
        HealthKitSyncState.hasRequestedAuthorization = true

        let coordinator = WorkoutImportCoordinator(
            authorizationController: RecoveryCardAuthorizationController(),
            workoutReader: RecoveryCardWorkoutReader(),
            metricsReader: RecoveryCardMetricsReader()
        )

        let now = Date()
        let insideWindow = now.addingTimeInterval(-(2 * 60 * 60))
        let outsideWindow = now.addingTimeInterval(-(80 * 60 * 60))

        let linkPending = makeSensorWorkout(start: insideWindow)

        let metricsPending = makeSensorWorkout(start: insideWindow)
        metricsPending.healthKitUUID = UUID().uuidString

        let metricsStalled = makeSensorWorkout(start: outsideWindow)
        metricsStalled.healthKitUUID = UUID().uuidString

        let complete = makeSensorWorkout(start: insideWindow)
        complete.healthKitUUID = UUID().uuidString
        complete.avgHeartRate = 148
        complete.maxHeartRate = 174
        complete.heartRateData = [
            HeartRateDataPoint(timestamp: insideWindow.addingTimeInterval(600), heartRate: 149)
        ].encoded

        let scenarios = [
            RecoveryScenario(
                id: "linkPending",
                caption: "Linked to no Health workout yet · still inside retry window",
                status: coordinator.appleHealthHeartRateEnrichmentStatus(for: linkPending)
            ),
            RecoveryScenario(
                id: "metricsPending",
                caption: "Linked by stable Health UUID · heart rate has not landed yet",
                status: coordinator.appleHealthHeartRateEnrichmentStatus(for: metricsPending)
            ),
            RecoveryScenario(
                id: "metricsStalled",
                caption: "Linked · automatic retry window expired · manual Fetch still works",
                status: coordinator.appleHealthHeartRateEnrichmentStatus(for: metricsStalled)
            ),
            RecoveryScenario(
                id: "complete",
                caption: "Heart rate enriched · card must disappear",
                status: coordinator.appleHealthHeartRateEnrichmentStatus(for: complete)
            ),
        ]

        #expect(scenarios[0].status == .linkPending)
        #expect(scenarios[1].status == .metricsPending)
        #expect(scenarios[2].status == .metricsStalled)
        #expect(scenarios[3].status == .complete)
        #expect(scenarios[2].isCardVisible)
        #expect(scenarios[3].isCardVisible == false)

        let renderer = ImageRenderer(content: RecoveryStatesProof(scenarios: scenarios))
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory)
            .appending(path: "workout-heart-rate-recovery-states.png")
        try png.write(to: url)

        #expect(png.count > 5_000)
    }

    private func makeSensorWorkout(start: Date) -> Workout {
        Workout(
            name: "Live Climb",
            date: start,
            duration: 1_200,
            steps: 1_600,
            floors: Workout.stepsToFloors(1_600, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
    }
}

private struct RecoveryScenario: Identifiable {
    let id: String
    let caption: String
    let status: WorkoutImportCoordinator.AppleHealthEnrichmentStatus

    /// Mirrors `WorkoutDetailView.shouldShowAppleHealthHeartRateRecovery`.
    var isCardVisible: Bool {
        switch status {
        case .linkPending, .metricsPending, .metricsStalled:
            return true
        case .notPending, .complete:
            return false
        }
    }

    var hasStoppedAutomaticChecks: Bool {
        status == .metricsStalled
    }
}

private struct RecoveryStatesProof: View {
    let scenarios: [RecoveryScenario]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Workout Detail · Apple Health heart-rate recovery")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            ForEach(scenarios) { scenario in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(scenario.id.uppercased()) · \(scenario.caption)")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    if scenario.isCardVisible {
                        WorkoutHeartRateRecoveryCard(
                            connectionState: .connected,
                            isFetching: false,
                            hasStoppedAutomaticChecks: scenario.hasStoppedAutomaticChecks,
                            message: nil,
                            effectiveColorScheme: .dark,
                            onFetch: {}
                        )
                    } else {
                        Text("Recovery card hidden")
                            .font(.montserratMedium(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            )
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(Color.black)
    }
}

@MainActor
private final class RecoveryCardAuthorizationController: HealthKitAuthorizationControlling {
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
private final class RecoveryCardWorkoutReader: HealthKitWorkoutReading {
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
private final class RecoveryCardMetricsReader: HealthKitMetricsReading {
    func fetchMetrics(for workout: HKWorkout) async -> WorkoutMetrics { WorkoutMetrics() }

    func fetchMetrics(for workout: HKWorkout, during dateRange: ClosedRange<Date>) async
        -> WorkoutMetrics
    {
        WorkoutMetrics()
    }

    func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        WorkoutMetrics()
    }
}
