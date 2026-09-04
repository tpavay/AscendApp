import Foundation
import Observation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// The clusters photographed on the surface a climber taps them from.
///
/// `ShareStatClusterPresetEvidenceTests` exports what the shared image looks
/// like; nothing there shows the picker itself. This hosts the shipping
/// `ShareComposerView` in a phone-sized window through `RenderedScreen`, walks
/// it the way a climber does - pick a background, the add sheet opens on its
/// own - and photographs the GROUPS grid, then taps a group and photographs the
/// canvas it lands on. Photographs are written only under `ASCEND_EVIDENCE_DIR`.
///
/// The screens are the real ones: no stand-in sheet, no re-implemented tile.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ShareStatClusterPickerEvidenceTests {
    private static let screenSize = CGSize(width: 393, height: 852)

    @Test
    func theGroupsPickerAndAPlacedClusterArePhotographed() async throws {
        let defaultsSuite = "ShareStatClusterPickerEvidenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let walkthroughStore = ShareComposerWalkthroughStore(defaults: defaults)
        walkthroughStore.markSeen()

        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Live Climb",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true
        )
        context.insert(workout)
        try context.save()

        let composer = ShareComposerView(
            workout: workout,
            climb: .preview,
            climbRank: 4,
            climbRankTotal: 1_284,
            walkthroughStore: walkthroughStore
        )
        .modelContainer(container)

        try await hostComposer(composer) { screen in
            try await openTheAddSheet(on: screen)

            // A tile reads out everything it draws and ends on its own name, so
            // the labels below are also what a VoiceOver climber hears.
            let sheetLabels = try await settledAccessibilityElements(under: screen.window) {
                $0.contains { $0.accessibilityLabel?.hasSuffix("HERO") == true }
            }.compactMap(\.accessibilityLabel)
            #expect(
                ["HERO", "RANK", "ROW", "SPLITS", "RECEIPT", "MINIMAL",
                 "HR HERO", "HR ROW", "FULL GRID", "HR MINIMAL"].allSatisfy { title in
                    sheetLabels.contains { $0.hasSuffix(title) }
                },
                "the add sheet did not show every group. Saw: \(sheetLabels)"
            )
            try screen.photograph(named: "share-cluster-picker-1-groups-grid")

            // Tapping a group drops it on the canvas as one sticker.
            try activateAccessibilityElement(in: screen.window) {
                $0.accessibilityLabel?.hasSuffix(", SPLITS") == true
            }
            try await screen.settle(.turns(20))
            try screen.photograph(named: "share-cluster-picker-2-splits-placed")
        }
    }

    /// The captain's report and its fix, walked end to end on the surfaces that show them.
    ///
    /// One hosted session covers what three separate ones used to: the rank-less state he reported,
    /// the real `fullScreenCover` delivering a standing that lands behind the presented screen, and
    /// the Climb and Recaps tabs both gaining what they were missing. Merged deliberately - each
    /// test in this suite costs roughly three and a half minutes on a CI runner, where hosting a
    /// window is two orders of magnitude slower than it is locally, and three of them put
    /// `iOS Verify (Staging)` past its 45-minute cap.
    ///
    /// The before half is the reproduction: against a composer that never receives a standing -
    /// which is exactly what Workout Detail used to build - the Recaps tab has no Standing card and
    /// the Climb tab's grid has no RANK cluster. The after half is the fix, and it also proves the
    /// propagation the network path depends on: a plain parent view would only show that the
    /// composer adopts a changed input, not that the cover delivers one.
    ///
    /// It does not exercise `WorkoutDetailView` itself. What stops a new entry point from silently
    /// dropping rank again is that `ShareComposerView`'s rank parameters carry no defaults, so
    /// omitting them is a compile error.
    @Test
    func aSavedClimbOpensWithoutItsRankAndGainsItWhenTheStandingLands() async throws {
        let defaultsSuite = "ShareStatClusterPickerEvidenceTests-saved-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let walkthroughStore = ShareComposerWalkthroughStore(defaults: defaults)
        walkthroughStore.markSeen()

        let container = try Self.makeContainer()
        let workout = ShareStatClusterPresetTests.recordedWorkout(
            name: "Empire State Building",
            trackingMode: .liveClimb,
            climbId: Climb.preview.id,
            heartRate: true,
            recordedSteps: 1_576
        )
        container.mainContext.insert(workout)
        try container.mainContext.save()

        let frozenStore = FrozenCompletionRankStore(defaults: defaults)
        let workoutId = UUID()
        let pending = LateArrivingStanding()
        let host = SharePresentingHost(
            workout: workout,
            walkthroughStore: walkthroughStore,
            pending: pending
        )
        .modelContainer(container)

        try await hostComposer(host) { screen in
            try await awaitControl(labelled: "Recaps", in: screen.window)
            try activateAccessibilityElement(labelled: "Recaps", in: screen.window)

            // Waited for by content rather than by a clock: a read that lands before the grid has
            // drawn would pass the assertion below having pinned nothing, and that half is the
            // captain's reported symptom. The always-offered cards are what say the grid is up.
            let beforeLabels = try await settledAccessibilityElements(under: screen.window) {
                Self.recapGridIsPopulated($0)
            }.compactMap(\.accessibilityLabel)
            #expect(
                Self.namesEveryAlwaysOfferedRecap(beforeLabels),
                "the Recaps grid never drew, so nothing was pinned. Saw: \(beforeLabels)"
            )
            #expect(
                beforeLabels.allSatisfy { !$0.contains("Standing") },
                "a climb with no resolved standing was offered a Standing card. Saw: \(beforeLabels)"
            )

            pending.standing = await Self.fetchedStanding(workoutId: workoutId, in: frozenStore)

            let afterLabels = try await settledAccessibilityElements(under: screen.window) {
                $0.contains { $0.accessibilityLabel?.contains("Standing") == true }
            }.compactMap(\.accessibilityLabel)
            #expect(
                afterLabels.contains { $0.contains("Standing") },
                "the standing landed and the Recaps tab still had no Standing card. Saw: \(afterLabels)"
            )

            try await openTheAddSheet(on: screen)
            try await expectRankTile(in: screen.window, from: "sharing a saved climb")
            try screen.photograph(named: "share-cluster-picker-3-saved-climb-rank")
        }
    }

    // MARK: - Hosting

    /// Hosts the shipping composer in a phone-sized window through `RenderedScreen`, waits for
    /// its tree to arrive, and hands `body` the live screen; the window is torn down however
    /// `body` ends.
    private func hostComposer<Root: View>(
        _ root: Root,
        _ body: (HostedScreen) async throws -> Void
    ) async throws {
        try await RenderedScreen.host(root, size: Self.screenSize) { screen in
            _ = try await screen.elements()
            try await body(screen)
        }
    }

    /// The climber picks the climb's own artwork as a background; the add sheet then opens by
    /// itself, which is where the groups live. Searched from the window rather than the hosting
    /// controller's view so a composer presented in a cover is reachable too.
    private func openTheAddSheet(on screen: HostedScreen) async throws {
        try activateAccessibilityElement(labelled: "Presets", in: screen.window)
        try await screen.settle(.turns(10))
        try activateAccessibilityElement(in: screen.window) {
            $0.accessibilityLabel == Climb.preview.name && $0.accessibilityTraits.contains(.button)
        }
        try await screen.settle(.turns(24))
    }

    /// Waits for a control the composer only publishes once its own `.task` has run.
    private func awaitControl(labelled label: String, in window: UIWindow) async throws {
        _ = try await settledAccessibilityElements(under: window) {
            $0.contains { $0.accessibilityLabel == label }
        }
    }

    // MARK: - Fixtures

    private static let leaderboardContext = LiveReplayLeaderboardContext.liveClimb(
        climbId: Climb.preview.id,
        targetSteps: 1_576
    )

    /// Staging's own `completionSnapshots` document for the climb the captain shared: 32nd of 85.
    private static func stagingSnapshot(workoutId: UUID) -> LiveReplayCompletionRankSnapshot {
        LiveReplayCompletionRankSnapshot(
            workoutId: workoutId.uuidString,
            rank: 32,
            completedCount: 85,
            completionDurationSeconds: 1_006,
            rankedAt: Date(timeIntervalSince1970: 1_787_859_963),
            rankingMetric: "completionDurationSeconds",
            tiePolicy: "competition_rank_equal_durations_share_rank"
        )
    }

    /// What the cover's own read produces for a workout this install has never held a snapshot for:
    /// the server document, fetched once and frozen, arriving after the composer is on screen.
    private static func fetchedStanding(
        workoutId: UUID,
        in store: FrozenCompletionRankStore
    ) async -> SavedClimbShareStanding? {
        let leaderboard = StubLiveReplayLeaderboardService()
        leaderboard.completionRankSnapshot = stagingSnapshot(workoutId: workoutId)
        return await SavedClimbShareStanding.resolve(
            context: leaderboardContext,
            workoutId: workoutId.uuidString,
            service: CompletedClimbRankService(leaderboardService: leaderboard, store: store)
        )
    }

    /// The recap cards in the grid's first row, offered whatever the climb's standing is. Waiting
    /// on them says the grid has drawn, where waiting on a non-empty tree says only that something
    /// somewhere has.
    private static let alwaysOfferedRecapTitles = ["Result", "Poster"]

    private static func recapGridIsPopulated(_ elements: [NSObject]) -> Bool {
        namesEveryAlwaysOfferedRecap(elements.compactMap(\.accessibilityLabel))
    }

    private static func namesEveryAlwaysOfferedRecap(_ labels: [String]) -> Bool {
        alwaysOfferedRecapTitles.allSatisfy { title in
            labels.contains { $0.contains(title) }
        }
    }

    /// The tile reads out what it draws, so the frozen numbers have to be in it.
    private func expectRankTile(in window: UIWindow, from path: String) async throws {
        let sheetLabels = try await settledAccessibilityElements(under: window) {
            $0.contains { $0.accessibilityLabel?.hasSuffix("HERO") == true }
        }.compactMap(\.accessibilityLabel)
        let rankTile = sheetLabels.first { $0.hasSuffix("RANK") }
        #expect(
            rankTile != nil,
            "\(path) offered no RANK cluster. Saw: \(sheetLabels)"
        )
        #expect(
            rankTile?.contains("32") == true && rankTile?.contains("85") == true,
            "the RANK tile did not name the frozen standing. Saw: \(rankTile ?? "nothing")"
        )
    }

    private static func makeContainer() throws -> ModelContainer {
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
}

/// The standing Workout Detail is still reading when the composer opens.
@MainActor
@Observable
private final class LateArrivingStanding {
    var standing: SavedClimbShareStanding?
}

/// Stands in for the Share tap on Workout Detail, presentation included: the composer goes up in a
/// `fullScreenCover` before the frozen standing has been read, and the standing lands in the
/// presenter's state afterwards.
private struct SharePresentingHost: View {
    let workout: Workout
    let walkthroughStore: ShareComposerWalkthroughStore
    let pending: LateArrivingStanding
    @State private var isSharing = true

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .fullScreenCover(isPresented: $isSharing) {
                ShareComposerView(
                    workout: workout,
                    climb: .preview,
                    climbRank: pending.standing?.rank,
                    climbRankTotal: pending.standing?.totalClimbers,
                    walkthroughStore: walkthroughStore
                )
            }
    }
}
