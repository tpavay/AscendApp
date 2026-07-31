import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the rank-hero labelling fix, taken off the real screen.
///
/// The reported contradiction: a CN Tower Live Climb summary read
/// "CLIMB RANK / 1st of 1 / LIVE CLIMB COMPLETE" while the climb detail read
/// "50 completed". Both numbers were right - the hero showed the standing the
/// server froze when the attempt published, the detail counts every finisher
/// since - but nothing in the hero said so, so the two read as comparable.
///
/// These tests host the shipping `LiveClimbCompletionSummaryView` in a real
/// `UIWindow`, screenshot it the way a device screen recording would, and read
/// the copy back out of the pixels with Vision. Nothing is reproduced from
/// source: the label, the value, the "of N" and the detail line all come from
/// `LiveClimbSummaryRankHero` through the view's own `rankingSection`.
///
/// The standing is handed in through the view's caller-supplied slot, which is
/// the only rank source a test can drive - the frozen snapshot reaches the view
/// from `LiveClimbPublicResultSyncStore.shared`, a Firestore-backed singleton
/// with no injection point. Same `Basis`, same `standings` resolution, same
/// rendered `Text`, so the pixels are the pixels the climb surface produces.
/// The climb slot is left `nil` for the same reason, with the climb wording
/// supplied through the overrides the routine surface already uses.
///
/// PNGs land in `ASCEND_EVIDENCE_DIR` when set, the test host's temp dir
/// otherwise; the path is logged either way.
@MainActor
struct LiveClimbSummaryRankHeroRenderEvidenceTests {
    /// The captain's row, verified against staging: the frozen snapshot holds
    /// rank 1 / completedCount 1 from 2026-06-11.
    private static let frozenRank = 1
    private static let frozenTotal = 1

    /// What the same attempt computes against today's rows - the counterfactual
    /// run with the snapshot doc absent.
    private static let currentRank = 29
    private static let currentTotal = 50

    @Test
    func frozenStandingNamesItselfOnScreenInsteadOfClaimingTheSessionCompleted() async throws {
        let reported = try render(
            basis: .liveSession,
            rank: Self.frozenRank,
            total: Self.frozenTotal,
            moment: .retrospective
        )
        let fixed = try render(
            basis: .atCompletion,
            rank: Self.frozenRank,
            total: Self.frozenTotal,
            moment: .retrospective
        )

        let reportedText = try await recognizedText(in: reported)
        let fixedText = try await recognizedText(in: fixed)

        // The reported screen, rendered: a frozen "1st of 1" under copy that
        // describes the session, which invites comparison with "50 completed".
        #expect(reportedText.contains("climb rank"))
        #expect(reportedText.contains("1st"))
        #expect(reportedText.contains("live climb complete"))

        // After the fix the same figure names the population it was measured
        // against, and stops claiming to be a current standing.
        #expect(fixedText.contains("climb rank"))
        #expect(fixedText.contains("1st"))
        #expect(fixedText.contains("rank when you finished"))
        #expect(!fixedText.contains("live climb complete"))
        #expect(!fixedText.contains("current leaderboard rank"))

        // The "of N" renders at 13pt beside a 44pt ordinal and OCR reads it
        // unreliably ("of 1" comes back as "ofi"), so the denominator the view
        // renders is pinned on the hero itself.
        #expect(renderedHero(basis: .atCompletion, rank: Self.frozenRank, total: Self.frozenTotal)?.total == 1)

        try writeEvidence(image: reported, named: "live-climb-summary-rank-hero-reported.png")
        try writeEvidence(image: fixed, named: "live-climb-summary-rank-hero-fixed.png")
    }

    @Test
    func freshCompletionSaysTheRankWasJustEarned() async throws {
        let fresh = try render(
            basis: .atCompletion,
            rank: Self.frozenRank,
            total: Self.frozenTotal,
            moment: .freshCompletion
        )

        let freshText = try await recognizedText(in: fresh)

        #expect(freshText.contains("rank you just earned"))
        #expect(!freshText.contains("live climb complete"))

        try writeEvidence(image: fresh, named: "live-climb-summary-rank-hero-fresh.png")
    }

    /// The counterfactual the investigation ran against real staging rows: with
    /// the frozen snapshot absent the hero falls through to the recomputed rank,
    /// which agrees with the climb detail's 50 - and says which one it is.
    @Test
    func recomputedStandingIsLabelledAsTheCurrentLeaderboardRank() async throws {
        let current = try render(
            basis: .current,
            rank: Self.currentRank,
            total: Self.currentTotal,
            moment: .retrospective
        )

        let currentText = try await recognizedText(in: current)

        #expect(currentText.contains("29th"))
        #expect(currentText.contains("current leaderboard rank"))
        #expect(!currentText.contains("live climb complete"))
        #expect(renderedHero(basis: .current, rank: Self.currentRank, total: Self.currentTotal)?.total == 50)

        try writeEvidence(image: current, named: "live-climb-summary-rank-hero-current.png")
    }

    /// One sheet a reviewer can read end to end: the reported screen, the same
    /// screen after the fix, the fresh-completion wording, and the recomputed
    /// standing that agrees with climb detail.
    @Test
    func proofSheetShowsEveryHeroBasisSideBySide() throws {
        let sheet = try renderProofSheet(
            panels: [
                (
                    "Reported · 2026-07-31",
                    "Frozen rank under session copy - reads as comparable with \"50 completed\"",
                    try heroStrip(basis: .liveSession, rank: Self.frozenRank, total: Self.frozenTotal, moment: .retrospective)
                ),
                (
                    "Fixed · saved summary",
                    "Same frozen figure, now named: it is the rank at the moment you finished",
                    try heroStrip(basis: .atCompletion, rank: Self.frozenRank, total: Self.frozenTotal, moment: .retrospective)
                ),
                (
                    "Fixed · just finished",
                    "Post-session tense of the same frozen basis",
                    try heroStrip(basis: .atCompletion, rank: Self.frozenRank, total: Self.frozenTotal, moment: .freshCompletion)
                ),
                (
                    "Fixed · no frozen snapshot",
                    "Falls through to the recomputed standing, which agrees with climb detail's 50",
                    try heroStrip(basis: .current, rank: Self.currentRank, total: Self.currentTotal, moment: .retrospective)
                )
            ]
        )

        try writeEvidence(image: sheet, named: "live-climb-summary-rank-hero-proof-sheet.png")
    }

    // MARK: - Rendering the shipping screen

    private func render(
        basis: LiveClimbSummaryRankHero.Basis,
        rank: Int,
        total: Int,
        moment: LiveClimbSummaryRankHero.Moment
    ) throws -> UIImage {
        let container = try makeContainer()
        let workout = makeWorkout()

        let screen = LiveClimbCompletionSummaryView(
            climb: nil,
            workout: workout,
            leaderboardRank: rank,
            leaderboardTotal: total,
            leaderboardRankBasis: basis,
            allowsRatingPrompt: false,
            // The hero only renders where there is a population to rank against, so the
            // screen needs a context even though the standing is handed in directly.
            leaderboardContext: .justClimbGlobal(targetSteps: 2_579),
            moment: moment,
            rankingLabelOverride: "CLIMB RANK",
            completedDetailOverride: "LIVE CLIMB COMPLETE",
            onDone: {}
        )
        .modelContainer(container)

        return try screenshot(of: screen)
    }

    /// The rank hero as it sits on the screen, cropped off a full screenshot so
    /// the proof sheet shows rendered pixels rather than a re-drawn copy.
    private func heroStrip(
        basis: LiveClimbSummaryRankHero.Basis,
        rank: Int,
        total: Int,
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
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()

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

        window.isHidden = true

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
            copy: LiveClimbSummaryRankHero.Copy(labelOverride: "CLIMB RANK")
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

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
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
                Text("Live Climb summary · rank hero")
                    .font(.montserratBold(size: 22))
                    .foregroundStyle(.white)

                Text("Screenshots of the shipping summary screen. The frozen standing and the recomputed one count different populations, so each names its own.")
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
