import CoreGraphics
import Foundation
import Testing

@testable import AscendApp

/// The geometry behind the photographic climb-progress reveal: which climbs carry a cut-out, how
/// a cut-out is fitted without stretching, and where the reveal line lands for a given number of
/// recorded steps.
struct ClimbProgressArtworkTests {
    static let pilotClimbIDs = ["empire-state-building", "eiffel-tower", "charminar"]

    /// A climb's cut-out as the bundled catalog (the hosted catalog's twin) describes it.
    static func catalogArtwork(_ climbID: String) -> ClimbProgressArtwork? {
        BundledClimbCatalog.climbs.first { $0.id == climbID }?.progressArtwork
    }

    // MARK: - Catalog

    @Test("Every live climb's catalog entry carries a usable cut-out in its own Storage folder")
    func everyLiveClimbHasACutOut() throws {
        let live = BundledClimbCatalog.climbs.filter { $0.releaseState == .available }
        #expect(live.count == 59, "the bundled catalog has \(live.count) live climbs")
        for climb in live {
            let artwork = try #require(climb.progressArtwork, "\(climb.id) is live but its catalog entry has no progressArtwork")
            #expect(artwork.isUsable(forClimbID: climb.id), "\(climb.id)'s progressArtwork is not usable")
            #expect(artwork.path == "climb-images/\(climb.id)/progress/v1.png")
            #expect(artwork.sha256?.count == 64, "\(climb.id) has no SHA-256 to verify its download against")
        }
    }

    @Test("A climb whose entry has no cut-out resolves to nothing, keeping its ordinary Just Me layout")
    func climbsWithoutACutOutResolveToNil() {
        #expect(BundledClimbCatalog.climbs.first { $0.id == "the-shard" }?.progressArtwork == nil)
    }

    @Test("A malformed entry is unusable rather than drawn misaligned")
    func malformedEntriesAreUnusable() {
        #expect(!Self.artwork(progressTopY: 0.9, progressBottomY: 0.1).isUsable(forClimbID: "fixture"))
        #expect(!Self.artwork(bounds: .init(left: 0, top: 0, right: 2_000, bottom: 100)).isUsable(forClimbID: "fixture"))
        #expect(!Self.artwork(bounds: .init(left: 10, top: 10, right: 10, bottom: 50)).isUsable(forClimbID: "fixture"))
        #expect(!Self.artwork(progressTopY: 0.0, progressBottomY: 1.0).isUsable(forClimbID: "fixture"))
        #expect(!Self.artwork(progressTopY: .nan, progressBottomY: 1.0).isUsable(forClimbID: "fixture"))
        #expect(Self.artwork().isUsable(forClimbID: "fixture"))
    }

    @Test("An entry can only point at its own climb's artwork folder")
    func pathIsConfinedToTheClimbsFolder() {
        #expect(!Self.artwork(path: "climb-images/other-climb/progress/v1.png").isUsable(forClimbID: "fixture"))
        #expect(!Self.artwork(path: "climb-images/fixture/../other/progress/v1.png").isUsable(forClimbID: "fixture"))
        #expect(!Self.artwork(path: "users/abc/progress.png").isUsable(forClimbID: "fixture"))
        #expect(!Self.artwork(path: "climb-images/fixture-2/progress/v1.png").isUsable(forClimbID: "fixture"))
    }

    @Test("A malformed progressArtwork costs that climb its cut-out, never the catalog")
    func malformedEntryDoesNotBreakTheClimb() throws {
        let json = """
        {"id": "fixture", "name": "Fixture", "city": "C", "country": "X", "continent": "Y", "latitude": 0, "longitude": 0,
         "totalHeightMeters": 100, "totalHeightFeet": 328, "realClimbableHeightMeters": null, "realClimbableHeightFeet": null,
         "totalSteps": 550, "realStairCount": 500, "calculatedFloors": 25, "category": "tower", "tier": "bronze",
         "tags": [], "funFact": "F", "sourceURL": "https://example.com", "releaseState": "available",
         "progressArtwork": {"path": 7}}
        """
        let climb = try JSONDecoder().decode(Climb.self, from: Data(json.utf8))
        #expect(climb.id == "fixture")
        #expect(climb.progressArtwork == nil)
    }

    @Test("A climb's cut-out survives the catalog's disk-cache round trip")
    func progressArtworkRoundTrips() throws {
        let climb = try #require(BundledClimbCatalog.climbs.first { $0.id == "sky-tower-wroclaw" })
        let decoded = try JSONDecoder().decode(Climb.self, from: JSONEncoder().encode(climb))
        #expect(decoded.progressArtwork == climb.progressArtwork)
        #expect(decoded.progressArtwork?.layoutOverride == "side-by-side")
    }

    // MARK: - Layout selection

    @Test(
        "Each landmark near the threshold gets the layout decided for it, pins included",
        arguments: [
            ("empire-state-building", ClimbProgressLayout.sideBySide),
            ("ufo-tower-bratislava", .sideBySide),     // 0.519
            ("torre-reforma", .sideBySide),            // 0.531
            ("sky-tower-bucharest", .sideBySide),      // 0.538
            ("eiffel-tower", .sideBySide),             // 0.559
            ("sky-tower-wroclaw", .sideBySide),        // 0.596, pinned: a single tower
            ("charminar", .stacked),                   // 0.607
            ("dc-tower-1", .sideBySide),               // 0.615, pinned: a single tower
            ("petronas-towers", .stacked),             // 0.636
            ("merdeka-118", .stacked),                 // 0.690
            ("tokyo-tower", .stacked),                 // 0.761
            ("st-peters-basilica", .stacked),          // 0.970
        ]
    )
    func landmarkLayouts(climbID: String, expected: ClimbProgressLayout) throws {
        let artwork = try #require(Self.catalogArtwork(climbID))
        #expect(artwork.layout == expected, "\(climbID) at aspect \(artwork.visibleAspectRatio)")
    }

    @Test(
        "Without a pin, a landmark at least 0.58 as wide as it is tall stacks and a narrower one stands beside the metrics",
        arguments: [
            (visibleWidth: 238, expected: ClimbProgressLayout.sideBySide),
            (visibleWidth: 579, expected: .sideBySide),
            (visibleWidth: 580, expected: .stacked),
            (visibleWidth: 607, expected: .stacked),
            (visibleWidth: 1_000, expected: .stacked),
        ]
    )
    func aspectRuleChoosesTheLayout(visibleWidth: Int, expected: ClimbProgressLayout) {
        #expect(Self.squareCanvasArtwork(visibleWidth: visibleWidth).layout == expected)
    }

    @Test("A manifest pin overrides the aspect rule in both directions")
    func manifestPinOverridesTheRule() {
        #expect(Self.squareCanvasArtwork(visibleWidth: 300, layout: "stacked").layout == .stacked)
        #expect(Self.squareCanvasArtwork(visibleWidth: 900, layout: "side-by-side").layout == .sideBySide)
    }

    @Test("A pin that names no layout is ignored and the aspect rule decides", arguments: ["diagonal", "", "Stacked", "side_by_side"])
    func invalidPinFallsBackToTheRule(pin: String) {
        #expect(Self.squareCanvasArtwork(visibleWidth: 300, layout: pin).layout == .sideBySide)
        #expect(Self.squareCanvasArtwork(visibleWidth: 900, layout: pin).layout == .stacked)
    }

    @Test("The manifest's optional layout key decodes as the pin, and its absence as no pin")
    func layoutKeyDecodes() throws {
        func decode(_ layout: String?) throws -> ClimbProgressArtwork {
            let layoutField = layout.map { #", "layout": "\#($0)""# } ?? ""
            let json = """
            {"path": "climb-images/fixture/progress/v1.png", "canvasWidth": 1000, "canvasHeight": 1000,
             "visibleBoundsPixels": {"left": 0, "top": 0, "right": 300, "bottom": 1000},
             "progressTopY": 0, "progressBottomY": 1\(layoutField)}
            """
            return try JSONDecoder().decode(ClimbProgressArtwork.self, from: Data(json.utf8))
        }

        #expect(try decode(nil).layoutOverride == nil)
        #expect(try decode(nil).layout == .sideBySide)
        #expect(try decode("stacked").layoutOverride == "stacked")
        #expect(try decode("stacked").layout == .stacked)
        #expect(try decode("diagonal").layout == .sideBySide)
    }

    // MARK: - Progress fraction

    @Test(
        "Completed steps over total steps is clamped to 0-100% and never divides by a bad total",
        arguments: [
            (completed: 0, total: Int?.some(1_000), expected: 0.0),
            (completed: 250, total: Int?.some(1_000), expected: 0.25),
            (completed: 1_000, total: Int?.some(1_000), expected: 1.0),
            (completed: 1_500, total: Int?.some(1_000), expected: 1.0),
            (completed: -20, total: Int?.some(1_000), expected: 0.0),
            (completed: 300, total: Int?.some(0), expected: 0.0),
            (completed: 300, total: Int?.some(-5), expected: 0.0),
            (completed: 300, total: Int?.none, expected: 0.0),
        ]
    )
    func fractionIsSafe(completed: Int, total: Int?, expected: Double) {
        #expect(ClimbProgressFraction.resolve(completedSteps: completed, totalSteps: total) == expected)
    }

    @Test("A non-finite fraction reads as zero")
    func nonFiniteFractionIsZero() {
        #expect(ClimbProgressFraction.clamped(.nan) == 0)
        #expect(ClimbProgressFraction.clamped(.infinity) == 0)
    }

    // MARK: - Layout

    @Test("The landmark keeps its measured proportions wherever it is fitted", arguments: pilotClimbIDs)
    func landmarkIsNeverStretched(climbID: String) throws {
        let artwork = try #require(Self.catalogArtwork(climbID))
        let visibleAspect = Double(artwork.visibleBoundsPixels.width) / Double(artwork.visibleBoundsPixels.height)

        for available in [CGSize(width: 160, height: 420), CGSize(width: 185, height: 560), CGSize(width: 60, height: 60)] {
            let layout = ClimbProgressArtworkLayout(artwork: artwork, fitting: available)
            let drawnAspect = layout.displaySize.width / layout.displaySize.height
            #expect(abs(drawnAspect - visibleAspect) < 0.0001, "\(climbID) drawn at \(layout.displaySize) in \(available)")
            #expect(layout.displaySize.width <= available.width + 0.0001)
            #expect(layout.displaySize.height <= available.height + 0.0001)
            #expect(
                abs(layout.displaySize.width - available.width) < 0.0001
                    || abs(layout.displaySize.height - available.height) < 0.0001,
                "\(climbID) fills neither dimension of \(available)"
            )
        }
    }

    @Test("Charminar draws shorter than the towers at the same width")
    func charminarIsShorterAtTheSameWidth() throws {
        let width = CGSize(width: 150, height: 10_000)
        func height(_ id: String) throws -> CGFloat {
            let artwork = try #require(Self.catalogArtwork(id))
            return ClimbProgressArtworkLayout(artwork: artwork, fitting: width).displaySize.height
        }

        let charminar = try height("charminar")
        #expect(charminar < (try height("eiffel-tower")))
        #expect(charminar < (try height("empire-state-building")))
    }

    @Test("The reveal line sits on the landmark's base at 0% and its tip at 100%", arguments: pilotClimbIDs)
    func markerSpansBaseToTip(climbID: String) throws {
        let artwork = try #require(Self.catalogArtwork(climbID))
        let layout = ClimbProgressArtworkLayout(artwork: artwork, fitting: CGSize(width: 170, height: 460))
        let canvasHeight = CGFloat(artwork.canvasHeight)
        let top = CGFloat(artwork.visibleBoundsPixels.top)

        let expectedBase = (artwork.progressBottomY * canvasHeight - top) * layout.scale
        let expectedTip = (artwork.progressTopY * canvasHeight - top) * layout.scale
        #expect(abs(layout.markerY(progress: 0) - expectedBase) < 0.001)
        #expect(abs(layout.markerY(progress: 1) - expectedTip) < 0.001)

        // The pilot manifests put the base and tip on the visible bounds' own edges, so the line
        // runs the full height of the drawn landmark.
        #expect(abs(layout.markerY(progress: 0) - layout.displaySize.height) < 0.5 * layout.scale + 0.001)
        #expect(abs(layout.markerY(progress: 1)) < 0.5 * layout.scale + 0.001)

        #expect(abs(layout.markerY(progress: 0.5) - (expectedBase + expectedTip) / 2) < 0.001)
        #expect(layout.markerY(progress: 2) == layout.markerY(progress: 1))
        #expect(layout.markerY(progress: -1) == layout.markerY(progress: 0))
    }

    @Test("A finished climb is coloured to the very top of the image")
    func finishedClimbRevealsEverything() {
        let layout = ClimbProgressArtworkLayout(
            artwork: Self.artwork(bounds: .init(left: 0, top: 0, right: 100, bottom: 200), progressTopY: 0.2, progressBottomY: 0.9),
            fitting: CGSize(width: 100, height: 200)
        )
        #expect(layout.markerY(progress: 1) == 40)
        #expect(layout.revealTop(progress: 1) == 0)
        #expect(layout.revealTop(progress: 0.5) == layout.markerY(progress: 0.5))
    }

    @Test("A zero-size proposal lays out as nothing rather than trapping")
    func zeroProposalIsSafe() {
        let layout = ClimbProgressArtworkLayout(artwork: Self.artwork(), fitting: .zero)
        #expect(layout.displaySize == .zero)
        #expect(layout.markerY(progress: 0.5) == 0)
    }

    /// A 1000x1000 canvas whose visible landmark fills its full height at `visibleWidth`, so
    /// the visible aspect is exactly `visibleWidth / 1000`.
    private static func squareCanvasArtwork(visibleWidth: Int, layout: String? = nil) -> ClimbProgressArtwork {
        ClimbProgressArtwork(
            path: "climb-images/fixture/progress/v1.png",
            canvasWidth: 1_000,
            canvasHeight: 1_000,
            visibleBoundsPixels: .init(left: 0, top: 0, right: visibleWidth, bottom: 1_000),
            progressTopY: 0,
            progressBottomY: 1,
            layoutOverride: layout
        )
    }

    private static func artwork(
        path: String = "climb-images/fixture/progress/v1.png",
        bounds: ClimbProgressArtwork.PixelBounds = .init(left: 10, top: 20, right: 90, bottom: 180),
        progressTopY: Double = 0.1,
        progressBottomY: Double = 0.9
    ) -> ClimbProgressArtwork {
        ClimbProgressArtwork(
            path: path,
            canvasWidth: 100,
            canvasHeight: 200,
            visibleBoundsPixels: bounds,
            progressTopY: progressTopY,
            progressBottomY: progressBottomY
        )
    }
}
