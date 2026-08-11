import Foundation
import HealthKit
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the two surfaces #438 added that the workout-detail proof does not cover:
/// the post-climb offer to connect Apple Health, and what a sparse or absent heart-rate series
/// renders as.
///
/// Both render the real production views, so a reviewer sees what the climber sees.
@MainActor
struct LiveClimbHeartRateConnectSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The offer is made to the climber who can act on it, and to nobody else.
    ///
    /// A hard gate on "Health is already connected" is what made enrichment invisible to
    /// everyone who had never connected (#438); the prompt is the replacement, and it has to
    /// stay off the summary for a climber who already connected or already has heart rate.
    @Test
    func offersTheConnectionOnlyOnAClimbThatEarnsIt() throws {
        let insideWindow = now.addingTimeInterval(-(30 * 60))
        let outsideWindow = now.addingTimeInterval(-(80 * 60 * 60))

        let neverConnected = makeService(connectionState: .neverConnected)
        let connected = makeService(connectionState: .connected)

        let blankClimb = makeSensorWorkout(start: insideWindow)

        let climbWithHeartRate = makeSensorWorkout(start: insideWindow)
        climbWithHeartRate.avgHeartRate = 151
        climbWithHeartRate.maxHeartRate = 176
        climbWithHeartRate.heartRateData = [
            HeartRateDataPoint(timestamp: insideWindow.addingTimeInterval(300), heartRate: 150)
        ].encoded

        let staleClimb = makeSensorWorkout(start: outsideWindow)

        // Offered: never connected, just finished, no heart rate on the climb.
        #expect(neverConnected.offersConnectionPrompt(for: blankClimb))
        // Not offered: the climb already has heart rate, so there is nothing to ask for.
        #expect(neverConnected.offersConnectionPrompt(for: climbWithHeartRate) == false)
        // Not offered: already connected - this climb is in the retry series instead.
        #expect(connected.offersConnectionPrompt(for: blankClimb) == false)
        // Not offered: past the eligibility window, where connecting would not backfill it.
        #expect(neverConnected.offersConnectionPrompt(for: staleClimb) == false)

        let proof = ConnectPromptProof(
            rows: [
                ConnectPromptRow(
                    id: "offered",
                    caption: "Never connected · climb has no heart rate · the ask lands here",
                    isConnecting: false
                ),
                ConnectPromptRow(
                    id: "connecting",
                    caption: "Tapped · the summary never blocks, Done stays where it was",
                    isConnecting: true
                ),
            ],
            suppressedCaptions: [
                "Already connected · this climb is already in the retry series",
                "Climb already has heart rate · nothing to ask for",
                "Past the retry window · connecting would not backfill it",
            ]
        )

        try render(proof, named: "live-climb-heart-rate-connect-prompt.png")
    }

    /// A Garmin that wrote two readings answered sparsely; it did not fail. The slot has to
    /// look like information at every density rather than like a broken chart.
    @Test
    func rendersEveryHeartRateDensitySensibly() throws {
        let start = now.addingTimeInterval(-(20 * 60))
        let duration: TimeInterval = 20 * 60

        func samples(_ bpms: [(TimeInterval, Int)]) -> [HeartRateDataPoint] {
            bpms.map { HeartRateDataPoint(timestamp: start.addingTimeInterval($0.0), heartRate: $0.1) }
        }

        let dense: [HeartRateDataPoint] = (0..<40).map { index in
            let offset = Double(index) * 30
            let wave: Int = Int(20 * sin(Double(index) / 4))
            let drift: Int = index / 6
            return HeartRateDataPoint(
                timestamp: start.addingTimeInterval(offset),
                heartRate: 128 + wave + drift
            )
        }

        let densities = [
            HeartRateDensityCase(
                id: "none",
                caption: "Wearable wrote nothing for this window",
                samples: [],
                average: nil,
                maximum: nil,
                duration: duration,
                start: start
            ),
            HeartRateDensityCase(
                id: "single",
                caption: "One reading · avg and max are still real, so they stay",
                samples: samples([(600, 149)]),
                average: 149,
                maximum: 149,
                duration: duration,
                start: start
            ),
            HeartRateDensityCase(
                id: "two",
                caption: "Two readings · the count is reported, not a failed load",
                samples: samples([(240, 141), (900, 163)]),
                average: 152,
                maximum: 163,
                duration: duration,
                start: start
            ),
            HeartRateDensityCase(
                id: "sparse",
                caption: "Five readings · charts with isolated points, no fake curve",
                samples: samples([(0, 118), (300, 144), (660, 159), (1_020, 166), (1_180, 138)]),
                average: 145,
                maximum: 166,
                duration: duration,
                start: start
            ),
            HeartRateDensityCase(
                id: "dense",
                caption: "Apple Watch cadence · the full trace",
                samples: dense,
                average: 141,
                maximum: 172,
                duration: duration,
                start: start
            ),
        ]

        // The two the chart cannot draw a line for must still say which case they are.
        #expect(
            HeartRateChartView.unavailableChartMessage(sampleCount: 0)
                == "No heart-rate samples for this climb"
        )
        #expect(
            HeartRateChartView.unavailableChartMessage(sampleCount: 2)
                == "Your wearable logged 2 readings for this climb - too few to chart"
        )

        try render(HeartRateDensityProof(cases: densities), named: "heart-rate-series-densities.png")
    }

    // MARK: - Helpers

    private func render(_ view: some View, named fileName: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3

        let image = try #require(renderer.uiImage, "ImageRenderer produced no image")
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: fileName))

        #expect(png.count > 5_000)
    }

    private func makeService(
        connectionState: AppleHealthConnectionState
    ) -> AppleHealthEnrichmentService {
        let capturedNow = now
        return AppleHealthEnrichmentService(
            authorizationController: ConnectPromptAuthorizationController(
                connectionState: connectionState
            ),
            metricsReader: ConnectPromptMetricsReader(),
            attemptStore: AppleHealthEnrichmentAttemptStore(
                defaults: UserDefaults(suiteName: "connect-prompt-\(UUID().uuidString)")!
            ),
            sessionWorkGate: AuthenticatedBootstrapCoordinator(),
            featureFlags: RemoteFeatureFlagStore(),
            now: { capturedNow }
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

private struct ConnectPromptRow: Identifiable {
    let id: String
    let caption: String
    let isConnecting: Bool
}

private struct ConnectPromptProof: View {
    let rows: [ConnectPromptRow]
    let suppressedCaptions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Live Climb summary · Apple Health connect prompt")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(row.id.uppercased()) · \(row.caption)")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    LiveClimbHeartRateConnectCard(
                        isConnecting: row.isConnecting,
                        onConnect: {},
                        onDismiss: {}
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.07))
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("NOT OFFERED")
                    .font(.montserratSemiBold(size: 11))
                    .foregroundStyle(Color.ascendAccent.opacity(0.9))

                ForEach(suppressedCaptions, id: \.self) { caption in
                    Text("· \(caption)")
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .padding(28)
        .frame(width: 420)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

private struct HeartRateDensityCase: Identifiable {
    let id: String
    let caption: String
    let samples: [HeartRateDataPoint]
    let average: Int?
    let maximum: Int?
    let duration: TimeInterval
    let start: Date
}

private struct HeartRateDensityProof: View {
    let cases: [HeartRateDensityCase]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Workout Detail · heart-rate series at every density")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            ForEach(cases) { density in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(density.id.uppercased()) · \(density.caption)")
                        .font(.montserratSemiBold(size: 11))
                        .foregroundStyle(Color.ascendAccent.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    HeartRateChartView(
                        heartRateData: density.samples,
                        workoutStartTime: density.start,
                        workoutDuration: density.duration,
                        averageHeartRateBpm: density.average,
                        maxHeartRateBpm: density.maximum
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.05))
                )
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
private final class ConnectPromptAuthorizationController: HealthKitAuthorizationControlling {
    let isHealthDataAvailable = true
    let hasRequestedAuthorization = false
    let hasCompletedInitialBackfill = false
    var authorizationRequestStatus: HKAuthorizationRequestStatus = .shouldRequest
    var lastPermissionErrorMessage: String?
    let connectionState: AppleHealthConnectionState

    init(connectionState: AppleHealthConnectionState) {
        self.connectionState = connectionState
    }

    func refreshAuthorizationRequestStatus() async {}

    func requestAuthorization() async -> Bool { true }
}

@MainActor
private final class ConnectPromptMetricsReader: HealthKitMetricsReading {
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
