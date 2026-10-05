import CoreBluetooth
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Product-level evidence for the Just Me tab's hero-and-centered-grid redesign: a large
/// centered step count, the summit bar directly beneath it, and a centered grid of medium
/// stat cards (Elapsed, Current Rank, Pace, Floors, then Heart Rate) sitting directly below the
/// bar - a 2x2 grid without a strap, three over two with one connected - all read off the
/// real, shipping `LiveClimbSessionView` mid-recording, not a redrawn copy.
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
        #expect(viewModel.liveHeartRateStatus == nil, "no strap is remembered, so the grid should hold four boxes")

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

            // The grid holds four boxes with no strap paired: Elapsed, Current Rank, Pace, Floors.
            #expect(text.contains("elapsed"))
            #expect(text.contains("current rank"))
            #expect(text.contains("floors"))
            #expect(text.contains("19"), "300 steps at sixteen a floor is 18.75, which the saved workout rounds to 19: \(text)")

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
        "The stat grid is two by two without a strap and three over two with one, floors on it both ways, at both phone widths",
        arguments: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes
    )
    func statGridHoldsFloorsWithAndWithoutAStrap(size: CGSize) async throws {
        try await Self.assertStatGrid(at: size, heartRateConnected: false)
        try await Self.assertStatGrid(at: size, heartRateConnected: true)
    }

    /// Asserts every box the grid should show at this width/state combination sits inside the
    /// screen's gutter, asserts the heart-rate box's presence matches `heartRateConnected`
    /// exactly, and asserts the grid's actual shape. Elapsed and Current Rank always share the
    /// first row and Pace always opens the second, at half the grid's width rather than
    /// stretched across it. Without a strap Floors sits beside Pace, under Current Rank; with
    /// one, Heart Rate takes that seat and Floors sits midway between Elapsed and Current Rank.
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
        #expect(viewModel.displayedFloors == 19, "300 steps at sixteen a floor, rounded as the saved workout rounds")

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
                    && texts.contains { $0.text == "FLOORS" }
                return heartRateConnected
                    ? hasCore && texts.contains { $0.text == "HEART RATE" }
                    : hasCore
            }
            // Exact matches only - "CURRENT" (the pace column label) is a substring of
            // "CURRENT RANK", so a fuzzy contains-match would collide with it.
            func exact(_ label: String) -> CGRect? {
                allTexts.first { $0.text == label }?.frame
            }

            var alwaysPresent = ["ELAPSED", "CURRENT RANK", "CURRENT", "AVERAGE", "FLOORS", "19", "12:34", "End attempt"]
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
            let floors = exact("FLOORS")
            let floorsValue = exact("19")
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

            // The floors figure sits over its own label, as every other box's value does.
            if let floors, let floorsValue {
                #expect(
                    abs(floorsValue.midX - floors.midX) < 4 && floorsValue.maxY <= floors.minY + 1,
                    "the floors figure \(floorsValue.integral) must sit directly over its label \(floors.integral)"
                )
            }

            // The pace card's true center is the midpoint of its two symmetric columns -
            // "AVERAGE" alone sits right-of-center within the card, so it is not a usable
            // proxy for the whole card's position on its own.
            if let paceCurrent, let paceAverage, let elapsed, let rank, let floors {
                let paceCenterX = (paceCurrent.midX + paceAverage.midX) / 2
                let paceCenterY = (paceCurrent.midY + paceAverage.midY) / 2
                // Half the grid's width from one row-two box to the other, whatever the top row holds.
                let halfGridPitch = screen.bounds.width / 2

                #expect(
                    paceCenterY > elapsed.midY,
                    "Pace (center y \(paceCenterY)) must sit on the row below Elapsed/Rank \(elapsed.integral)"
                )
                let paceSpread = paceAverage.midX - paceCurrent.midX
                #expect(
                    paceSpread > 0 && paceSpread < halfGridPitch * 0.75,
                    "the Pace card (label spread \(paceSpread)) must stay one half of the grid wide, not stretch across the row, at \(Int(size.width))pt"
                )
                #expect(
                    paceCenterX < screen.bounds.midX,
                    "Pace (center x \(paceCenterX)) must open the second row, at \(Int(size.width))pt"
                )

                if heartRateConnected, let heartRate {
                    // Three over two: Floors midway between Elapsed and Current Rank, then Pace
                    // and Heart Rate splitting the row below.
                    #expect(
                        abs(floors.midY - elapsed.midY) < 4,
                        "Floors \(floors.integral) must join Elapsed \(elapsed.integral) on the first row once a strap takes its seat"
                    )
                    #expect(
                        abs(floors.midX - (elapsed.midX + rank.midX) / 2) < 6,
                        "Floors \(floors.integral) must sit midway between Elapsed \(elapsed.integral) and Current Rank \(rank.integral)"
                    )
                    #expect(heartRate.midY > elapsed.midY, "Heart Rate \(heartRate.integral) must sit on the second grid row")
                    #expect(
                        abs((paceCenterX + heartRate.midX) / 2 - screen.bounds.midX) < 6,
                        "Pace (center x \(paceCenterX)) and Heart Rate \(heartRate.integral) must split the second row evenly"
                    )
                } else {
                    // Two by two: Pace under Elapsed's column, Floors under Current Rank's.
                    #expect(floors.midY > elapsed.midY, "Floors \(floors.integral) must sit on the second grid row")
                    #expect(
                        abs(paceCenterX - elapsed.midX) < 6,
                        "Pace (center x \(paceCenterX)) must align under Elapsed's column \(elapsed.integral)"
                    )
                    #expect(
                        abs(floors.midX - rank.midX) < 6,
                        "Floors \(floors.integral) must align under Current Rank's column \(rank.integral)"
                    )
                }
            }

            let text = try await screen.copy()
            #expect(!text.contains("elevation"), "the Elevation Climbed card must stay removed")
            #expect(!text.contains("pace"), "the word \"pace\" must not appear anywhere: \(text)")
            if !heartRateConnected {
                #expect(!text.contains("heart rate"), "no heart-rate box may render with no strap paired")
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
