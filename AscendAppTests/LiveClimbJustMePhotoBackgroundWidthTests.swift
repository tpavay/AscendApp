import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import AscendApp

/// The Just Me tab draws the climb's hero photo full-bleed behind the session
/// (`LiveClimbSessionView.sessionBackground`). A photo scaled to fill a phone
/// is far wider than the phone, and a filled `Image` reports that width as its
/// own layout size, so without a bound the whole session panel - the tab bar,
/// the steps header, the stat row and the End attempt bar - laid out at the
/// photo's width, centred, and spilled off both edges of the screen (captain's
/// dev build, 2026-09-23). Read off the shipping view mid-recording with a
/// landscape photo planted where the artwork loader looks, at two phone widths.
///
/// Photographed when `ASCEND_EVIDENCE_DIR` is set, and not drawn otherwise.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct LiveClimbJustMePhotoBackgroundWidthTests {
    /// iPhone SE (3rd generation) and the iPhone 16 Pro width every other evidence suite hosts at.
    nonisolated static let phoneSizes: [CGSize] = [
        CGSize(width: 375, height: 667),
        CGSize(width: 402, height: 874), // RenderedScreen.iPhone16ProSize, restated because it is main-actor isolated
    ]

    /// Every label the tab publishes has to sit at least this far inside both screen edges.
    /// The narrowest side padding the panel uses is 18pt, so anything closer than this to an
    /// edge has been laid out wider than the screen.
    private static let minimumSideGutter: CGFloat = 8

    @Test("Every Just Me surface stays inside the screen over a full-bleed hero photo", arguments: phoneSizes)
    func justMeStaysInsideTheScreen(size: CGSize) async throws {
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
        motionSession.duration = 15

        #expect(viewModel.isRecording, "the photo background only shows while recording")

        try await RenderedScreen.host(
            LiveClimbSessionView(viewModel: viewModel)
                .environment(ModerationStore.shared)
                .modelContainer(container),
            size: size
        ) { screen in
            try await Self.waitForHeroPhoto(on: screen)
            try screen.photograph(named: "just-me-photo-background-\(Int(size.width))pt")

            // A label laid out past the edge is published by the tree but never painted, and
            // `frame(ofElementLabelled:)` reads only painted text - so "missing" and "spilled"
            // are the same defect here, and every label is reported rather than the first.
            let inside = screen.bounds.insetBy(dx: Self.minimumSideGutter, dy: 0)
            for label in ["Just Me", "Leaderboard", "900 steps", "ELAPSED", "REMAINING", "CURRENT RANK", "End attempt"] {
                guard let frame = try await screen.frame(ofElementLabelled: label, reading: 40) else {
                    Issue.record("\(label) is not painted on the Just Me tab at \(Int(size.width))pt")
                    continue
                }
                #expect(
                    inside.contains(frame),
                    "\(label) at \(frame.integral) spills past the screen's side gutter \(inside.integral) at \(Int(size.width))pt"
                )
            }
        }
    }

    @Test("A filled hero photo never reports a size wider than it was offered")
    func heroArtworkReportsOnlyTheProposedSize() async throws {
        let climb = Self.climb
        let artworkURL = URL(filePath: NSTemporaryDirectory())
            .appending(path: "live-climb-hero-width-\(UUID().uuidString).png")
        ImageCache.shared.store(Self.heroPhoto, for: artworkURL)

        let proposed = CGSize(width: 200, height: 600)
        let recorded = SizeRecorder()

        try await RenderedScreen.host(
            ClimbArtworkView(
                climb: climb,
                variant: .hero,
                imageRepository: PrimedClimbImageRepository(url: artworkURL)
            )
            .onGeometryChange(for: CGSize.self) { $0.size } action: { recorded.size = $0 }
            .frame(width: proposed.width, height: proposed.height)
        ) { screen in
            try await Self.waitForHeroPhoto(on: screen)

            let size = try #require(recorded.size, "the artwork laid out")
            #expect(
                size == proposed,
                "a photo filling \(proposed) reported \(size): the overflow is what pushes every sibling off screen"
            )
        }
    }

    // MARK: - The planted photo

    /// A solid magenta photograph, landscape the way climb heroes are, so a pixel read can tell
    /// the loaded photo from the tier-coloured placeholder that renders while it loads.
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

    /// Plants the photo in the climb-image disk cache under the key the shipping repository
    /// resolves first, so the session view's default loader finds it without Storage.
    private static func plantHeroPhoto(for climb: Climb) throws -> String {
        let key = "climb-images/\(climb.id)/v\(climb.imageSetVersion)/hero.heic"
        let data = try #require(heroPhoto.pngData(), "the planted photo encodes")
        _ = try DiskAssetCache.climbImages.store(data, for: key)
        return key
    }

    /// Waits until the magenta photo is painted behind the screen's centre. Every assertion in
    /// this suite is vacuous against the placeholder, which never overflows, so a screen that
    /// never shows the photo is a failed read rather than a passed one.
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
        id: "just-me-photo-background-width-tower",
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

    @MainActor
    private final class SizeRecorder {
        var size: CGSize?
    }

    private struct PrimedClimbImageRepository: ClimbImageRepository {
        let url: URL

        func resolveImageURL(for climb: Climb, variant: ClimbImageVariant) async -> URL? {
            url
        }
    }
}

private extension RGBA {
    /// Magenta under any of the session's black scrims: red and blue both well clear of green.
    var isMagentaHued: Bool {
        Int(red) > Int(green) + 40 && Int(blue) > Int(green) + 40
    }
}
