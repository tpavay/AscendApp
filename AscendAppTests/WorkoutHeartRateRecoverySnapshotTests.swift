import Foundation
import HealthKit
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence that the heart-rate slot on Workout Detail is never blank.
///
/// `WorkoutDetailView` decides what the slot shows purely from
/// `AppleHealthEnrichmentService.phase(for:)`. This test builds real `Workout` values in each
/// state a climber can actually be in, asks a real service for the phase, applies the same
/// visibility rule the view uses, and renders the real `WorkoutHeartRateRecoveryCard` to a PNG
/// a reviewer can inspect.
///
/// The rendered copy is the point as much as the visibility: none of it names a device, because
/// heart rate reaches Ascend as Apple Health samples whoever wrote them (#438).
@MainActor
struct WorkoutHeartRateRecoverySnapshotTests {
    @Test
    func rendersAnHonestStateForEveryPhase() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let insideWindow = now.addingTimeInterval(-(2 * 60 * 60))
        let outsideWindow = now.addingTimeInterval(-(80 * 60 * 60))

        let connected = makeService(connectionState: .connected, now: now)
        let neverConnected = makeService(connectionState: .neverConnected, now: now)
        let revoked = makeService(connectionState: .revoked, now: now)
        let paused = makeService(
            connectionState: .connected,
            now: now,
            featureFlags: RemoteFeatureFlagStore(
                snapshot: .resolving(
                    remoteValues: [RemoteFeatureFlag.appleHealthEnrichment.key: false]
                )
            )
        )

        let waiting = makeSensorWorkout(start: insideWindow)
        let stopped = makeSensorWorkout(start: outsideWindow)
        let offered = makeSensorWorkout(start: insideWindow)
        let revokedWorkout = makeSensorWorkout(start: insideWindow)
        let pausedWorkout = makeSensorWorkout(start: insideWindow)

        let complete = makeSensorWorkout(start: insideWindow)
        complete.avgHeartRate = 148
        complete.maxHeartRate = 174
        complete.heartRateData = [
            HeartRateDataPoint(timestamp: insideWindow.addingTimeInterval(600), heartRate: 149)
        ].encoded

        let scenarios = [
            RecoveryScenario(
                id: "waiting",
                caption: "Connected · nothing published yet · more checks are scheduled",
                phase: connected.phase(for: waiting)
            ),
            RecoveryScenario(
                id: "stoppedLooking",
                caption: "Connected · past the retry window · manual check still works",
                phase: connected.phase(for: stopped)
            ),
            RecoveryScenario(
                id: "connectionOffered",
                caption: "Never connected · the offer is made here, not silently skipped",
                phase: neverConnected.phase(for: offered)
            ),
            RecoveryScenario(
                id: "accessRevoked",
                caption: "Access turned off in the Health app",
                phase: revoked.phase(for: revokedWorkout)
            ),
            RecoveryScenario(
                id: "checking",
                caption: "A read is in flight right now",
                phase: .checking
            ),
            RecoveryScenario(
                id: "checksPaused",
                caption: "Enrichment switched off at the backend · the climb keeps its place",
                phase: paused.phase(for: pausedWorkout)
            ),
            RecoveryScenario(
                id: "notApplicable",
                caption: "Heart rate attached · the chart replaces the card",
                phase: connected.phase(for: complete)
            ),
        ]

        #expect(scenarios[0].phase == .waiting)
        #expect(scenarios[1].phase == .stoppedLooking)
        #expect(scenarios[2].phase == .connectionOffered)
        #expect(scenarios[3].phase == .accessRevoked)
        #expect(scenarios[5].phase == .checksPaused)
        #expect(scenarios[6].phase == .notApplicable)

        // The whole point of the fix: every state a climber can be in says something.
        let visibleCount = scenarios.filter(\.isCardVisible).count
        #expect(visibleCount == scenarios.count - 1)
        #expect(scenarios[6].isCardVisible == false)

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

    private func makeService(
        connectionState: AppleHealthConnectionState,
        now: Date,
        featureFlags: RemoteFeatureFlagStore = RemoteFeatureFlagStore()
    ) -> AppleHealthEnrichmentService {
        AppleHealthEnrichmentService(
            authorizationController: RecoveryCardAuthorizationController(
                connectionState: connectionState
            ),
            metricsReader: RecoveryCardMetricsReader(),
            attemptStore: AppleHealthEnrichmentAttemptStore(
                defaults: UserDefaults(suiteName: "recovery-card-\(UUID().uuidString)")!
            ),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            featureFlags: featureFlags,
            now: { now }
        )
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
    let phase: AppleHealthEnrichmentService.Phase

    /// Mirrors `WorkoutDetailView`'s rule: everything except `notApplicable` renders the card.
    var isCardVisible: Bool {
        phase != .notApplicable
    }
}

private struct RecoveryStatesProof: View {
    let scenarios: [RecoveryScenario]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Workout Detail · Apple Health heart-rate states")
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
                            phase: scenario.phase,
                            message: nil,
                            effectiveColorScheme: .dark,
                            onPrimaryAction: {}
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
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .unnecessary
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState

    init(connectionState: AppleHealthConnectionState) {
        self.connectionState = connectionState
    }

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool { true }
}

@MainActor
private final class RecoveryCardMetricsReader: HealthKitMetricsReading {
    func fetchMetrics(during dateRange: ClosedRange<Date>) async -> WorkoutMetrics {
        WorkoutMetrics()
    }
}
