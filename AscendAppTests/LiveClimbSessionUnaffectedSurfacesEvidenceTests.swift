import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// Companion to `LiveClimbJustMePhotoBackgroundWidthTests`: the two in-session surfaces the
/// #594 fix must leave alone, read off the shipping `LiveClimbSessionView` at the same two
/// phone widths. The Leaderboard tab never draws the hero photo, and a Just Climb has no
/// landmark so no photo exists to draw - both are asserted here rather than assumed, and each
/// is photographed when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbSessionUnaffectedSurfacesEvidenceTests {
    nonisolated static let phoneSizes: [CGSize] = [
        CGSize(width: 375, height: 667),
        CGSize(width: 402, height: 874),
    ]

    private static let minimumSideGutter: CGFloat = 8

    @Test("The Leaderboard tab stays inside the screen and draws no hero photo", arguments: phoneSizes)
    func leaderboardTabStaysInsideTheScreen(size: CGSize) async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let climb = Self.climb
        let heroKey = try Self.plantHeroPhoto(for: climb)
        defer { try? DiskAssetCache.climbImages.remove(for: heroKey) }

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
        motionSession.stepCount = 214
        motionSession.duration = 150 // 2:30, so the pace card reads a plausible 86 steps per minute
        #expect(viewModel.isRecording)

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: size
        ) { screen in
            // Start from the Just Me tab with the photo painted, so the switch below is a real
            // transition away from the photo rather than a screen that never had one.
            try await Self.waitForHeroPhoto(on: screen)

            try activateAccessibilityElement(labelled: "Leaderboard", in: screen.root)
            try await screen.settle(RenderedScreen.Settle.turns(30))

            let probe = CGPoint(x: screen.bounds.midX, y: screen.bounds.midY)
            var stillMagenta = try screen.color(at: probe).isMagentaHued
            var reads = 0
            while stillMagenta, reads < 60 {
                try await screen.settle(RenderedScreen.Settle.turns(4))
                stillMagenta = try screen.color(at: probe).isMagentaHued
                reads += 1
            }
            #expect(
                !stillMagenta,
                "the hero photo is a Just Me surface and must not be drawn behind the Leaderboard tab"
            )

            try screen.photograph(named: "leaderboard-tab-over-planted-photo-\(Int(size.width))pt")

            let inside = screen.bounds.insetBy(dx: Self.minimumSideGutter, dy: 0)
            for label in ["Just Me", "Leaderboard", "End attempt"] {
                guard let frame = try await screen.frame(ofElementLabelled: label, reading: 40) else {
                    Issue.record("\(label) is not painted on the Leaderboard tab at \(Int(size.width))pt")
                    continue
                }
                #expect(
                    inside.contains(frame),
                    "\(label) at \(frame.integral) spills past the screen's side gutter \(inside.integral) at \(Int(size.width))pt"
                )
            }
        }
    }

    @Test("A Just Climb's Just Me tab stays inside the screen", arguments: phoneSizes)
    func justClimbStaysInsideTheScreen(size: CGSize) async throws {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self, WorkoutSourceLink.self, WorkoutParticipation.self,
            ClimbAttempt.self, BestEffortCacheEntry.self, BestEffortCacheMetadata.self
        )
        let context = container.mainContext

        let motionSession = FakeHeadphoneMotionSession()
        let viewModel = LiveClimbSessionViewModel(
            justClimbGoal: JustClimbGoal(kind: .steps, stepCount: 2_000),
            motionSession: motionSession,
            climbService: ClimbService(
                catalogRepository: StubClimbCatalogRepository(climbs: [])
            ),
            leaderboardService: StubLiveReplayLeaderboardService()
        )

        viewModel.start(modelContext: context)
        motionSession.stepCount = 214
        motionSession.duration = 150 // 2:30, so the pace card reads a plausible 86 steps per minute
        #expect(viewModel.isRecording)
        #expect(viewModel.mode.climb == nil, "a Just Climb has no landmark, so no photo can be drawn")

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: size
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("2,000 steps"), "the Just Climb goal is on screen: \(copy)")

            try screen.photograph(named: "just-climb-just-me-\(Int(size.width))pt")

            let inside = screen.bounds.insetBy(dx: Self.minimumSideGutter, dy: 0)
            for label in ["Just Me", "Leaderboard", "2,000 steps", "ELAPSED", "ELEVATION CLIMBED", "CURRENT RANK", "PACE (STEPS PER MINUTE)", "End attempt"] {
                guard let frame = try await screen.frame(ofElementLabelled: label, reading: 40) else {
                    Issue.record("\(label) is not painted on the Just Climb tab at \(Int(size.width))pt")
                    continue
                }
                #expect(
                    inside.contains(frame),
                    "\(label) at \(frame.integral) spills past the screen's side gutter \(inside.integral) at \(Int(size.width))pt"
                )
            }
        }
    }

    // MARK: - The planted photo

    private static let heroPhoto: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1350), format: {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return format
        }())
        return renderer.image { context in
            UIColor.magenta.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 2400, height: 1350)))
        }
    }()

    private static func plantHeroPhoto(for climb: Climb) throws -> String {
        let key = "climb-images/\(climb.id)/v\(climb.imageSetVersion)/hero.heic"
        let data = try #require(heroPhoto.pngData(), "the planted photo encodes")
        _ = try DiskAssetCache.climbImages.store(data, for: key)
        return key
    }

    private static func waitForHeroPhoto(on screen: HostedScreen) async throws {
        let probe = CGPoint(x: screen.bounds.midX, y: screen.bounds.midY)
        for _ in 0..<60 {
            let pixel = try screen.color(at: probe)
            if pixel.isMagentaHued { return }
            try await screen.settle(RenderedScreen.Settle.turns(4))
        }
        Issue.record("the hero photo never painted at \(probe); the read would only see the placeholder")
    }

    private static let climb = Climb(
        id: "unaffected-surfaces-width-tower",
        name: "Width Tower",
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

private extension RGBA {
    var isMagentaHued: Bool {
        Int(red) > Int(green) + 40 && Int(blue) > Int(green) + 40
    }
}
