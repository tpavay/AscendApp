import Foundation
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the ranking-and-ghost design the captain locked on
/// 2026-09-01.
///
/// Every image here is a screenshot of a shipping view hosted in a real
/// `UIWindow` - `LiveClimbSummaryRankHeroView` and `LiveReplayLeaderboardPanel` -
/// with the copy read back out of the pixels by Vision. Nothing is redrawn for
/// the test.
///
/// PNGs land in `ASCEND_EVIDENCE_DIR` when set, the test host's temp dir
/// otherwise; the path is logged either way.
@MainActor
@Suite(.hostsAWindow)
struct RankingGhostRenderEvidenceTests {
    typealias Hero = LiveClimbSummaryRankHero

    // MARK: - The finish card

    /// The case that parked the other task, rendered: five climbs on St. Peter's,
    /// today's run second-fastest, nobody else on the tower. The screen used to
    /// read `1st` over `FASTEST OF 1 CLIMBER`.
    @Test
    func aSoloSlowerRepeatShowsItsPlacingAmongTheClimbersOwnClimbs() async throws {
        let image = try screenshot(of: heroPanel(
            standing: Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
            personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
            moment: .freshCompletion
        ))
        let text = try await recognizedText(in: image)

        #expect(text.contains("of your 5 climbs"))
        #expect(!text.contains("climber"))
        #expect(!text.contains("fastest"))
        #expect(!text.contains("rank you just earned"))

        try writeEvidence(image: image, named: "finish-card-solo-slower-repeat.png")
    }

    /// The same component when the repeat was faster. One ordinal covers improved
    /// and not-improved, so there is no separate personal-best card.
    @Test
    func aSoloPersonalBestUsesTheSameCard() async throws {
        let image = try screenshot(of: heroPanel(
            standing: Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
            personalPlacing: PersonalClimbPlacing(ordinal: 1, total: 5),
            moment: .freshCompletion
        ))
        let text = try await recognizedText(in: image)

        #expect(text.contains("of your 5 climbs"))
        #expect(!text.contains("climber"))

        try writeEvidence(image: image, named: "finish-card-solo-personal-best.png")
    }

    /// The First Ascent card: the gold flag and the claim, and nothing else.
    @Test
    func aFirstAscentCardIsTheFlagAndTheClaim() async throws {
        let image = try screenshot(of: heroPanel(
            standing: Hero.Standing(rank: 1, total: 1, basis: .atCompletion),
            personalPlacing: PersonalClimbPlacing(ordinal: 1, total: 1),
            moment: .freshCompletion
        ))
        let text = try await recognizedText(in: image)

        #expect(text.contains("first ascent claimed"))
        #expect(!text.contains("climber"))
        #expect(!text.contains("of your"))

        try writeEvidence(image: image, named: "finish-card-first-ascent.png")
    }

    /// A real field of climbers keeps the leaderboard rank in the hero, with the
    /// field named beneath it exactly as it ships today.
    @Test
    func aRealFieldKeepsTheLeaderboardRankInTheHero() async throws {
        let image = try screenshot(of: heroPanel(
            standing: Hero.Standing(rank: 2, total: 2, basis: .atCompletion),
            personalPlacing: PersonalClimbPlacing(ordinal: 2, total: 5),
            moment: .freshCompletion
        ))
        let text = try await recognizedText(in: image)

        #expect(text.contains("fastest of 2 climbers"))
        #expect(!text.contains("of your 5 climbs"))

        try writeEvidence(image: image, named: "finish-card-rival-repeat.png")
    }

    // MARK: - The live board

    /// The marker while the climber is behind their own best: one line inside
    /// their own row, no rank cell of its own, and no number anywhere near it.
    ///
    /// The line is measured off the pixels rather than read: it lands on the same
    /// progress scale the row's own fill is drawn against, which is what makes
    /// the visible gap between them mean anything.
    @Test
    func theLiveBoardMarksThePreviousBestInsideTheClimbersOwnRow() async throws {
        let image = try screenshot(of: leaderboardPanel(currentSteps: 347, markerSteps: 414))
        let text = try await recognizedText(in: image)

        let markerX = try #require(markerColumnX(in: image), "no marker line was drawn")
        #expect(abs(markerX - expectedMarkerX(steps: 414)) <= 6)

        #expect(text.contains("347"))
        // Nothing states the gap. The visible distance is the whole message.
        #expect(!text.contains("catch"))
        #expect(!text.contains("steps ahead"))
        #expect(!text.contains("behind"))
        // The best is not a row: it takes no rank cell and shows no step count.
        #expect(!text.contains("414"))

        try writeEvidence(image: image, named: "live-board-previous-best-behind.png")
    }

    /// The same board once the climber has passed their own best. The line is in
    /// the identical place and looks identical - which side the fill sits on is
    /// the entire signal - and the standings did not move, because the best never
    /// held one.
    @Test
    func passingThePreviousBestChangesTheGapAndNothingElse() async throws {
        let behind = try screenshot(of: leaderboardPanel(currentSteps: 347, markerSteps: 414))
        let image = try screenshot(of: leaderboardPanel(currentSteps: 470, markerSteps: 414))
        let text = try await recognizedText(in: image)

        let behindMarkerX = try #require(markerColumnX(in: behind))
        let passedMarkerX = try #require(markerColumnX(in: image), "no marker line was drawn")
        #expect(abs(passedMarkerX - behindMarkerX) <= 2)
        #expect(abs(passedMarkerX - expectedMarkerX(steps: 414)) <= 6)

        #expect(text.contains("470"))
        #expect(!text.contains("catch"))
        #expect(!text.contains("414"))

        try writeEvidence(image: image, named: "live-board-previous-best-passed.png")
    }

    /// Early in the race both the climber and their best are near the start, so
    /// the marker sits over the row's leading chrome. Evidence that the state is
    /// legible rather than assumed.
    @Test
    func theMarkerStaysLegibleEarlyInTheRace() async throws {
        let image = try screenshot(of: leaderboardPanel(currentSteps: 22, markerSteps: 48))

        try writeEvidence(image: image, named: "live-board-previous-best-early.png")
    }

    // MARK: - The Just Me rail

    /// The same marker turned on its side (JM-G): one horizontal line at the
    /// height the previous best reached, `BEST` above it, narrowed to the track.
    /// No step count, no delta, no comparison sentence.
    @Test
    func theJustMeRailCarriesTheSameMarkerTurnedOnItsSide() async throws {
        let image = try screenshot(
            of: LiveClimbProgressRail(
                progress: 347.0 / 551,
                previousBestProgress: 414.0 / 551,
                summitSteps: 551
            )
            .frame(width: 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 24)
            .background(Color.black)
        )
        let text = try await recognizedText(in: image)

        #expect(text.contains("summit"))
        #expect(text.contains("551"))
        #expect(text.contains("start"))
        // The marker states no number of its own.
        #expect(!text.contains("414"))
        #expect(!text.contains("347"))
        #expect(!text.contains("catch"))

        try writeEvidence(image: image, named: "just-me-rail-previous-best.png")
    }

    // MARK: - Measuring the marker

    /// Where the marker's line should land: the panel's own horizontal padding
    /// plus the row's share of the same step scale its progress fill uses.
    private func expectedMarkerX(steps: Int) -> CGFloat {
        let rowWidth = Self.screenSize.width - (Self.panelPadding * 2)
        return Self.panelPadding + rowWidth * (CGFloat(steps) / 551)
    }

    /// The x of the tallest near-white vertical run inside the row band.
    ///
    /// The scan is confined to the row and to its trailing half, where the only
    /// white the panel draws is the marker itself: the rank cell and the step
    /// count are lime, the `YOU` pill is black on lime, and the climber's name
    /// sits well to the left of the band.
    private func markerColumnX(in image: UIImage) -> CGFloat? {
        guard let cgImage = image.cgImage else { return nil }

        let scale = Int(image.scale)
        let width = cgImage.width
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * cgImage.height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: cgImage.height))

        let firstColumn = Int(Self.screenSize.width * 0.45) * scale
        var tallest = (column: -1, height: 0)

        for column in firstColumn..<width {
            var height = 0
            for row in (Self.rowBandTop * scale)..<(Self.rowBandBottom * scale) {
                let offset = row * bytesPerRow + column * bytesPerPixel
                let isNearWhite = pixels[offset] > 200
                    && pixels[offset + 1] > 200
                    && pixels[offset + 2] > 200
                if isNearWhite { height += 1 }
            }
            if height > tallest.height {
                tallest = (column, height)
            }
        }

        // A stroked 2pt line fills most of the band; a stacked letter does not.
        let bandHeight = (Self.rowBandBottom - Self.rowBandTop) * scale
        guard tallest.column >= 0, tallest.height > bandHeight / 2 else { return nil }

        return CGFloat(tallest.column) / CGFloat(scale)
    }

    /// A band comfortably inside the single row this panel draws, below the
    /// header rule and above the field-size line.
    private static let rowBandTop = 135
    private static let rowBandBottom = 185
    private static let panelPadding: CGFloat = 16

    // MARK: - Rendering

    private func heroPanel(
        standing: Hero.Standing?,
        personalPlacing: PersonalClimbPlacing?,
        moment: Hero.Moment
    ) throws -> some View {
        let hero = try #require(Hero.make(
            isClimbContext: true,
            moment: moment,
            standings: [standing],
            personalPlacing: personalPlacing,
            sync: Hero.SyncState(
                phase: .published,
                hasRankContext: true,
                rankResolution: .settled
            ),
            copy: Hero.Copy()
        ))

        return LiveClimbSummaryRankHeroView(
            hero: hero,
            rankingMetric: .fastestCompletion,
            fieldPopulation: .climbers,
            onRetrySync: {}
        )
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private func leaderboardPanel(currentSteps: Int, markerSteps: Int) -> some View {
        let rows = [
            CrossUserIdentityAdapter.replayRow(
                LiveReplayLeaderboardRow.currentUser(
                    rank: 1,
                    steps: currentSteps,
                    displayName: "Tyler P."
                ),
                blockedUserIds: [],
                isBlockListHydrated: true
            )
        ]

        return LiveReplayLeaderboardPanel(
            rows: rows,
            progressScaleSteps: 551,
            targetStepGoal: 551,
            progress: min(Double(currentSteps) / 551, 1),
            currentUserPhotoURL: nil,
            previousBestStepsAtBucket: markerSteps,
            fetchFailed: false,
            field: LiveReplayFieldSize(population: .climbers, count: 1),
            tint: .accent,
            effectiveColorScheme: .dark,
            showsFilter: false
        )
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private static let screenSize = CGSize(width: 393, height: 400)

    private func screenshot(of view: some View) throws -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(origin: .zero, size: Self.screenSize)

        // A window with no scene is never handed to the render server, and
        // `drawHierarchy` then captures an empty surface - so borrow the test
        // host's own scene.
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window = scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
        window.frame = CGRect(origin: .zero, size: Self.screenSize)
        window.overrideUserInterfaceStyle = .dark

        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.rootViewController = controller
        // Visible but never key: this capture is synchronous and shares the scene
        // with the other window-hosting evidence suites.
        window.isHidden = false

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: Self.screenSize, format: format)
        return renderer.image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
    }

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: name)
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("Rendered ranking-ghost evidence: \(url.path())")
    }
}
