import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Sharing a saved climb has to publish the rank the climber earned.
///
/// The captain's report, reproduced against staging's own numbers: an Empire State Building climb
/// finished in 16:46 over 1,576 steps, ranked 32nd of 85 by the server. Opening its completion
/// summary showed that rank; opening the share composer from the saved climb offered no rank
/// cluster, no rank sticker and a recap card with an empty top-right corner - because Workout
/// Detail built the composer with no rank at all.
///
/// The two symptoms have one cause, and these tests prove that rather than assume it: the picker's
/// clusters and the recap card's rank tab both read the single rank pair the composer is
/// constructed with, so restoring that pair restores both, and withholding it drops both cleanly.
@MainActor
struct SavedClimbShareRankTests {
    private static let context = LiveReplayLeaderboardContext.liveClimb(
        climbId: "empire-state-building",
        targetSteps: 1_576
    )
    private static let workoutId = "1181618B-AD09-4B2B-AB93-C53B9188E210"

    // MARK: - The saved path resolves a standing

    /// The frozen standing this device already holds is served without a request, so opening the
    /// composer from a climb whose summary has been read never waits on the network.
    @Test
    func aStoredFrozenStandingReachesTheSavedClimbShareCardWithoutARequest() async {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.freeze(Self.snapshot(), contextKey: Self.context.contextKey)

        let leaderboard = StubLiveReplayLeaderboardService()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let standing = await SavedClimbShareStanding.resolve(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )

        #expect(standing == SavedClimbShareStanding(snapshot: Self.snapshot()))
        #expect(standing?.rank == 32)
        #expect(standing?.totalClimbers == 85)
        #expect(leaderboard.completionRankSnapshotFetchCount == 0, "a stored standing was refetched")
    }

    /// A device that has never opened this climb's summary still shares its rank: the one shared
    /// read path fetches the server snapshot once and freezes it.
    @Test
    func aStandingNeverReadOnThisDeviceIsFetchedOnceAndFrozen() async {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let leaderboard = StubLiveReplayLeaderboardService()
        leaderboard.completionRankSnapshot = Self.snapshot()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let first = await SavedClimbShareStanding.resolve(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )
        let second = await SavedClimbShareStanding.resolve(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )

        #expect(first?.rank == 32)
        #expect(second == first, "the second read disagreed with the frozen answer")
        #expect(leaderboard.completionRankSnapshotFetchCount == 1)
        #expect(
            store.snapshot(contextKey: Self.context.contextKey, workoutId: Self.workoutId)?.rank == 32
        )
    }

    /// A workout the server ranks nowhere stays unranked. Nothing is invented locally, and nothing
    /// is frozen, so the share card drops its rank rather than showing a placeholder.
    @Test
    func aClimbTheServerHasNotRankedResolvesToNoStanding() async {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let leaderboard = StubLiveReplayLeaderboardService()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let standing = await SavedClimbShareStanding.resolve(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )

        #expect(standing == nil)
        #expect(store.snapshot(contextKey: Self.context.contextKey, workoutId: Self.workoutId) == nil)
    }

    /// The only standing a share card withholds is one the server never wrote. A snapshot that
    /// exists always carries a usable pair - `LiveReplayCompletionRankSnapshot` clamps both halves
    /// to at least one - so there is no half-populated case for a card to render around.
    @Test
    func onlyAnAbsentSnapshotIsAnAbsentStanding() throws {
        #expect(SavedClimbShareStanding(snapshot: nil) == nil)

        let clamped = try #require(SavedClimbShareStanding(snapshot: Self.snapshot(rank: 0)))
        #expect(clamped.rank == 1)
        #expect(clamped.totalClimbers == 85)
    }

    // MARK: - What that standing restores in the composer

    /// The Climb tab offers the rank cluster and both rank stickers once the saved path supplies
    /// the standing, and the recap card can build its rank tab from the same pair.
    @Test
    func theResolvedStandingRestoresTheRankClusterStickersAndRecapTab() throws {
        let standing = try #require(SavedClimbShareStanding(snapshot: Self.snapshot()))
        let viewModel = Self.savedClimbViewModel(standing: standing)

        #expect(
            viewModel.availablePresets().contains { $0.id == "rank" },
            "the Climb tab offered no rank cluster"
        )
        #expect(viewModel.climbStats().contains { $0.kind == .climbRank })
        #expect(viewModel.climbStats().contains { $0.kind == .climbRankWithTotal })

        let resolved = try #require(
            ResolvedShareStanding(rank: standing.rank, totalClimbers: standing.totalClimbers)
        )
        #expect(resolved.ordinalRank == "32nd")
        #expect(resolved.formattedFieldSize == "85")
        #expect(
            ShareCardTemplateStore().templates(for: [.climb, .standing]).contains { $0.id == "standing" },
            "the Recaps tab dropped the standing card for a ranked climb"
        )
    }

    /// The pre-fix state, pinned: with no rank the same view model offers no rank cluster, no rank
    /// stickers, and the recap requirements exclude `.standing` - so the standing template drops out
    /// rather than rendering a hollow frame. Both symptoms, one missing pair.
    @Test
    func withoutAStandingBothTheClusterAndTheRecapTabDropCleanly() {
        let viewModel = Self.savedClimbViewModel(standing: nil)

        #expect(viewModel.availablePresets().allSatisfy { $0.id != "rank" })
        #expect(viewModel.climbStats().allSatisfy { $0.kind != .climbRank })
        #expect(viewModel.climbStats().allSatisfy { $0.kind != .climbRankWithTotal })
        #expect(ResolvedShareStanding(rank: nil, totalClimbers: nil) == nil)
        #expect(
            ShareCardTemplateStore().templates(for: [.climb]).allSatisfy { $0.id != "standing" },
            "an unranked climb was offered a standing card with nothing to fill it"
        )
        // The other recap templates still stand; only their rank tab is withheld.
        #expect(!ShareCardTemplateStore().templates(for: [.climb]).isEmpty)
    }

    /// The background is not part of the answer: a camera-roll photograph does not change which
    /// stats resolve, so the rank cards stay on offer against the climber's own picture.
    @Test
    func aCameraRollBackgroundKeepsTheRankCardsOnOffer() throws {
        let standing = try #require(SavedClimbShareStanding(snapshot: Self.snapshot()))
        let viewModel = Self.savedClimbViewModel(standing: standing)
        let onArtwork = viewModel.availablePresets().map(\.id)

        viewModel.background = .photo(Self.photograph())
        let onPhoto = viewModel.availablePresets().map(\.id)

        #expect(onPhoto == onArtwork)
        #expect(onPhoto.contains("rank"))
    }

    // MARK: - A standing that lands after the composer opens

    /// The composer opens on the frame Share was tapped, so the standing is applied to a view model
    /// that is already on screen. Every derived value has to be dropped with it: a cluster list, a
    /// sticker list or a resolved standing computed while the rank was missing would keep answering
    /// the old question for the whole presentation.
    @Test
    func aStandingAppliedAfterTheComposerOpensRestoresTheClusterAndBothStickers() throws {
        let viewModel = Self.savedClimbViewModel(standing: nil)
        #expect(viewModel.availablePresets().allSatisfy { $0.id != "rank" })
        #expect(viewModel.climbStats().allSatisfy { $0.kind != .climbRank })

        let standing = try #require(SavedClimbShareStanding(snapshot: Self.snapshot()))
        viewModel.setClimbRank(standing.rank, total: standing.totalClimbers)

        #expect(
            viewModel.availablePresets().contains { $0.id == "rank" },
            "the standing landed and the Climb tab still offered no rank cluster"
        )
        #expect(viewModel.climbStats().contains { $0.kind == .climbRank })
        #expect(viewModel.climbStats().contains { $0.kind == .climbRankWithTotal })
        #expect(
            ResolvedShareStanding(
                rank: viewModel.climbRank,
                totalClimbers: viewModel.climbRankTotal
            ) != nil,
            "the recap card could not build the standing it renders its rank tab from"
        )
    }

    // MARK: - Only a frozen standing reaches a card

    /// A card publishes; a screen reports. The completion summary keeps showing where the climber
    /// stands right now, and it forwards a rank to the composer only when that rank is the
    /// permanent one - so a climb the server has not ranked yet shares without a rank rather than
    /// printing today's position onto an image that outlives it.
    @Test
    func onlyAFrozenSummaryStandingIsForwardedToTheCard() throws {
        let recomputed = try #require(Self.hero(
            standings: [LiveClimbSummaryRankHero.Standing(rank: 34, total: 91, basis: .current)]
        ))
        #expect(recomputed.value == .rank(34), "the summary stopped showing the current standing")
        let recomputedStanding = try #require(recomputed.standing)
        #expect(recomputedStanding.frozen == nil)

        let session = try #require(
            LiveClimbSummaryRankHero.Standing(rank: 3, total: 8, basis: .liveSession)
        )
        #expect(session.frozen == nil)

        let frozen = try #require(Self.hero(
            standings: [
                LiveClimbSummaryRankHero.Standing(rank: 32, total: 85, basis: .atCompletion),
                LiveClimbSummaryRankHero.Standing(rank: 34, total: 91, basis: .current)
            ]
        ))
        let frozenStanding = try #require(frozen.standing?.frozen)
        #expect(frozenStanding.rank == 32)
        #expect(frozenStanding.renderableTotal == 85)
    }

    // MARK: - What the Share tap hands over

    /// The tap seeds from what this device already holds, so a climb whose standing has been read
    /// once reaches the composer's first frame: no request, and nothing to await.
    @Test
    func aStoredStandingIsSeededSynchronouslyAndWithoutARequest() throws {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.freeze(Self.snapshot(), contextKey: Self.context.contextKey)

        let leaderboard = StubLiveReplayLeaderboardService()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let seeded = try #require(SavedClimbShareStanding.stored(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        ))

        #expect(seeded.rank == 32)
        #expect(seeded.totalClimbers == 85)
        #expect(leaderboard.completionRankSnapshotFetchCount == 0, "the seed reached the network")
    }

    /// A device that has never read this climb's standing seeds nothing, which is what sends the
    /// composer's own read after it. Nothing is invented locally to fill the gap.
    @Test
    func aStandingThisDeviceHasNeverReadSeedsNothing() {
        let (store, defaults, suiteName) = Self.frozenStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let leaderboard = StubLiveReplayLeaderboardService()
        leaderboard.completionRankSnapshot = Self.snapshot()
        let service = CompletedClimbRankService(leaderboardService: leaderboard, store: store)

        let seeded = SavedClimbShareStanding.stored(
            context: Self.context,
            workoutId: Self.workoutId,
            service: service
        )

        #expect(seeded == nil)
        #expect(leaderboard.completionRankSnapshotFetchCount == 0)
    }

    // MARK: - A recap redrawn for a late standing

    /// The redraw swaps the baked image and nothing else. A climber who placed stickers on the card
    /// while the read was out keeps them: routing this through the canvas reset that a fresh
    /// background gets would wipe their work to fix a missing rank tab, which is the worse trade.
    @Test
    func redrawingAnAppliedRecapKeepsEverythingTheClimberPlacedOnIt() throws {
        let viewModel = Self.savedClimbViewModel(standing: nil)
        let baked = Self.card(.darkGray)
        viewModel.resetForNewBackground(.recap(baked))
        viewModel.addSticker(kind: .steps)
        let placed = try #require(viewModel.stickers.first)

        let redrawn = Self.card(.systemTeal)
        viewModel.replaceRecapBackground(redrawn)

        guard case .recap(let shown)? = viewModel.background else {
            Issue.record("the canvas lost its recap background")
            return
        }
        #expect(shown === redrawn, "the applied card was not redrawn")
        #expect(viewModel.stickers.map(\.id) == [placed.id], "the redraw wiped the climber's work")
    }

    /// Only a recap is redrawn. A stale template cannot repaint over the photograph a climber
    /// picked afterwards.
    @Test
    func redrawingLeavesANonRecapBackgroundAlone() {
        let viewModel = Self.savedClimbViewModel(standing: nil)
        let photo = Self.card(.darkGray)
        viewModel.resetForNewBackground(.photo(photo))

        viewModel.replaceRecapBackground(Self.card(.systemTeal))

        guard case .photo(let shown)? = viewModel.background else {
            Issue.record("the canvas lost the photograph the climber picked")
            return
        }
        #expect(shown === photo)
    }

    // MARK: - The card itself

    /// The reported symptom and its fix on the artifact a climber actually posts.
    ///
    /// The other tests judge which cards are offered; this one renders the recap through the
    /// shipping template view, the way the composer bakes it, and photographs both halves: the card
    /// Workout Detail used to build, with its top-right corner empty, and the same card once the
    /// frozen standing lands. Cheap on purpose - `ImageRenderer`, no window hosting, because hosting
    /// a window is what put `iOS Verify (Staging)` past its cap.
    @Test
    func theRecapCardDrawsItsRankTabOnceTheStandingLands() throws {
        let viewModel = Self.savedClimbViewModel(standing: nil)
        let template = try #require(
            ShareCardTemplateStore(bundle: .main).templates(for: [.climb]).first { $0.id == "result" }
        )

        let withoutRank = try #require(Self.renderRecapCard(template, for: viewModel))
        Self.write(withoutRank, "saved-climb-recap-card-1-without-rank")

        let standing = try #require(SavedClimbShareStanding(snapshot: Self.snapshot()))
        viewModel.setClimbRank(standing.rank, total: standing.totalClimbers)
        let withRank = try #require(Self.renderRecapCard(template, for: viewModel))
        Self.write(withRank, "saved-climb-recap-card-2-with-rank")

        #expect(
            try Self.rankTabCornerDiffers(withoutRank, withRank),
            "the standing landed and the card's rank corner was drawn exactly as it was without one"
        )
    }

    // MARK: - Fixtures

    private static func hero(
        standings: [LiveClimbSummaryRankHero.Standing?]
    ) -> LiveClimbSummaryRankHero? {
        LiveClimbSummaryRankHero.make(
            isClimbContext: true,
            standings: standings,
            sync: LiveClimbSummaryRankHero.SyncState(
                phase: .published,
                hasRankContext: true,
                rankResolution: .settled
            ),
            copy: LiveClimbSummaryRankHero.Copy()
        )
    }


    private static func savedClimbViewModel(
        standing: SavedClimbShareStanding?
    ) -> ShareComposerViewModel {
        ShareComposerViewModel(
            workout: ShareStatClusterPresetTests.recordedWorkout(
                name: "Empire State Building",
                trackingMode: .liveClimb,
                climbId: Climb.preview.id,
                heartRate: true,
                recordedSteps: 1_576
            ),
            measurementSystem: .imperial,
            stepHeight: MeasurementSystem.imperial.defaultStepHeight,
            climb: .preview,
            climbName: Climb.preview.name,
            climbRank: standing?.rank,
            climbRankTotal: standing?.totalClimbers
        )
    }

    /// A one-colour image stands in for the camera roll: this suite judges which cards are offered,
    /// not how they read, so the pixels are irrelevant and a bundled photograph would only make the
    /// test slower.
    private static func photograph() -> UIImage {
        card(.darkGray)
    }

    private static func card(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 120, height: 214)).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 120, height: 214)))
        }
    }

    private static func frozenStore(
        _ name: String = #function
    ) -> (FrozenCompletionRankStore, UserDefaults, String) {
        let suiteName = "SavedClimbShareRankTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (FrozenCompletionRankStore(defaults: defaults), defaults, suiteName)
    }

    /// Staging's own `completionSnapshots` document for the climb the captain reported.
    private static func snapshot(
        rank: Int = 32,
        completedCount: Int = 85
    ) -> LiveReplayCompletionRankSnapshot {
        LiveReplayCompletionRankSnapshot(
            workoutId: workoutId,
            rank: rank,
            completedCount: completedCount,
            completionDurationSeconds: 1_006,
            rankedAt: Date(timeIntervalSince1970: 1_787_859_963),
            rankingMetric: "completionDurationSeconds",
            tiePolicy: "competition_rank_equal_durations_share_rank"
        )
    }

    // MARK: - Rendering the card

    /// The recap exactly as the composer bakes it: the same template view, over the same context
    /// `makeRecapPreview` builds, at the size the share button exports.
    private static func renderRecapCard(
        _ template: ShareCardTemplate,
        for viewModel: ShareComposerViewModel
    ) -> UIImage? {
        let context = ShareCardRenderContext.template(
            stats: viewModel.climbStats(),
            bestEfforts: viewModel.bestEffortStats,
            weeklyTotals: viewModel.weeklyTotalStats,
            splits: viewModel.splits(),
            standing: ResolvedShareStanding(
                rank: viewModel.climbRank,
                totalClimbers: viewModel.climbRankTotal
            )
        )
        let size = ShareComposerExporter.exportSize
        let card = ShareCardTemplateView(template: template, context: context, artwork: heroArtwork)
            .frame(width: size.width, height: size.height)
            .clipped()
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The bundled Empire State photograph stands in for the climb's hosted hero artwork, which a
    /// test cannot download.
    private static var heroArtwork: ShareCardArtworkSource {
        let image = UIImage(named: "OnboardingLandmarkEmpireCard")
        return ShareCardArtworkSource(overrides: image.map { [.hero: $0] } ?? [:])
    }

    /// Whether the corner the rank tab lives in was drawn differently. Read from the pixels rather
    /// than from the render context, because what the card publishes is the image.
    private static func rankTabCornerDiffers(_ before: UIImage, _ after: UIImage) throws -> Bool {
        let corner = CGRect(
            x: before.size.width / 2,
            y: 0,
            width: before.size.width / 2,
            height: before.size.height / 4
        )
        return try pixels(of: before, in: corner) != pixels(of: after, in: corner)
    }

    private static func pixels(of image: UIImage, in rect: CGRect) throws -> [UInt8] {
        let cropped = try #require(image.cgImage?.cropping(to: rect))
        let width = cropped.width
        let height = cropped.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw EvidenceError.noBitmapContext
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private enum EvidenceError: Error { case noBitmapContext }

    private static func write(_ image: UIImage, _ name: String) {
        guard let data = image.pngData() else { return }
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            .map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory
        let url = directory.appending(path: "\(name).png")
        try? data.write(to: url)
        print("evidence: \(url.path())")
    }
}
