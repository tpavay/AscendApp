import CoreBluetooth
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence for the Just Me tab's hero-and-single-row redesign: a large
/// centered step count, the summit bar directly beneath it, and one bottom row of compact
/// stat cards (Elapsed, Current Rank, Pace, then Heart Rate last) sitting above End attempt -
/// all read off the real, shipping `LiveClimbSessionView` mid-recording, not a redrawn copy.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbJustMeRedesignEvidenceTests {
    @Test("The Just Me tab shows a large hero step count with no elevation card and no strap paired")
    func justMeShowsTheHeroAndDropsTheElevationCard() async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let climb = Self.climb
        let motionSession = FakeHeadphoneMotionSession()

        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [climb])
            ),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: context)
        motionSession.stepCount = 300
        motionSession.duration = 754 // 12:34

        #expect(viewModel.isRecording, "the redesigned chrome (photo background, hero, stat row) only shows while recording")
        #expect(viewModel.mode.targetStepCount == 900)
        #expect(viewModel.liveHeartRateStatus == nil, "no strap is remembered, so the row should fold to three boxes")

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let text = try await screen.copy()

            // The hero states current-vs-goal steps plainly and large - not a percentage-first number.
            #expect(text.contains("300"))
            #expect(text.contains("of"))
            #expect(text.contains("900 steps"))

            // The Elevation Climbed card is gone entirely - the captain found it not useful.
            #expect(!text.contains("elevation"), "the Elevation Climbed card must be removed: \(text)")

            // The row folds to three boxes with no strap paired: Elapsed, Current Rank, Pace.
            #expect(text.contains("elapsed"))
            #expect(text.contains("current rank"))
            #expect(text.contains("pace (steps per minute)"), "the PACE card is reused unchanged: \(text)")
            #expect(text.contains("current"))
            #expect(text.contains("average"))
            #expect(text.contains("24"), "300 steps / 12.57 minutes = 24 steps per minute")
            #expect(!text.contains("heart rate"), "no strap is remembered, so the heart-rate box must not render: \(text)")

            // The live percentage still rides the summit bar's fill, mid-climb (300/900 = 33%).
            #expect(text.contains("33%"))

            try screen.photograph(named: "just-me-redesign-hero-no-strap")
        }
    }

    @Test(
        "The heart-rate box appears only with a connected strap, at both phone widths",
        arguments: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes
    )
    func heartRateBoxTogglesTheRowBetweenThreeAndFourCards(size: CGSize) async throws {
        try await Self.assertStatRow(at: size, heartRateConnected: false)
        try await Self.assertStatRow(at: size, heartRateConnected: true)
    }

    /// Asserts every box the row should show at this width/state combination sits inside the
    /// screen's gutter, then asserts the heart-rate box's presence matches `heartRateConnected`
    /// exactly - so a box that fails to hide (or fails to appear) is caught either direction.
    private static func assertStatRow(at size: CGSize, heartRateConnected: Bool) async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let climb = Self.climb
        let motionSession = FakeHeadphoneMotionSession()

        let strap = heartRateConnected ? try await Self.makeConnectedHeartRateMonitor() : nil

        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [climb])
            ),
            leaderboardService: StubLiveReplayLeaderboardService(),
            heartRateRecorder: strap?.recorder ?? LiveHeartRateRecorder(),
            heartRateMonitor: strap?.monitor ?? HeartRateMonitorService(userDefaults: Self.freshDefaults())
        )

        viewModel.start(modelContext: context)
        motionSession.stepCount = 300
        motionSession.duration = 754 // 12:34

        if heartRateConnected {
            let strap = try #require(strap)
            let deviceID = try #require(strap.monitor.rememberedDevice?.id)
            strap.client.emit(.connected(id: deviceID, name: "Test Strap"))
            await Task.yield()
            strap.client.emit(.measurement(
                HeartRateMeasurement(beatsPerMinute: 128, sensorContact: .detected, receivedAt: Date())
            ))
            await Task.yield()
        }

        #expect(
            (viewModel.liveHeartRateStatus != nil) == heartRateConnected,
            "the view model's own heart-rate status must match the strap fixture before rendering"
        )

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: size
        ) { screen in
            let inside = screen.bounds.insetBy(dx: 8, dy: 0)
            var alwaysPresent = ["ELAPSED", "CURRENT RANK", "PACE (STEPS PER MINUTE)", "End attempt"]
            if heartRateConnected {
                alwaysPresent.append("HEART RATE")
            }

            for label in alwaysPresent {
                guard let frame = try await screen.frame(ofElementLabelled: label, reading: 40) else {
                    Issue.record("\(label) is not painted on the Just Me tab (heart rate connected: \(heartRateConnected)) at \(Int(size.width))pt")
                    continue
                }
                #expect(
                    inside.contains(frame),
                    "\(label) at \(frame.integral) spills past the screen's side gutter \(inside.integral) at \(Int(size.width))pt"
                )
            }

            let text = try await screen.copy()
            #expect(!text.contains("elevation"), "the Elevation Climbed card must stay removed")
            if !heartRateConnected {
                #expect(!text.contains("heart rate"), "the row must fold to three boxes with no strap paired")
            }

            try screen.photograph(named: "just-me-redesign-stat-row-\(heartRateConnected ? "hr" : "no-hr")-\(Int(size.width))pt")
        }
    }

    /// A remembered device plus a fake Bluetooth client wired through to `.connected`, mirroring
    /// `HeartRateMonitorServiceTests`. The monitor is not yet connected when this returns -
    /// `viewModel.start(modelContext:)` must run first, since that is what calls
    /// `autoConnectIfRemembered()` and creates the client the test then drives to `.connected`.
    private static func makeConnectedHeartRateMonitor() async throws -> (
        monitor: HeartRateMonitorService,
        recorder: LiveHeartRateRecorder,
        client: FakeBluetoothHeartRateClient
    ) {
        let defaults = Self.freshDefaults()
        let deviceID = UUID()
        defaults.set(deviceID.uuidString, forKey: "heartRateMonitor.rememberedDeviceID")
        defaults.set("Test Strap", forKey: "heartRateMonitor.rememberedDeviceName")

        let client = FakeBluetoothHeartRateClient()
        let monitor = HeartRateMonitorService(
            userDefaults: defaults,
            authorizationProvider: { .allowedAlways },
            clientFactory: { eventHandler in
                client.onEvent = eventHandler
                return client
            },
            connectionSleep: { duration in try await Task.sleep(for: duration) }
        )
        let recorder = LiveHeartRateRecorder(sources: [monitor])
        return (monitor, recorder, client)
    }

    private static func freshDefaults() -> UserDefaults {
        let suiteName = "LiveClimbJustMeRedesignEvidenceTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    private static let climb = Climb(
        id: "just-me-redesign-test-tower",
        name: "Test Tower",
        city: "Testville",
        country: "Testland",
        continent: "North America",
        latitude: 40.0,
        longitude: -74.0,
        totalHeightMeters: 300,
        totalHeightFeet: 984,
        realClimbableHeightMeters: nil,
        realClimbableHeightFeet: nil,
        totalSteps: 900,
        realStairCount: 900,
        calculatedFloors: 45,
        category: "tower",
        tier: .gold,
        tags: [],
        funFact: "Fact",
        sourceURL: "https://example.com",
        imageSetVersion: 1,
        releaseState: .available
    )
}
