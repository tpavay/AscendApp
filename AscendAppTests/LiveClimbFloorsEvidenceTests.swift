import CoreBluetooth
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Floors climbed, read off every surface that draws a climb in progress: the Just Me landmark
/// layouts, the Mountain read-out, the live leaderboard's own row (the Leaderboard tab, the
/// Mountain's second page and a routine all draw that panel), and the Live Activity row.
/// The Just Me photo layout's grid is `LiveClimbJustMeRedesignEvidenceTests`.
///
/// Each surface states the floors of the step count beside it - `Workout.stepsToFloors`, the
/// figure the saved workout carries - and fits it without pushing a neighbour off a compact
/// phone. Where a value could be squeezed rather than moved, it is read back with OCR, because
/// a truncated number keeps its full accessibility label.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbFloorsEvidenceTests {
    // MARK: - Just Me, over a landmark

    struct Landmark: Sendable, CustomTestStringConvertible {
        let id: String
        let steps: Int
        let size: CGSize
        var testDescription: String { "\(id) at \(Int(size.width))pt" }
    }

    /// A tall landmark, drawn beside its metrics, and a stocky one, drawn above them, each at
    /// both phone sizes.
    nonisolated static let landmarks: [Landmark] = LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes.flatMap { size in
        [
            Landmark(id: "empire-state-building", steps: 1_000, size: size),
            Landmark(id: "charminar", steps: 100, size: size),
        ]
    }

    @Test("The landmark layouts state floors on the step count's own caption line", arguments: landmarks)
    func theLandmarkLayoutsStateFloorsUnderTheStepCount(landmark: Landmark) async throws {
        let container = try Self.makeContainer()
        let climb = try #require(BundledClimbCatalog.climbs.first { $0.id == landmark.id })
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            climb: climb,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [climb])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            heartRateMonitor: HeartRateMonitorService(userDefaults: Self.freshDefaults()),
            progressImageRepository: FixtureClimbProgressImageRepository()
        )
        viewModel.start(modelContext: container.mainContext)
        await viewModel.loadProgressArtworkIfNeeded()
        #expect(viewModel.progressArtwork != nil, "\(landmark.id)'s cut-out loaded from its fixture")
        motionSession.stepCount = landmark.steps
        motionSession.duration = 754

        let floors = FloorsClimbed.phrase(Workout.stepsToFloors(landmark.steps))
        #expect(FloorsClimbed.phrase(viewModel.displayedFloors) == floors)

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: landmark.size
        ) { screen in
            let texts = try await screen.texts(reading: 60) { texts in
                texts.contains { $0.text.contains("ELAPSED") } && texts.contains { $0.text.contains("AVG") }
            }
            let stepsMetric = try #require(
                texts.first { $0.text.contains("of \(climb.referenceStepCount.formatted()) steps") },
                "the step count is on the tab: \(texts.map(\.text))"
            )
            #expect(stepsMetric.text.contains(floors), "floors ride the step count's captions: \(stepsMetric.text)")
            #expect(stepsMetric.text.contains("%"), "the percentage keeps its place beside them: \(stepsMetric.text)")

            let inside = screen.bounds.insetBy(dx: 8, dy: 0)
            #expect(inside.contains(stepsMetric.frame), "\(stepsMetric.frame.integral) spills past \(inside.integral)")

            // Nothing below the step count was pushed into it, or off the tab.
            let rank = try #require(texts.first { $0.text.contains("CURRENT RANK") })
            let endAttempt = try #require(texts.first { $0.text == "End attempt" })
            #expect(stepsMetric.frame.maxY <= rank.frame.minY + 0.5, "the step count \(stepsMetric.frame.integral) runs into Current Rank \(rank.frame.integral)")
            for label in ["ELAPSED", "CURRENT RANK", "AVG"] {
                let frame = try #require(texts.first { $0.text.contains(label) }).frame
                #expect(frame.maxY <= endAttempt.frame.minY, "\(label) at \(frame.integral) is pushed under End attempt \(endAttempt.frame.integral)")
            }

            let legible = try await screen.recognizedText(scale: 3)
            #expect(legible.contains(floors), "\(floors) is drawn in full: \(legible)")

            try screen.photograph(named: "floors-just-me-landmark-\(landmark.id)-\(Int(landmark.size.width))pt")
        }
    }

    // MARK: - Ascend Mountain

    @Test(
        "The Mountain read-out gives floors a box in its stat row, with and without a strap",
        arguments: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes
    )
    func theMountainReadOutStatesFloors(size: CGSize) async throws {
        try await Self.assertMountainStatRow(at: size, heartRateConnected: false)
        try await Self.assertMountainStatRow(at: size, heartRateConnected: true)
    }

    /// The row's hardest case: an hour-long clock, a four-digit floor count and, with a strap, a
    /// fourth box - each value still drawn in full.
    private static func assertMountainStatRow(at size: CGSize, heartRateConnected: Bool) async throws {
        let container = try Self.makeContainer()
        let motionSession = FakeHeadphoneMotionSession()
        let strap = heartRateConnected ? try await Self.makeConnectedHeartRateMonitor() : nil
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(kind: .steps, stepCount: 20_000),
            experience: .mountain,
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            heartRateRecorder: strap?.recorder ?? LiveHeartRateRecorder(),
            heartRateMonitor: strap?.monitor ?? HeartRateMonitorService(userDefaults: Self.freshDefaults())
        )
        viewModel.start(modelContext: container.mainContext)
        motionSession.stepCount = 18_888
        motionSession.duration = 7_199 // 1:59:59

        if let strap {
            let deviceID = try #require(strap.monitor.rememberedDevice?.id)
            strap.client.emit(.connected(id: deviceID, name: "Test Strap"))
            await Task.yield()
            strap.client.emit(.measurement(
                HeartRateMeasurement(beatsPerMinute: 128, sensorContact: .detected, receivedAt: Date())
            ))
            await Task.yield()
        }
        #expect((viewModel.liveHeartRateStatus != nil) == heartRateConnected)

        let floors = Workout.stepsToFloors(18_888).formatted()
        #expect(viewModel.displayedFloors.formatted() == floors)

        try await RenderedScreen.host(
            AscendMountainSessionHUD(viewModel: viewModel, debugState: nil, crowd: nil)
                .padding(.horizontal, 18)
                .background(Color.black),
            size: size
        ) { screen in
            let texts = try await screen.texts(reading: 60) { texts in
                texts.contains { $0.text.contains("FLOORS") }
            }
            var labels = ["SPM", "ELAPSED", "FLOORS"]
            if heartRateConnected {
                labels.append("BPM")
            }
            // The row sits on the screen's bottom edge here, where a box's frame rounds a
            // fraction of a point past it; the side gutters are what this bounds.
            let inside = screen.bounds.insetBy(dx: 8, dy: -1)
            let boxes = try labels.map { label in
                try #require(texts.first { $0.text.hasSuffix(label) }, "\(label) is not on the Mountain read-out: \(texts.map(\.text))")
            }
            for box in boxes {
                #expect(inside.contains(box.frame), "\(box.text) at \(box.frame.integral) spills past \(inside.integral)")
            }
            // One row, in reading order, no box overlapping the next.
            for (left, right) in zip(boxes, boxes.dropFirst()) {
                #expect(
                    abs(left.frame.minY - right.frame.minY) < 0.5 && abs(left.frame.height - right.frame.height) < 0.5,
                    "\(left.text) \(left.frame.integral) and \(right.text) \(right.frame.integral) are not one level row of equal boxes"
                )
                #expect(left.frame.maxX <= right.frame.minX, "\(left.text) \(left.frame.integral) overlaps \(right.text) \(right.frame.integral)")
            }
            let floorsBox = try #require(texts.first { $0.text.hasSuffix("FLOORS") })
            #expect(floorsBox.text.contains(floors), "the box reads the session's floors: \(floorsBox.text)")

            let legible = try await screen.recognizedText(scale: 3)
            for value in [floors, "1:59:59"] {
                #expect(legible.contains(value), "\(value) is drawn in full at \(Int(size.width))pt: \(legible)")
            }

            try screen.photograph(named: "floors-mountain-read-out-\(heartRateConnected ? "hr" : "no-hr")-\(Int(size.width))pt")
        }
    }

    // MARK: - The live leaderboard

    @Test("The Leaderboard tab states floors on the climber's own row, from the steps that row draws")
    func theLeaderboardTabStatesFloorsOnTheLiveRow() async throws {
        let container = try Self.makeContainer()
        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(kind: .steps, stepCount: 900),
            motionSession: motionSession,
            climbService: ClimbService(catalogRepository: StubClimbCatalogRepository(climbs: [])),
            leaderboardService: StubLiveReplayLeaderboardService(),
            heartRateMonitor: HeartRateMonitorService(userDefaults: Self.freshDefaults())
        )
        viewModel.start(modelContext: container.mainContext)
        motionSession.stepCount = 300
        motionSession.duration = 754

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes[0]
        ) { screen in
            _ = try await screen.texts(reading: 60) { texts in texts.contains { $0.text == "Leaderboard" } }
            try activateAccessibilityElement(labelled: "Leaderboard", in: screen.root)
            try await screen.settle(RenderedScreen.Settle.turns(60))

            let copy = try await screen.copy(reading: 60) { $0.contains("floors") }
            #expect(copy.contains("19 floors"), "300 steps at sixteen a floor, as the Just Me tab reads it: \(copy)")
            #expect(viewModel.displayedFloors == 19)

            try screen.photograph(named: "floors-leaderboard-tab-375pt")
        }
    }

    @Test(
        "Only the attempt in progress carries floors on the live board, under the climber's name",
        arguments: LiveClimbJustMePhotoBackgroundWidthTests.phoneSizes
    )
    func onlyTheLiveRowCarriesFloors(size: CGSize) async throws {
        let rows = Self.boardRows(currentSteps: 497)
        let panelSize = CGSize(width: size.width, height: 420)

        try await RenderedScreen.host(
            NavigationStack {
                // Configured as a routine configures it; the session's panel differs only in
                // dropping the filter.
                LiveReplayLeaderboardPanel(
                    rows: rows,
                    progressScaleSteps: 1_576,
                    targetStepGoal: 1_576,
                    progress: 497.0 / 1_576.0,
                    currentUserPhotoURL: nil,
                    // A previous best that lands the `BEST` marker's line on the floors
                    // line, which it has to pass behind as it does the name.
                    previousBestStepsAtBucket: 630,
                    fetchFailed: false,
                    standing: .racing(field: LiveReplayFieldSize(population: .climbers, count: 27), ownClimbs: nil),
                    tint: .accent,
                    effectiveColorScheme: .dark
                )
                .padding(18)
                .background(Color.black)
            },
            size: panelSize
        ) { screen in
            let texts = try await screen.texts(reading: 60) { texts in
                texts.contains { $0.text.contains("FLOORS") }
            }
            let rowsWithFloors = texts.filter { $0.text.contains("FLOORS") }
            #expect(rowsWithFloors.count == 1, "floors belong to the attempt in progress alone: \(texts.map(\.text))")

            let liveRow = try #require(rowsWithFloors.first)
            #expect(liveRow.text.contains("Tyler Pavay"), "the row is the climber's own: \(liveRow.text)")
            #expect(liveRow.text.contains("31 FLOORS"), "497 steps at sixteen a floor is 31.06: \(liveRow.text)")
            #expect(liveRow.text.contains("497"), "beside the steps they were counted from: \(liveRow.text)")
            #expect(screen.bounds.insetBy(dx: 8, dy: 0).contains(liveRow.frame))

            let legible = try await screen.recognizedText(scale: 3)
            #expect(legible.contains("31 floors"), "the line is drawn in full, with the BEST marker passing behind it: \(legible)")
            #expect(legible.contains("best"), "the marker is still flagged: \(legible)")

            try screen.photograph(named: "floors-live-board-row-\(Int(size.width))pt")
        }
    }

    // MARK: - The Live Activity

    /// What the Lock Screen hands the row on a phone `screenWidth` points wide: the system insets
    /// the activity 11 points a side, and the photo (58), the stop control (34), the two 14-point
    /// gaps between them and the 16-point padding take the rest.
    private static func lockScreenRowWidth(screenWidth: CGFloat) -> CGFloat {
        screenWidth - 22 - 32 - 58 - 34 - 28
    }

    /// The narrowest phone iOS 26 runs on. Its row was already too narrow for a standing with
    /// its field spelled out before floors existed, so what is held there is that floors made
    /// it no narrower (`floorsCostTheStandingNoWidth`), not that everything reads in full.
    private static let narrowestLockScreenRowWidth = lockScreenRowWidth(screenWidth: 375)
    /// The same row before floors, when a collapsed spacer still cost it a third 14-point gap.
    private static let narrowestLockScreenRowWidthBeforeFloors = narrowestLockScreenRowWidth - 14
    /// The narrowest phone with a Dynamic Island, and the width most phones share.
    private static let standardLockScreenRowWidth = lockScreenRowWidth(screenWidth: 393)

    @Test("The Live Activity states floors beneath its step count, and every column still reads in full")
    func theLiveActivityStatesFloorsBeneathSteps() async throws {
        let state = Self.activityState(steps: 497, rank: 12, rankTotal: 127)
        #expect(state.floors == Workout.stepsToFloors(497))

        for surface in [LiveClimbActivityMetricsRow.Surface.lockScreen, .expandedIsland] {
            let surfaceName = surface == .lockScreen ? "lock-screen" : "expanded-island"

            try await Self.hostActivityRow(state, surface: surface, width: Self.standardLockScreenRowWidth) { screen in
                let texts = try await screen.texts()
                let title = try #require(texts.first { $0.text == "STEPS" }, "\(texts.map(\.text))")
                let steps = try #require(texts.first { $0.text == "497" }, "\(texts.map(\.text))")
                let floors = try #require(texts.first { $0.text == "31 floors" }, "\(texts.map(\.text))")

                #expect(
                    abs(floors.frame.minX - steps.frame.minX) < 0.5 && abs(steps.frame.minX - title.frame.minX) < 0.5,
                    "floors sit in the step count's own column on the \(surfaceName) row"
                )
                #expect(floors.frame.minY >= steps.frame.maxY - 0.5, "floors sit beneath the step count on the \(surfaceName) row")
                for text in texts {
                    #expect(screen.bounds.contains(text.frame), "\(text.text) at \(text.frame.integral) leaves the \(surfaceName) row \(screen.bounds.integral)")
                }

                let legible = try await screen.recognizedText(scale: 4)
                for value in ["31 floors", "#12 of 127 climbers", "2nd of your 5 climbs", "5:50"] {
                    #expect(legible.contains(value), "\(value) is drawn in full on the \(surfaceName) row: \(legible)")
                }

                try screen.photograph(named: "floors-live-activity-\(surfaceName)")
            }
        }
    }

    /// Floors widen the Steps column while the step count is short, and the standing is what
    /// would pay for it. The Lock Screen gave the row back a gap it was wasting, so the standing
    /// has to come out no narrower than it was - at every step count's width, not just one.
    @Test(
        "Floors cost the Lock Screen's standing none of the width it had",
        arguments: [8, 97, 497, 999, 1_576, 12_345]
    )
    func floorsCostTheStandingNoWidth(steps: Int) async throws {
        let state = Self.activityState(steps: steps, rank: 12, rankTotal: 127)

        // The standing's width in the row as it was: no floors line, on the old budget.
        let before = try await Self.standingWidth(
            in: HStack(alignment: .top, spacing: LiveClimbActivityMetricsRow.Surface.lockScreen.spacing) {
                LiveClimbMetricColumn(title: "Steps", value: state.steps.formatted())
                LiveClimbMetricColumn(
                    title: state.standingTitle,
                    value: state.standingDetailLabel,
                    secondary: state.standingSecondaryLabel
                )
                LiveClimbMetricColumn(title: "Time", value: state.durationLabel)
            },
            width: Self.narrowestLockScreenRowWidthBeforeFloors
        )
        let after = try await Self.standingWidth(
            in: LiveClimbActivityMetricsRow(state: state, surface: .lockScreen),
            width: Self.narrowestLockScreenRowWidth
        )

        #expect(after >= before - 0.5, "\(steps) steps: the standing had \(before)pt and has \(after)pt")
    }

    /// The width the row gives its standing value, hosted at `width`.
    private static func standingWidth(in row: some View, width: CGFloat) async throws -> CGFloat {
        try await Self.hostActivityRow(row, width: width) { screen in
            let texts = try await screen.texts()
            return try #require(texts.first { $0.text == "#12 of 127 climbers" }, "\(texts.map(\.text))").frame.width
        }
    }

    private static func hostActivityRow<Result>(
        _ state: LiveClimbActivityAttributes.ContentState,
        surface: LiveClimbActivityMetricsRow.Surface,
        width: CGFloat,
        _ body: @MainActor (HostedScreen) async throws -> Result
    ) async throws -> Result {
        try await hostActivityRow(LiveClimbActivityMetricsRow(state: state, surface: surface), width: width, body)
    }

    private static func hostActivityRow<Result>(
        _ row: some View,
        width: CGFloat,
        _ body: @MainActor (HostedScreen) async throws -> Result
    ) async throws -> Result {
        // Taller than the row: the hosting window keeps its top safe area, and a line pushed
        // past the bottom edge is one the accessibility read no longer reports.
        let size = CGSize(width: width, height: 110)
        return try await RenderedScreen.host(
            row
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color.black)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark),
            size: size,
            body
        )
    }

    private static func activityState(steps: Int, rank: Int, rankTotal: Int) -> LiveClimbActivityAttributes.ContentState {
        LiveClimbActivityAttributes.ContentState(
            steps: steps,
            rank: rank,
            rankTotal: rankTotal,
            ownClimbs: .init(placing: 2, total: 5),
            board: .racing,
            durationSeconds: 350,
            progress: 0.3,
            status: .recording,
            climbPhotoURLString: nil,
            updatedAt: Date(timeIntervalSince1970: 1_787_957_195)
        )
    }

    // MARK: - Fixtures

    /// A rival ahead, the attempt in progress, and a rival behind.
    private static func boardRows(currentSteps: Int) -> [ModeratedReplayLeaderboardRow] {
        func rival(_ id: String, name: String, token: String, steps: Int, city: String) -> LiveReplayLeaderboardRow {
            LiveReplayLeaderboardRow(
                id: id,
                rank: nil,
                displayName: name,
                avatarToken: token,
                photoURL: nil,
                stepsAtBucket: steps,
                finalSteps: 1_576,
                deltaFromUser: steps - currentSteps,
                isCurrentUser: false,
                isLiveAttempt: false,
                isPersonalBest: true,
                completionDurationSeconds: 900,
                userId: id,
                gender: "woman",
                age: 31,
                locationCity: city
            )
        }

        let window = LiveReplayLeaderboardWindow(
            context: .liveClimb(climbId: "empire-state-building", targetSteps: 1_576),
            bucketIndex: 35,
            currentSteps: currentSteps,
            fetchedAt: Date(timeIntervalSince1970: 1_787_957_195),
            rows: [
                rival("rival-ahead", name: "Maya Okafor", token: "MO", steps: 560, city: "Austin"),
                rival("rival-behind", name: "Jonas Weber", token: "JW", steps: 410, city: "Berlin"),
            ],
            currentUserRank: 2,
            totalClimbers: 27,
            ownPreviousCompletionRow: nil
        )

        return window.locallyRankedRows(
            currentSteps: currentSteps,
            currentElapsedSeconds: 350,
            displayName: "Tyler Pavay"
        ).map {
            CrossUserIdentityAdapter.replayRow($0, blockedUserIds: [], isBlockListHydrated: true)
        }
    }

    /// A remembered strap behind a fake Bluetooth client, as `LiveClimbJustMeRedesignEvidenceTests`
    /// builds one. It connects once the session has started and the test emits `.connected`.
    private static func makeConnectedHeartRateMonitor() async throws -> (
        monitor: HeartRateMonitorService,
        recorder: LiveHeartRateRecorder,
        client: FakeBluetoothHeartRateClient
    ) {
        let defaults = Self.freshDefaults()
        defaults.set(UUID().uuidString, forKey: "heartRateMonitor.rememberedDeviceID")
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
        return (monitor, LiveHeartRateRecorder(sources: [monitor]), client)
    }

    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LiveClimbFloorsEvidenceTests.\(UUID().uuidString)")!
    }

    private static func makeContainer() throws -> ModelContainer {
        try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
    }
}
