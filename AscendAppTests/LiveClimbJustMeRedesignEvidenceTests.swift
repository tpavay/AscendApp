import CoreBluetooth
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence for the Just Me tab's hero-and-centered-grid redesign: a large
/// centered step count, the summit bar directly beneath it, and a centered grid of medium
/// stat cards (Elapsed, Current Rank, Pace, then Heart Rate) sitting directly below the bar -
/// a 2x2 grid with a strap connected, two-and-one without one - all read off the real,
/// shipping `LiveClimbSessionView` mid-recording, not a redrawn copy.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbJustMeRedesignEvidenceTests {
    @Test("The Just Me tab shows a large hero step count with no elevation card, no PACE word, and no strap paired")
    func justMeShowsTheHeroAndDropsTheElevationCardAndTheWordPace() async throws {
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

        #expect(viewModel.isRecording, "the redesigned chrome (photo background, hero, stat grid) only shows while recording")
        #expect(viewModel.mode.targetStepCount == 900)
        #expect(viewModel.liveHeartRateStatus == nil, "no strap is remembered, so the grid should fold to three boxes")

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

            // The grid folds to three boxes with no strap paired: Elapsed, Current Rank, Pace.
            #expect(text.contains("elapsed"))
            #expect(text.contains("current rank"))

            // The word "pace" is gone entirely - each value is labeled directly instead.
            #expect(!text.contains("pace"), "the word \"pace\" must not appear anywhere: \(text)")
            #expect(text.contains("current"))
            #expect(text.contains("average"))
            #expect(text.contains("spm"), "each pace value carries its own SPM unit: \(text)")
            #expect(text.contains("24"), "300 steps / 12.57 minutes = 24 steps per minute")
            #expect(!text.contains("heart rate"), "no strap is remembered, so the heart-rate box must not render: \(text)")

            // The live percentage still rides the summit bar's fill, mid-climb (300/900 = 33%).
            #expect(text.contains("33%"))

            try screen.photograph(named: "just-me-redesign-hero-no-strap")
        }
    }

    @Test(
        "The heart-rate box toggles the grid between three (two-and-one) and four (2x2) cards, at both phone widths",
        arguments: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes
    )
    func heartRateBoxTogglesTheGridBetweenThreeAndFourCards(size: CGSize) async throws {
        try await Self.assertStatGrid(at: size, heartRateConnected: false)
        try await Self.assertStatGrid(at: size, heartRateConnected: true)
    }

    /// Asserts every box the grid should show at this width/state combination sits inside the
    /// screen's gutter, asserts the heart-rate box's presence matches `heartRateConnected`
    /// exactly, and asserts the grid's actual shape: Elapsed and Current Rank always share a
    /// row, Pace sits on the row below - alongside Heart Rate when a strap is connected, or
    /// alone and horizontally centered (not stretched) when it is not.
    private static func assertStatGrid(at size: CGSize, heartRateConnected: Bool) async throws {
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
            let allTexts = try await screen.texts(reading: 60) { texts in
                let hasCore = texts.contains { $0.text == "ELAPSED" }
                    && texts.contains { $0.text == "CURRENT RANK" }
                    && texts.contains { $0.text == "AVERAGE" }
                return heartRateConnected
                    ? hasCore && texts.contains { $0.text == "HEART RATE" }
                    : hasCore
            }
            // Exact matches only - "CURRENT" (the pace column label) is a substring of
            // "CURRENT RANK", so a fuzzy contains-match would collide with it.
            func exact(_ label: String) -> CGRect? {
                allTexts.first { $0.text == label }?.frame
            }

            var alwaysPresent = ["ELAPSED", "CURRENT RANK", "CURRENT", "AVERAGE", "End attempt"]
            if heartRateConnected {
                alwaysPresent.append("HEART RATE")
            }
            for label in alwaysPresent {
                guard let frame = exact(label) else {
                    Issue.record("\(label) is not painted on the Just Me tab (heart rate connected: \(heartRateConnected)) at \(Int(size.width))pt")
                    continue
                }
                #expect(
                    inside.contains(frame),
                    "\(label) at \(frame.integral) spills past the screen's side gutter \(inside.integral) at \(Int(size.width))pt"
                )
            }

            let elapsed = exact("ELAPSED")
            let rank = exact("CURRENT RANK")
            let paceCurrent = exact("CURRENT")
            let paceAverage = exact("AVERAGE")
            let heartRate = heartRateConnected ? exact("HEART RATE") : nil

            // Elapsed and Current Rank always share the grid's first row.
            if let elapsed, let rank {
                #expect(
                    abs(elapsed.midY - rank.midY) < 4,
                    "Elapsed \(elapsed.integral) and Current Rank \(rank.integral) must sit on the same grid row"
                )
            }

            // The pace card's true center is the midpoint of its two symmetric columns -
            // "AVERAGE" alone sits right-of-center within the card, so it is not a usable
            // proxy for the whole card's position on its own.
            if let paceCurrent, let paceAverage {
                let paceCenterX = (paceCurrent.midX + paceAverage.midX) / 2
                let paceCenterY = (paceCurrent.midY + paceAverage.midY) / 2

                if let elapsed {
                    #expect(
                        paceCenterY > elapsed.midY,
                        "Pace (center y \(paceCenterY)) must sit on the row below Elapsed/Rank \(elapsed.integral)"
                    )
                }

                if heartRateConnected, let heartRate, let elapsed, let rank {
                    // 2x2: Pace sits under Elapsed's column, Heart Rate under Rank's column.
                    #expect(heartRate.midY > elapsed.midY, "Heart Rate \(heartRate.integral) must sit on the second grid row")
                    #expect(
                        abs(paceCenterX - elapsed.midX) < 6,
                        "Pace (center x \(paceCenterX)) must align under Elapsed's column \(elapsed.integral)"
                    )
                    #expect(
                        abs(heartRate.midX - rank.midX) < 6,
                        "Heart Rate \(heartRate.integral) must align under Current Rank's column \(rank.integral)"
                    )
                } else {
                    // Two-and-one: the lone Pace box is centered, not stretched to fill the row.
                    #expect(
                        abs(paceCenterX - screen.bounds.midX) < 6,
                        "the lone Pace box (center x \(paceCenterX)) must be horizontally centered, not lopsided, at \(Int(size.width))pt"
                    )
                }
            }

            let text = try await screen.copy()
            #expect(!text.contains("elevation"), "the Elevation Climbed card must stay removed")
            #expect(!text.contains("pace"), "the word \"pace\" must not appear anywhere: \(text)")
            if !heartRateConnected {
                #expect(!text.contains("heart rate"), "the grid must fold to three boxes with no strap paired")
            }

            try screen.photograph(named: "just-me-redesign-stat-grid-\(heartRateConnected ? "hr" : "no-hr")-\(Int(size.width))pt")
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

    @Test("Heart rate reads once on Just Me, in the stat grid below the hero, and the Leaderboard tab keeps its top-right chip")
    func heartRateReadsOnceOnJustMeAndLeaderboardKeepsItsChip() async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let climb = Self.climb
        let motionSession = FakeHeadphoneMotionSession()
        let strap = try await Self.makeConnectedHeartRateMonitor()
        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [climb])
            ),
            leaderboardService: StubLiveReplayLeaderboardService(),
            heartRateRecorder: strap.recorder,
            heartRateMonitor: strap.monitor
        )

        viewModel.start(modelContext: container.mainContext)
        motionSession.stepCount = 300
        motionSession.duration = 754

        let deviceID = try #require(strap.monitor.rememberedDevice?.id)
        strap.client.emit(.connected(id: deviceID, name: "Test Strap"))
        await Task.yield()
        strap.client.emit(.measurement(
            HeartRateMeasurement(beatsPerMinute: 128, sensorContact: .detected, receivedAt: Date())
        ))
        await Task.yield()
        #expect(viewModel.liveHeartRateStatus != nil)

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container)
        ) { screen in
            let justMe = try await screen.texts(reading: 40) { texts in
                texts.contains { $0.text.localizedCaseInsensitiveContains("HEART RATE") }
            }
            let heartRateBadges = justMe.filter { $0.text.localizedCaseInsensitiveContains("beats per minute") }
            #expect(heartRateBadges.count == 1, "heart rate must read exactly once on Just Me: \(justMe.map(\.text))")
            let endAttempt = try #require(justMe.first { $0.text == "End attempt" })
            let leaderboardToggle = try #require(justMe.first { $0.text == "Leaderboard" })
            if let badge = heartRateBadges.first {
                #expect(
                    badge.frame.minY > leaderboardToggle.frame.maxY && badge.frame.maxY < endAttempt.frame.minY,
                    "the only heart-rate reading must sit in the stat grid below the hero, not the top-right slot: \(badge.frame.integral)"
                )
            }
            try screen.photograph(named: "just-me-redesign-hr-once-just-me")

            try activateAccessibilityElement(labelled: "Leaderboard", in: screen.root)
            // Let the tab switch cross-fade fully finish before reading anything - a read
            // taken mid-transition can pair a text with a stale frame.
            try await screen.settle(RenderedScreen.Settle.turns(60))
            var leaderboard: [OnScreenText] = []
            for _ in 0..<10 {
                leaderboard = try await screen.texts(reading: 60)
                let chip = leaderboard.first { $0.text.hasPrefix("Heart rate") && $0.text.localizedCaseInsensitiveContains("beats per minute") }
                if let chip, chip.frame.maxY < screen.bounds.height * 0.25 {
                    break
                }
                try await screen.settle(RenderedScreen.Settle.turns(6))
            }
            let chip = leaderboard.first { $0.text.hasPrefix("Heart rate") && $0.text.localizedCaseInsensitiveContains("beats per minute") }
            #expect(chip != nil, "the Leaderboard tab's own heart-rate chip must stay: \(leaderboard.map(\.text))")
            if let chip {
                #expect(chip.frame.maxY < screen.bounds.height * 0.25, "the Leaderboard chip stays in the top chrome: \(chip.frame.integral)")
            }
            try screen.photograph(named: "just-me-redesign-hr-leaderboard-chip")
        }
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
