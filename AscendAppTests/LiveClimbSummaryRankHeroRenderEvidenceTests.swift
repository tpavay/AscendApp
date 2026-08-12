import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the completion summary's rank-first hierarchy.
///
/// These tests host the shipping `LiveClimbCompletionSummaryView` in a real
/// `UIWindow`, screenshot it the way a device screen recording would, and read
/// the copy back out of the pixels with Vision. Nothing is reproduced from
/// source: the ordinal, the field line and any board label all come from
/// `LiveClimbSummaryRankHero` through the view's own rank hero.
///
/// The standing is handed in through the view's caller-supplied slot, which is
/// the only rank source a test can drive - the frozen snapshot reaches the view
/// from `LiveClimbPublicResultSyncStore.shared`, a Firestore-backed singleton
/// with no injection point. Same `Basis`, same `standings` resolution, same
/// rendered `Text`, so the pixels are the pixels the climb surface produces.
/// The climb slot is left `nil` for the same reason, with the session's own
/// completion wording supplied through the override the live surfaces pass.
///
/// PNGs land in `ASCEND_EVIDENCE_DIR` when set, the test host's temp dir
/// otherwise; the path is logged either way.
@MainActor
@Suite(.hostsAWindow)
struct LiveClimbSummaryRankHeroRenderEvidenceTests {
    /// The captain's row, verified against staging: the frozen snapshot holds
    /// rank 1 / completedCount 1 from 2026-06-11.
    private static let frozenRank = 1
    private static let frozenTotal = 1

    /// What the same attempt computes against today's rows - the counterfactual
    /// run with the snapshot doc absent.
    private static let currentRank = 29
    private static let currentTotal = 50

    /// A standing measured against a field the hero can name states that ordering
    /// once, in plain language, with no label row repeating the ordinal in words.
    @Test
    func aStandingWithAFieldSizeStatesThatFieldInPlainLanguage() async throws {
        let fixed = try render(
            basis: .atCompletion,
            rank: Self.frozenRank,
            total: Self.frozenTotal,
            moment: .retrospective
        )

        let fixedText = try await recognizedText(in: fixed)

        #expect(fixedText.contains("fastest of 1"))
        #expect(!fixedText.contains("climb rank"))
        #expect(!fixedText.contains("rank when you finished"))
        #expect(!fixedText.contains("current leaderboard rank"))

        // Vision can read the large first-place ordinal as "lst", so the model assertion
        // pins that value while the rendered field line verifies the denominator.
        #expect(renderedHero(basis: .atCompletion, rank: Self.frozenRank, total: Self.frozenTotal)?.standing?.rank == 1)
        #expect(renderedHero(basis: .atCompletion, rank: Self.frozenRank, total: Self.frozenTotal)?.total == 1)

        try writeEvidence(image: fixed, named: "live-climb-summary-rank-hero-fixed.png")
    }

    /// A live session's population is its own race window, which the hero cannot
    /// characterise. Pairing that rank with a field ordering would assert a placement
    /// the screen cannot substantiate, so the session's own completion copy stands.
    @Test
    func aLiveSessionStandingNeverClaimsAFieldOrdering() async throws {
        let reported = try render(
            basis: .liveSession,
            rank: Self.frozenRank,
            total: Self.frozenTotal,
            moment: .retrospective
        )

        let reportedText = try await recognizedText(in: reported)

        #expect(reportedText.contains("live climb complete"))
        #expect(!reportedText.contains("fastest"))
        #expect(!reportedText.contains("most steps"))

        try writeEvidence(image: reported, named: "live-climb-summary-rank-hero-reported.png")
    }

    /// The denominator is genuinely optional - a routine board with no window, a
    /// publish status that froze a rank without a count. A bare "FASTEST" under the
    /// ordinal would read as a claim to have won it, so the basis wording stands
    /// instead, in the tense the moment calls for.
    @Test
    func aStandingWithNoFieldSizeFallsBackToTheBasisWording() async throws {
        let fresh = try render(
            basis: .atCompletion,
            rank: 4,
            total: nil,
            moment: .freshCompletion
        )
        let saved = try render(
            basis: .atCompletion,
            rank: 4,
            total: nil,
            moment: .retrospective
        )

        let freshText = try await recognizedText(in: fresh)
        let savedText = try await recognizedText(in: saved)

        #expect(freshText.contains("rank you just earned"))
        #expect(!freshText.contains("fastest"))
        #expect(savedText.contains("rank when you finished"))
        #expect(!savedText.contains("fastest"))

        try writeEvidence(image: fresh, named: "live-climb-summary-rank-hero-fresh.png")
        try writeEvidence(image: saved, named: "live-climb-summary-rank-hero-no-field-size.png")
    }

    /// A routine ranks on a board of its own, so it keeps the label that names it
    /// and the completion copy that describes its session.
    @Test
    func aRoutineStandingKeepsItsOwnBoardAndCompletionCopy() async throws {
        let image = try render(
            basis: .liveSession,
            rank: 3,
            total: 18,
            moment: .freshCompletion,
            labelOverride: "ROUTINE RANK",
            completedDetailOverride: "ROUTINE COMPLETE"
        )

        let text = try await recognizedText(in: image)

        #expect(text.contains("routine rank"))
        #expect(text.contains("routine complete"))
        #expect(text.contains("3rd"))
        #expect(!text.contains("fastest"))

        try writeEvidence(image: image, named: "routine-summary-rank-hero.png")
    }

    /// The counterfactual the investigation ran against real staging rows: with
    /// the frozen snapshot absent the hero falls through to the recomputed rank,
    /// which agrees with the climb detail's 50 - and states that field plainly.
    @Test
    func aRecomputedStandingStatesItsFieldWithoutJargon() async throws {
        let current = try render(
            basis: .current,
            rank: Self.currentRank,
            total: Self.currentTotal,
            moment: .retrospective
        )

        let currentText = try await recognizedText(in: current)

        #expect(currentText.contains("29th"))
        #expect(currentText.contains("fastest of 50"))
        #expect(!currentText.contains("current leaderboard rank"))
        #expect(!currentText.contains("climb rank"))
        #expect(renderedHero(basis: .current, rank: Self.currentRank, total: Self.currentTotal)?.total == 50)

        #expect(currentText.contains("cn tower live climb"))
        #expect(!currentText.contains("summary"))
        #expect(appearsBefore("29th", "total steps", in: currentText))
        #expect(currentText.contains("81 avg spm"))
        #expect(!currentText.contains("avg 81 spm"))
        #expect(occurrenceCount(of: "avg spm", in: currentText) == 1)
        #expect(appearsBefore("share", "done", in: currentText))

        try writeEvidence(image: current, named: "live-climb-summary-rank-hero-current.png")
    }

    /// One sheet a reviewer can read end to end: the frozen standing that can name
    /// its field, the live session that cannot, the standing with no denominator,
    /// and the recomputed standing that agrees with climb detail.
    @Test
    func proofSheetShowsEveryHeroBasisSideBySide() throws {
        let sheet = try renderProofSheet(
            panels: [
                (
                    "Saved summary",
                    "The rank is the result, followed by one plain-language field line",
                    try heroStrip(basis: .atCompletion, rank: Self.frozenRank, total: Self.frozenTotal, moment: .retrospective)
                ),
                (
                    "Session standing",
                    "A live session cannot name its own field, so it never claims one",
                    try heroStrip(basis: .liveSession, rank: Self.frozenRank, total: Self.frozenTotal, moment: .retrospective)
                ),
                (
                    "No field size",
                    "With no denominator the basis wording stands rather than a bare superlative",
                    try heroStrip(basis: .atCompletion, rank: 4, total: nil, moment: .freshCompletion)
                ),
                (
                    "Current standing",
                    "A recomputed standing still states its field without jargon",
                    try heroStrip(basis: .current, rank: Self.currentRank, total: Self.currentTotal, moment: .retrospective)
                )
            ]
        )

        try writeEvidence(image: sheet, named: "live-climb-summary-rank-hero-proof-sheet.png")
    }

    @Test
    func aSettledRankWithoutAStandingKeepsTheUnresolvedStateVisible() async throws {
        let hero = try #require(
            LiveClimbSummaryRankHero.make(
                isClimbContext: true,
                standings: [],
                sync: LiveClimbSummaryRankHero.SyncState(
                    phase: nil,
                    hasRankContext: true,
                    rankResolution: .settled
                ),
                copy: LiveClimbSummaryRankHero.Copy()
            )
        )
        let image = try screenshot(
            of: LiveClimbSummaryRankHeroView(
                hero: hero,
                rankingMetric: .fastestCompletion,
                onRetrySync: {}
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        )
        let text = try await recognizedText(in: image)

        #expect(text.contains("check leaderboard later"))
        #expect(!text.contains("climb rank"))
        #expect(!text.contains("fastest"))

        try writeEvidence(image: image, named: "live-climb-summary-rank-unresolved.png")
    }

    @Test
    func aStepsBasedStandingNamesTheBasisThatActuallyRanksIt() async throws {
        let hero = try #require(
            LiveClimbSummaryRankHero.make(
                isClimbContext: false,
                standings: [
                    LiveClimbSummaryRankHero.Standing(rank: 3, total: 18, basis: .current)
                ],
                sync: LiveClimbSummaryRankHero.SyncState(
                    phase: nil,
                    hasRankContext: true,
                    rankResolution: .settled
                ),
                copy: LiveClimbSummaryRankHero.Copy()
            )
        )
        let image = try screenshot(
            of: LiveClimbSummaryRankHeroView(
                hero: hero,
                rankingMetric: .mostSteps,
                onRetrySync: {}
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        )
        let text = try await recognizedText(in: image)

        #expect(text.contains("3rd"))
        #expect(text.contains("most steps of 18"))
        #expect(!text.contains("fastest"))

        try writeEvidence(image: image, named: "routine-summary-rank-most-steps.png")
    }

    // MARK: - Rendering the shipping screen

    private func render(
        basis: LiveClimbSummaryRankHero.Basis,
        rank: Int,
        total: Int?,
        moment: LiveClimbSummaryRankHero.Moment,
        labelOverride: String? = nil,
        completedDetailOverride: String? = "LIVE CLIMB COMPLETE"
    ) throws -> UIImage {
        let container = try makeContainer()
        let workout = makeWorkout()

        let screen = LiveClimbCompletionSummaryView(
            climb: nil,
            workout: workout,
            leaderboardRank: rank,
            leaderboardTotal: total,
            leaderboardRankBasis: basis,
            // The hero only renders where there is a population to rank against, so the
            // screen needs a context even though the standing is handed in directly.
            leaderboardContext: .justClimbGlobal(targetSteps: 2_579),
            moment: moment,
            rankingLabelOverride: labelOverride,
            completedDetailOverride: completedDetailOverride,
            onDone: { _ in }
        )
        .modelContainer(container)

        return try screenshot(of: screen)
    }

    /// The rank hero as it sits on the screen, cropped off a full screenshot so
    /// the proof sheet shows rendered pixels rather than a re-drawn copy.
    private func heroStrip(
        basis: LiveClimbSummaryRankHero.Basis,
        rank: Int,
        total: Int?,
        moment: LiveClimbSummaryRankHero.Moment
    ) throws -> UIImage {
        let full = try render(basis: basis, rank: rank, total: total, moment: moment)
        return try crop(full, to: CGRect(x: 0, y: 115, width: Self.screenSize.width, height: 135))
    }

    private static let screenSize = CGSize(width: 393, height: 852)

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

        // The summary carries a `@Query`, so a host left mounted keeps observing SwiftData after
        // its container has gone. It then traps on the next save any other suite performs, which
        // takes the whole test process down.
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        window.rootViewController = controller
        // Visible but never key: this capture is synchronous and shares the scene with the other
        // window-hosting evidence suites, and taking key out from under one mid-flight leaves its
        // appearance transition open forever.
        window.isHidden = false

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // SwiftUI commits its first frame on the next runloop turn; without this
        // the window draws empty.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: Self.screenSize, format: format)
        let image = renderer.image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }

        return image
    }

    private func crop(_ image: UIImage, to rect: CGRect) throws -> UIImage {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        let scale = image.scale
        let scaled = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        let cropped = try #require(cgImage.cropping(to: scaled), "Crop fell outside the image")
        return UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
    }

    private func renderProofSheet(panels: [(String, String, UIImage)]) throws -> UIImage {
        let renderer = ImageRenderer(content: RankHeroProofSheet(panels: panels))
        renderer.scale = 2
        return try #require(renderer.uiImage, "ImageRenderer produced no proof sheet")
    }

    /// The hero the rendered screen resolves for the same inputs, for the parts
    /// of it that are too small to read back off the pixels reliably.
    private func renderedHero(
        basis: LiveClimbSummaryRankHero.Basis,
        rank: Int,
        total: Int
    ) -> LiveClimbSummaryRankHero? {
        let sources = LiveClimbSummaryRankHero.Sources(
            callerSupplied: LiveClimbSummaryRankHero.Standing(rank: rank, total: total, basis: basis)
        )

        return LiveClimbSummaryRankHero.make(
            isClimbContext: false,
            standings: LiveClimbSummaryRankHero.standings(isClimbContext: false, sources: sources),
            sync: LiveClimbSummaryRankHero.SyncState(
                phase: nil,
                hasRankContext: true,
                rankResolution: .settled
            ),
            copy: LiveClimbSummaryRankHero.Copy()
        )
    }

    // MARK: - Fixtures

    /// A CN Tower-shaped Live Climb: 144 floors, 2,579 steps, finished in 31:48.
    private func makeWorkout() -> Workout {
        Workout(
            name: "CN Tower Live Climb",
            duration: 1_908,
            steps: 2_579,
            floors: 144,
            caloriesBurned: 486,
            source: .headphoneMotion
        )
    }

    /// Held for the process, not per render. The summary carries a `@Query`, and SwiftUI keeps
    /// observing SwiftData for a beat after the host is torn down - against a container that has
    /// already gone, that observer traps on the next save any other suite performs.
    private static let container: ModelContainer? = try? ModelContainer(
        for: Workout.self,
        WorkoutSourceLink.self,
        WorkoutParticipation.self,
        ClimbAttempt.self,
        BestEffortCacheEntry.self,
        BestEffortCacheMetadata.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    private func makeContainer() throws -> ModelContainer {
        try #require(Self.container, "The evidence suite needs an in-memory model container")
    }

    // MARK: - Reading the rendered pixels back

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .lowercased()
    }

    private func appearsBefore(_ first: String, _ second: String, in text: String) -> Bool {
        guard let firstRange = text.range(of: first), let secondRange = text.range(of: second) else {
            return false
        }
        return firstRange.lowerBound < secondRange.lowerBound
    }

    private func occurrenceCount(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: name)
        try png.write(to: url)
        #expect(png.count > 5_000)
        print("Rendered rank-hero evidence: \(url.path())")
    }
}

/// Reviewer-facing sheet. Every panel image is a crop of a real screenshot of
/// `LiveClimbCompletionSummaryView`; only the captions are drawn here.
private struct RankHeroProofSheet: View {
    let panels: [(String, String, UIImage)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Live Climb summary - rank hero")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)

                Text("Screenshots of the shipping summary screen. Every time-based standing leads with the ordinal and follows with one plain-language field line.")
                    .font(.montserratMedium(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(panels.enumerated()), id: \.offset) { _, panel in
                VStack(alignment: .leading, spacing: 8) {
                    Text(panel.0)
                        .font(.montserratBold(size: 13))
                        .foregroundStyle(.accent)

                    Text(panel.1)
                        .font(.montserratMedium(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)

                    Image(uiImage: panel.2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 393)
                }
            }
        }
        .padding(28)
        .frame(width: 449)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
